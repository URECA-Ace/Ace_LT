#!/bin/bash
# db 인스턴스 - MySQL 8.4 + Redis 8.2
set -eux
exec > >(tee /var/log/user-data.log) 2>&1

shutdown -h +240

dnf install -y docker
systemctl enable --now docker

# --bind-address=0.0.0.0 필수. 기본은 컨테이너 내부만 받는다
docker run -d --name mysql --restart unless-stopped -p 3306:3306 \
	-e MYSQL_ROOT_PASSWORD=1234 -e MYSQL_DATABASE=ace_lt -e TZ=Asia/Seoul \
	mysql:8.4 \
	--bind-address=0.0.0.0 \
	--character-set-server=utf8mb4 --collation-server=utf8mb4_0900_ai_ci \
	--default-time-zone=+09:00 --skip-name-resolve \
	--max-connections=500

# 성능 측정에 디스크 I/O 가 섞이지 않게 영속화 off (로컬과 동일한 통제 변수)
docker run -d --name redis --restart unless-stopped -p 6379:6379 \
	redis:8.2 redis-server --appendonly no --save ""

# 20,000+ 동시 연결을 받는 쪽이라 백로그를 올린다
cat >> /etc/sysctl.d/99-poc.conf <<'EOF'
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 32768
EOF
sysctl -p /etc/sysctl.d/99-poc.conf

echo "db bootstrap done" > /tmp/ready
