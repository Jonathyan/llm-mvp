# Infrastructuur voor een veilige Azure Chatbot

Dit project implementeert een veilige, interne helpdesk-chatbot in Microsoft Azure. De infrastructuur wordt volledig als code gedefinieerd met **Bicep**, wat zorgt voor een consistente en herhaalbare uitrol.

De kern van de architectuur is een webapplicatie die draait op een virtuele machine (VM). Deze applicatie communiceert op een beveiligde manier met Azure's AI- en beveiligingsdiensten via een afgeschermd virtueel netwerk.

---
## Architectuur

De architectuur is ontworpen volgens het "defense in depth"-principe en bestaat uit de volgende componenten:

* **Virtual Network (VNet)**: Een geïsoleerd netwerk met twee subnets:
    * `public-subnet`: Bevat de webserver-VM en is beperkt toegankelijk vanaf het internet.
    * `private-subnet`: Is volledig afgeschermd en bevat de Private Endpoints voor de backend-diensten.
* **Virtual Machine (VM)**: Een Linux (Ubuntu) VM die de Streamlit-webapplicatie host. De VM is uitgerust met een **Managed Identity** voor veilige, wachtwoordloze authenticatie.
* **Azure OpenAI**: De AI-dienst die de chatfunctionaliteit levert. De toegang is vergrendeld en verloopt uitsluitend via een **Private Endpoint**.
* **Azure Key Vault**: Slaat de API-sleutel voor de OpenAI-dienst veilig op. Ook deze dienst is alleen toegankelijk via een **Private Endpoint**.
* **Network Security Group (NSG)**: Een firewall die het verkeer naar de VM controleert en alleen de noodzakelijke poorten (SSH en poort 8080) openstelt.

---
## Vereisten

Voordat je begint, zorg ervoor dat je de volgende tools hebt geïnstalleerd en geconfigureerd:

1.  **Azure CLI**: [Installatie-instructies](https://docs.microsoft.com/cli/azure/install-azure-cli)
2.  **Git**: [Installatie-instructies](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
3.  **Een SSH-sleutelpaar**: Je hebt de publieke sleutel (`id_rsa.pub`) nodig voor de implementatie. [Instructies voor het genereren van een SSH-sleutel](https://docs.microsoft.com/azure/virtual-machines/linux/mac-create-ssh-keys).



---
## Tree
.
├── main.bicep
├── modules/
│   ├── network.bicep
│   ├── vm.bicep
│   ├── backend.bicep
│   └── privateEndpoints.bicep
├── deploy.sh
└── architecture.d2

---
## Implementatie Stappen

### Stap 1: Kloon de Repository

Kloon de repository met alle Bicep- en applicatiebestanden naar je lokale machine.

```bash
git clone [https://github.com/jouw-gebruikersnaam/jouw-chatbot-repo.git](https://github.com/jouw-gebruikersnaam/jouw-chatbot-repo.git)
cd jouw-chatbot-repo
```

### Stap 2: Geen Externe Scripts Nodig

De applicatie wordt volledig inline geïnstalleerd via de VM Extension. Er zijn geen externe scripts of GitHub repositories nodig - alles zit ingebouwd in de Bicep templates.

### Stap 3: Rol de Infrastructuur uit

1.  Log in op Azure via de CLI:
    ```bash
    az login
    ```

2.  Maak een resourcegroep aan (of gebruik een bestaande):
    ```bash
    az group create --name JouwResourceGroep --location westeurope
    ```

3.  Rol de Bicep-template uit. Vervang de placeholder-waarden met je eigen gegevens.
    ```bash
    # Lees je publieke SSH-sleutel in een variabele
    SSH_KEY=$(cat ~/.ssh/id_rsa.pub)
    
    # Haal je publieke IP op voor SSH toegang
    MY_IP=$(curl -s ifconfig.me)/32
    
    # Start de deployment
    az deployment group create \
      --resource-group JouwResourceGroep \
      --template-file main.bicep \
      --parameters \
        adminUsername='azureuser' \
        adminSshKey="$SSH_KEY" \
        allowedSshSourceIp="$MY_IP"
    ```

De implementatie duurt enkele minuten. De VM Extension wacht 60 seconden na boot voordat de installatie begint om ervoor te zorgen dat het systeem volledig klaar is.

---
## Configuratie na Implementatie

Na de uitrol is er nog één handmatige stap nodig om de applicatie volledig functioneel te maken.

### Stap 1: Haal de Namen van je Resources op

Je hebt de naam van je Key Vault en OpenAI-service nodig. Deze kun je vinden via de CLI:

```bash
# Haal Key Vault naam op
KV_NAME=$(az keyvault list --resource-group JouwResourceGroep --query "[].name" -o tsv)
echo "Key Vault: $KV_NAME"

# Haal OpenAI service naam op
OAI_NAME=$(az cognitiveservices account list --resource-group JouwResourceGroep --query "[].name" -o tsv)
echo "OpenAI Service: $OAI_NAME"
```

### Stap 2: Configureer Key Vault Access Policy

Voeg jezelf toe aan de Key Vault access policy om secrets te kunnen beheren:

```bash
# Haal je eigen Object ID op
MY_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)

# Voeg jezelf toe aan Key Vault access policy
az keyvault set-policy \
  --name $KV_NAME \
  --object-id $MY_OBJECT_ID \
  --secret-permissions get set list delete
```

### Stap 3: Voeg OpenAI API-sleutel toe aan Key Vault

Automatisch via CLI:

```bash
# Haal OpenAI API key op
OAI_KEY=$(az cognitiveservices account keys list --name $OAI_NAME --resource-group JouwResourceGroep --query "key1" -o tsv)

# Voeg toe aan Key Vault
az keyvault secret set --vault-name $KV_NAME --name "OpenAI-API-Key" --value "$OAI_KEY"
```

### Stap 4: Implementeer een Model in OpenAI

#### Via Azure CLI (Aanbevolen):
```bash
# Deploy gpt-35-turbo model
az cognitiveservices account deployment create \
  --name $OAI_NAME \
  --resource-group JouwResourceGroep \
  --deployment-name "gpt-35-turbo" \
  --model-name "gpt-35-turbo" \
  --model-version "0613" \
  --model-format "OpenAI" \
  --sku-capacity 10 \
  --sku-name "Standard"

# Verificeer deployment
az cognitiveservices account deployment list \
  --name $OAI_NAME \
  --resource-group JouwResourceGroep \
  --query "[].{name:name,model:properties.model.name,status:properties.provisioningState}" \
  --output table
```

#### Via Azure Portal (Alternatief):
1.  Ga naar [Azure OpenAI Studio](https://oai.azure.com)
2.  Selecteer je OpenAI resource
3.  Navigeer naar **"Deployments"** → **"+ Create new deployment"**
4.  Model: **gpt-35-turbo**
5.  Deployment name: **gpt-35-turbo** (noteer deze naam!)
6.  Klik **"Deploy"**

**Belangrijk:** Zonder model deployment krijg je een 403 error in de chatbot!

### Stap 5: Configureer Environment Variables in VM Service

1.  Verbind met je VM via SSH:
    ```bash
    VM_IP=$(az vm show -d -g JouwResourceGroep -n vm-webserver --query publicIps -o tsv)
    ssh azureuser@$VM_IP
    ```

2.  Bewerk het service-bestand:
    ```bash
    sudo nano /etc/systemd/system/chatbot.service
    ```

3.  Voeg de `Environment`-regels toe onder de `[Service]` sectie:
    ```ini
    [Service]
    User=azureuser
    Group=azureuser
    WorkingDirectory=/home/azureuser
    # Voeg de volgende regels toe (vervang met je eigen resource-namen):
    Environment="KEY_VAULT_NAME=kv-jouw-unique-string"
    Environment="AZURE_OPENAI_SERVICE=oai-jouw-unique-string"
    Environment="AZURE_OPENAI_DEPLOYMENT=gpt-35-turbo"
    ExecStart=/usr/local/bin/streamlit run app.py --server.port 8080
    Restart=always
    ```

4.  Sla het bestand op (`Ctrl+X`, dan `Y`, dan `Enter`).

5.  Herlaad en herstart de service:
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart chatbot.service
    sudo systemctl status chatbot.service
    ```

### Stap 6: Test de Configuratie

```bash
# Test Managed Identity toegang tot Key Vault
curl -H "Metadata:true" "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://vault.azure.net/"

# Test OpenAI private endpoint connectiviteit
ssh azureuser@$VM_IP
python3 -c "import socket; print('OpenAI resolves to:', socket.gethostbyname('$OAI_NAME.openai.azure.com'))"
curl -v https://$OAI_NAME.openai.azure.com/

# Check service logs
sudo journalctl -u chatbot.service -f

# Verificeer model deployment
az cognitiveservices account deployment list --name $OAI_NAME --resource-group JouwResourceGroep --output table
```

### Troubleshooting

**Als je 403 errors krijgt:**
- Controleer of model deployment bestaat (Stap 4)
- Verificeer private endpoint connectiviteit (DNS moet naar 10.0.2.x resolven)
- Check environment variables in service

**Als ping naar private endpoint faalt:**
- Dit is normaal - ICMP wordt geblokkeerd
- Test met `telnet 10.0.2.x 443` in plaats daarvan

---
## Toegang tot de Applicatie

Open een webbrowser en navigeer naar het publieke IP-adres van je virtuele machine op poort 8080.

`http://PUBLIEK_IP_ADRES_VAN_VM:8080`

Je zou nu de interface van je helpdesk-chatbot moeten zien, klaar om je vragen te beantwoorden.


---
## Bronvermeldingen

Hier zijn de directe links naar de documentatie:

**Primaire Microsoft documentatie:**
- **Microsoft Learn Bicep**: https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/
- **Bicep reference**: https://docs.microsoft.com/en-us/azure/templates/
- **Azure Architecture Center**: https://docs.microsoft.com/en-us/azure/architecture/
- **Azure Well-Architected Framework**: https://docs.microsoft.com/en-us/azure/architecture/framework/

**Specifieke Azure services:**
- **Azure Virtual Machines**: https://docs.microsoft.com/en-us/azure/virtual-machines/
- **Azure Key Vault**: https://docs.microsoft.com/en-us/azure/key-vault/
- **Azure OpenAI Service**: https://docs.microsoft.com/en-us/azure/cognitive-services/openai/
- **Azure Virtual Network**: https://docs.microsoft.com/en-us/azure/virtual-network/
- **Private Endpoints**: https://docs.microsoft.com/en-us/azure/private-link/

**Community en voorbeelden:**
- **Azure QuickStart Templates**: https://github.com/Azure/azure-quickstart-templates
- **Bicep GitHub repository**: https://github.com/Azure/bicep
- **Azure CLI documentatie**: https://docs.microsoft.com/en-us/cli/azure/
- **Azure PowerShell**: https://docs.microsoft.com/en-us/powershell/azure/

**Community support:**
- **Stack Overflow Azure tag**: https://stackoverflow.com/questions/tagged/azure
- **Microsoft Tech Community**: https://techcommunity.microsoft.com/
- **Azure Updates**: https://azure.microsoft.com/en-us/updates/

**Bicep-specifieke resources:**
- **Bicep Playground**: https://bicepdemo.z22.web.core.windows.net/
- **Azure Resource Explorer**: https://resources.azure.com/

Deze links waren essentieel voor het ontwikkelen van de modulaire structuur en dependency management van de template.