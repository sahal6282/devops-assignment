#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "Starting caller worker setup..."

apt update -y
apt install -y git curl

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

mkdir -p /opt/app
cd /opt/app
git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

cd /opt/app/quickstart-repo/quickstart/workers/caller-worker
npm install
npm run build || true

cat << EOF > /etc/systemd/system/caller-worker.service
[Unit]
Description=Caller RPC Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart-repo/quickstart/workers/caller-worker
Environment=III_URL="ws://${api_ip}:49134"
ExecStart=/usr/bin/node dist/worker.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now caller-worker.service

echo "Caller VM setup complete"
