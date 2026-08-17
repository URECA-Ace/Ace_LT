#!/bin/bash
# app 인스턴스 - JDK 21 만 깔고 대기
set -eux
exec > >(tee /var/log/user-data.log) 2>&1

shutdown -h +240

dnf install -y java-21-amazon-corretto-headless

cat >> /etc/sysctl.d/99-poc.conf <<'EOF'
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 32768
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
EOF
sysctl -p /etc/sysctl.d/99-poc.conf

cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
EOF

mkdir -p /home/ec2-user/app
chown ec2-user:ec2-user /home/ec2-user/app

echo "app bootstrap done" > /tmp/ready
