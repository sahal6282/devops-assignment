#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "=== Starting API VM Setup ==="

# FIX: Explicitly set the home directory for the installer
export HOME=/root
export PATH=$PATH:/root/.local/bin

# 1. Bulletproof NAT Routing
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
sysctl -p
PRIMARY_INTERFACE=$(ip route | grep default | awk '{print $5}')
iptables -t nat -A POSTROUTING -o $PRIMARY_INTERFACE -j MASQUERADE

# 2. Base Install
apt update -y
apt install -y git curl unzip jq

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# 3. Install III Engine
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
cp /root/.local/bin/iii /usr/local/bin/iii

# 4. Clone Repo
mkdir -p /opt/app
cd /opt/app
git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

# 5. Create Systemd Service for Engine (FIXED EXECSTART)
cat << 'EOF' > /etc/systemd/system/iii-engine.service
[Unit]
Description=III API Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart-repo/quickstart
ExecStart=/usr/local/bin/iii --no-update-check
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now iii-engine.service

echo "=== API VM setup complete ==="
