#!/bin/bash
# load 인스턴스 - k6 + 커널 튜닝
set -eux
exec > >(tee /var/log/user-data.log) 2>&1

shutdown -h +240

dnf install -y tar gzip python3

K6=v0.54.0
curl -sL "https://github.com/grafana/k6/releases/download/${K6}/k6-${K6}-linux-amd64.tar.gz" \
	| tar xz -C /tmp
install -m 755 "/tmp/k6-${K6}-linux-amd64/k6" /usr/local/bin/k6

cat >> /etc/sysctl.d/99-poc.conf <<'EOF'
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.core.somaxconn = 32768
net.ipv4.tcp_fin_timeout = 10
EOF
sysctl -p /etc/sysctl.d/99-poc.conf

cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 200000
* hard nofile 200000
EOF

mkdir -p /home/ec2-user/results
chown -R ec2-user:ec2-user /home/ec2-user

echo "load bootstrap done" > /tmp/ready
