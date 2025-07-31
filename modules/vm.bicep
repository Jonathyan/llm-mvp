// modules/vm.bicep
param location string
param subnetId string
param adminUsername string
param adminSshKey string

resource publicIp 'Microsoft.Network/publicIPAddresses@2023-05-01' = {
  name: 'pip-web-vm'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2023-05-01' = {
  name: 'nic-web-vm'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: subnetId
          }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'vm-webserver'
  location: location
  identity: {
    type: 'SystemAssigned' // Activeer Managed Identity
  }
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    osProfile: {
      computerName: 'webserver'
      adminUsername: adminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
        }
      ]
    }
  }
}

resource vmExtension 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: vm
  name: 'install-app-script'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    protectedSettings: {
      commandToExecute: '''
        # Wait for system to be fully ready and update dependencies
        sleep 60
        systemctl is-system-running --wait
        export DEBIAN_FRONTEND=noninteractive
        apt update
        apt install -y python3-pip
        
        # Create Python app
        cat > /home/azureuser/app.py << 'APPEOF'
import streamlit as st
import openai
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import os

# Configure page
st.set_page_config(page_title="Helpdesk Chatbot", page_icon="🤖")
st.title("🤖 Helpdesk Chatbot")

# Initialize Azure clients
@st.cache_resource
def get_openai_client():
    try:
        # Get credentials
        credential = DefaultAzureCredential()
        
        # Get Key Vault client
        key_vault_name = os.environ.get("KEY_VAULT_NAME")
        if not key_vault_name:
            st.error("KEY_VAULT_NAME environment variable not set")
            return None
            
        vault_url = f"https://{key_vault_name}.vault.azure.net/"
        secret_client = SecretClient(vault_url=vault_url, credential=credential)
        
        # Get OpenAI API key from Key Vault
        api_key = secret_client.get_secret("OpenAI-API-Key").value
        
        # Configure OpenAI client
        openai_service = os.environ.get("AZURE_OPENAI_SERVICE")
        if not openai_service:
            st.error("AZURE_OPENAI_SERVICE environment variable not set")
            return None
            
        client = openai.AzureOpenAI(
            api_key=api_key,
            api_version="2024-02-01",
            azure_endpoint=f"https://{openai_service}.openai.azure.com/"
        )
        return client
    except Exception as e:
        st.error(f"Error initializing OpenAI client: {str(e)}")
        return None

# Chat interface
if "messages" not in st.session_state:
    st.session_state.messages = []

# Display chat history
for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

# Chat input
if prompt := st.chat_input("Stel je vraag..."):
    # Add user message
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)
    
    # Get AI response
    with st.chat_message("assistant"):
        client = get_openai_client()
        if client:
            try:
                deployment_name = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-35-turbo")
                response = client.chat.completions.create(
                    model=deployment_name,
                    messages=[
                        {"role": "system", "content": "Je bent een behulpzame helpdesk assistent. Beantwoord vragen kort en duidelijk in het Nederlands."},
                        *[{"role": m["role"], "content": m["content"]} for m in st.session_state.messages]
                    ],
                    max_tokens=500,
                    temperature=0.7
                )
                
                assistant_response = response.choices[0].message.content
                st.markdown(assistant_response)
                st.session_state.messages.append({"role": "assistant", "content": assistant_response})
                
            except Exception as e:
                st.error(f"Error getting AI response: {str(e)}")
        else:
            st.error("OpenAI client not available")
APPEOF
        
        # Create requirements file
        cat > /home/azureuser/requirements.txt << 'REQEOF'
streamlit
openai
azure-identity
azure-keyvault-secrets
REQEOF
        
        # Install Python packages system-wide (already running as root)
        pip3 install -r /home/azureuser/requirements.txt
        
        # Fix file ownership for azureuser
        chown azureuser:azureuser /home/azureuser/app.py
        chown azureuser:azureuser /home/azureuser/requirements.txt
        
        # Create systemd service
        cat > /etc/systemd/system/chatbot.service << 'SERVICEEOF'
[Unit]
Description=Chatbot Streamlit Service
After=network.target

[Service]
User=azureuser
Group=azureuser
WorkingDirectory=/home/azureuser
ExecStart=/usr/local/bin/streamlit run app.py --server.port 8080
Restart=always

[Install]
WantedBy=multi-user.target
SERVICEEOF
        
        # Enable and start service
        systemctl daemon-reload
        systemctl enable chatbot.service
        systemctl start chatbot.service
      '''
    }
  }
}

output vmPrincipalId string = vm.identity.principalId
