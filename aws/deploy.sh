#!/usr/bin/env bash
# jar 와 측정 스크립트를 올리고 앱을 기동한다
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
source "$HERE/env.sh"

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o ConnectTimeout=10"
SCP="scp -i $KEY_FILE -o StrictHostKeyChecking=no"
JAR="$ROOT/build/libs/Ace_LT-0.0.1-SNAPSHOT.jar"
say() { echo "[$(date +%H:%M:%S)] $*"; }

# ── user-data 완료 대기 ──
for H in "$APP1_IP" "$APP2_IP" "$LOAD_IP"; do
	say "부트스트랩 대기 $H"
	for _ in $(seq 1 60); do
		$SSH "ec2-user@$H" 'test -f /tmp/ready' 2>/dev/null && break
		sleep 5
	done
done
say "db 컨테이너 대기"
for _ in $(seq 1 60); do
	$SSH "ec2-user@$APP1_IP" "timeout 2 bash -c '</dev/tcp/$DB_PRIV/3306'" 2>/dev/null && break
	sleep 5
done

# ── jar ──
[ -f "$JAR" ] || (cd "$ROOT" && ./gradlew bootJar -q)
say "jar 업로드 (41MB × 2)"
$SCP "$JAR" "ec2-user@$APP1_IP:app/app.jar"
$SCP "$JAR" "ec2-user@$APP2_IP:app/app.jar"

# ── 앱 기동 스크립트 (인스턴스별) ──
# pool 크기와 인스턴스 ID 를 인자로 받는다.
for i in 1 2; do
	eval "H=\$APP${i}_IP"
	$SSH "ec2-user@$H" "cat > ~/app/run.sh" <<EOF
#!/bin/bash
# run.sh <pool>
set -u
POOL="\${1:-10}"
pkill -9 -f 'app.jar' 2>/dev/null || true
sleep 1
ulimit -n 65535
DB_HOST=$DB_PRIV DB_PORT=3306 DB_NAME=ace_lt DB_USER=root DB_PASSWORD=1234 \\
REDIS_HOST=$DB_PRIV REDIS_PORT=6379 \\
SERVER_PORT=8080 POC_STAT_PORT=8081 INSTANCE_ID=app-$i POOL_SIZE="\$POOL" \\
	nohup java -jar ~/app/app.jar > ~/app/app.log 2>&1 &
for _ in \$(seq 1 90); do
	curl -sf localhost:8081/actuator/health >/dev/null 2>&1 && { echo "app-$i up pool=\$POOL"; exit 0; }
	sleep 1
done
echo "app-$i 기동 실패"; tail -20 ~/app/app.log; exit 1
EOF
	$SSH "ec2-user@$H" 'chmod +x ~/app/run.sh'
done

say "app1 기동"; $SSH "ec2-user@$APP1_IP" '~/app/run.sh 10'
say "app2 기동"; $SSH "ec2-user@$APP2_IP" '~/app/run.sh 10'

# ── 측정 도구를 load 로 ──
say "측정 스크립트 업로드"
$SSH "ec2-user@$LOAD_IP" 'mkdir -p ~/scripts ~/load ~/results'
$SCP "$ROOT/scripts/probe.sh" "$ROOT/scripts/probe-report.py" "ec2-user@$LOAD_IP:scripts/"
$SCP "$ROOT/load/issue.js" "$ROOT/load/dup.js" "ec2-user@$LOAD_IP:load/"
$SSH "ec2-user@$LOAD_IP" 'chmod +x ~/scripts/*.sh ~/scripts/*.py'

# ── 연결 확인 ──
say "연결 확인"
$SSH "ec2-user@$LOAD_IP" "curl -s http://$APP1_PRIV:8081/stat | head -c 200; echo"
$SSH "ec2-user@$LOAD_IP" "curl -s -o /dev/null -w 'app2 stat %{http_code}\n' http://$APP2_PRIV:8081/stat"

echo
echo "준비 완료. 다음: ./aws/measure.sh"
