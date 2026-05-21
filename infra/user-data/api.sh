#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

apt update -y
apt install -y git curl unzip

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install iii CLI 
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
cp /root/.local/bin/iii /usr/local/bin/iii

mkdir -p /opt/app
cd /opt/app
git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

# Create systemd service for the API Engine
cat << 'EOF' > /etc/systemd/system/iii-engine.service
[Unit]
Description=III API Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart-repo/quickstart
ExecStart=/usr/local/bin/iii start config.yaml
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now iii-engine.service

echo "API VM setup complete"
