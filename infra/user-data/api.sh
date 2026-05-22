#!/bin/bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

set -e

# ==============================================================
# Enable NAT routing for private subnet internet access
# ==============================================================

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

IFACE=$(ip route | grep default | awk '{print $5}')

iptables -t nat -A POSTROUTING -o $IFACE -j MASQUERADE

# ==============================================================

apt update -y
apt install -y git curl unzip

# Install Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install iii CLI
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh

export PATH=$PATH:/root/.local/bin

cp /root/.local/bin/iii /usr/local/bin/iii

# Clone repo
mkdir -p /opt/app
cd /opt/app

git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

# Create systemd service
cat << EOF > /etc/systemd/system/iii-engine.service
[Unit]
Description=III API Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart-repo/quickstart
Environment=PATH=/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/iii
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iii-engine.service
systemctl start iii-engine.service

echo "API VM setup complete"
