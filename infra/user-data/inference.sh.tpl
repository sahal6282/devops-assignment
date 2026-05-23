#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1
set -e

echo "=== Starting Inference Worker Setup ==="

export HOME=/root
export PATH=$PATH:/root/.local/bin

fallocate -l 4G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

apt update -y
apt install -y git curl unzip python3 python3-pip python3-venv build-essential

mkdir -p /opt/app
cd /opt/app
git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo
cd /opt/app/quickstart-repo/quickstart/workers/inference-worker

python3 -m venv venv
source venv/bin/activate
pip install --upgrade pip

export TMPDIR=/var/tmp
pip install --no-cache-dir -r requirements.txt

# Notice the Terraform variable ${api_ip} here!
cat << 'EOF' > /etc/systemd/system/inference-worker.service
[Unit]
Description=Python Inference RPC Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/app/quickstart-repo/quickstart/workers/inference-worker
Environment=III_URL="ws://${api_ip}:49134"
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/app/quickstart-repo/quickstart/workers/inference-worker/venv/bin/python inference_worker.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now inference-worker.service

echo "=== Inference VM setup complete ==="
