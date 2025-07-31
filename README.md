# Infrastructuur voor een Veilige Azure Chatbot

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
* **Network Security Group (NSG)**: Een firewall die het verkeer naar de VM controleert en alleen de noodzakelijke poorten (SSH en HTTP) openstelt.

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
└── scripts/
    └── install-app.sh

---
## Implementatie Stappen

### Stap 1: Kloon de Repository

Kloon de repository met alle Bicep- en applicatiebestanden naar je lokale machine.

```bash
git clone [https://github.com/jouw-gebruikersnaam/jouw-chatbot-repo.git](https://github.com/jouw-gebruikersnaam/jouw-chatbot-repo.git)
cd jouw-chatbot-repo
```

### Stap 2: Upload het Installatiescript

Het `scripts/install-app.sh` script moet op een publiek toegankelijke URL staan zodat de VM het kan downloaden. Een eenvoudige manier is om het als een **publieke GitHub Gist** te uploaden.

1.  Ga naar [gist.github.com](https://gist.github.com).
2.  Plak de inhoud van `install-app.sh` in de Gist.
3.  Maak een "Public Gist".
4.  Klik op de "Raw"-knop en kopieer de URL. Deze URL heb je nodig in de volgende stap.

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
    
    # Start de deployment
    az deployment group create \
      --resource-group JouwResourceGroep \
      --template-file main.bicep \
      --parameters \
        adminUsername='azureuser' \
        adminSshKey="$SSH_KEY" \
        scriptUrl='DE_RUWE_URL_NAAR_JE_INSTALL_SCRIPT'
    ```

De implementatie duurt enkele minuten.

---
## Configuratie na Implementatie

Na de uitrol is er nog één handmatige stap nodig om de applicatie volledig functioneel te maken.

### Stap 1: Haal de Namen van je Resources op

Je hebt de naam van je Key Vault en OpenAI-service nodig. Deze kun je vinden in de Azure Portal of via de CLI:

```bash
# Haal de naam van de Key Vault op
az keyvault list --resource-group JouwResourceGroep --query "[].name" -o tsv

# Haal de naam van de OpenAI-service op
az cognitiveservices account list --resource-group JouwResourceGroep --query "[].name" -o tsv
```

### Stap 2: Voeg de OpenAI API-sleutel toe aan de Key Vault

1.  Navigeer in de Azure Portal naar je **OpenAI-service**.
2.  Ga naar **"Keys and Endpoint"** en kopieer een van de API-sleutels.
3.  Navigeer naar je **Key Vault**.
4.  Ga naar **"Secrets"** en klik op **"+ Generate/Import"**.
5.  Geef het geheim de naam **`OpenAI-API-Key`** (dit is hoofdlettergevoelig en moet exact overeenkomen).
6.  Plak de gekopieerde API-sleutel in het "Secret value"-veld.
7.  Klik op **"Create"**.

### Stap 3: Implementeer een Model in OpenAI

1.  Ga in de Azure Portal naar je **OpenAI-service** en open de **Azure OpenAI Studio**.
2.  Navigeer naar **"Deployments"**.
3.  Maak een nieuwe implementatie aan met een model zoals `gpt-35-turbo`.
4.  Noteer de **deployment name**. Deze heb je nodig voor de applicatieconfiguratie.

### Stap 4: Configureer en Herstart de Applicatie

1.  Verbind met je VM via SSH. Je vindt het publieke IP-adres in de Azure Portal.
    ```bash
    ssh azureuser@PUBLIEK_IP_ADRES_VAN_VM
    ```

2.  Bewerk het service-bestand om de omgevingsvariabelen toe te voegen.
    ```bash
    sudo nano /etc/systemd/system/chatbot.service
    ```

3.  Voeg de `Environment`-regels toe onder de `[Service]` sectie. Vervang de waarden met je eigen resource-namen.
    ```ini
    [Service]
    User=azureuser
    Group=azureuser
    WorkingDirectory=/home/azureuser/jouw-chatbot-repo
    # Voeg de volgende regels toe:
    Environment="KEY_VAULT_NAME=naam-van-jouw-keyvault"
    Environment="AZURE_OPENAI_SERVICE=naam-van-jouw-openai-service"
    Environment="AZURE_OPENAI_DEPLOYMENT=naam-van-jouw-model-deployment"
    ExecStart=/usr/local/bin/streamlit run app.py --server.port 80
    Restart=always
    ```

4.  Sla het bestand op (`Ctrl+X`, dan `Y`, dan `Enter`).

5.  Herlaad en herstart de service om de wijzigingen toe te passen.
    ```bash
    sudo systemctl daemon-reload
    sudo systemctl restart chatbot.service
    ```

---
## Toegang tot de Applicatie

Open een webbrowser en navigeer naar het publieke IP-adres van je virtuele machine.

`http://PUBLIEK_IP_ADRES_VAN_VM`

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