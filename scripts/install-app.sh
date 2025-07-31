#!/bin/bash

# Update en installeer benodigde software
sudo apt-get update
sudo apt-get install -y python3-pip git

# Installeer Python-bibliotheken
pip3 install streamlit openai azure-identity azure-key-vault-secrets

# Clone de applicatie-repository (vervang de URL met je eigen repo)
cd /home/azureuser # Pas de user aan indien nodig
git clone https://github.com/jouw-gebruikersnaam/jouw-chatbot-repo.git

# Maak een systemd service aan om de app automatisch te starten
# Let op: Pas de paden aan naar de locatie van je repo en app.py
cat <<EOF > /etc/systemd/system/chatbot.service
[Unit]
Description=Chatbot Streamlit Service
After=network.target

[Service]
User=azureuser
Group=azureuser
WorkingDirectory=/home/azureuser/jouw-chatbot-repo
ExecStart=/usr/local/bin/streamlit run app.py --server.port 80
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Herlaad en start de service
sudo systemctl daemon-reload
sudo systemctl enable chatbot.service
sudo systemctl start chatbot.service