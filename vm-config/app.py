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