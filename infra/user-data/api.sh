#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

# 1. Configure API VM to act as NAT Router for the private subnet
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
sysctl -p
iptables -t nat -A POSTROUTING -o enX0 -j MASQUERADE || iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

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

# 5. Create Systemd Service for Engine
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
