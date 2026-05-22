#!/bin/bash
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

set -e

export HOME=/root
export PATH=$PATH:/root/.local/bin

# Enable NAT for private subnet internet access
echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
sysctl -p

iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE

apt update -y
apt install -y git curl unzip

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs

# Install iii
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh

cp $HOME/.local/bin/iii /usr/local/bin/iii

mkdir -p /opt/app
cd /opt/app

git clone https://github.com/sahal6282/devops-assignment.git quickstart-repo

cd /opt/app/quickstart-repo/quickstart

# Start iii engine
nohup iii dev > /var/log/iii-engine.log 2>&1 &
