#!/usr/bin/env bash

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/env.sh"

SSH="ssh -i $KEY_FILE -o StrictHostKeyChecking=no -o ConnectTimeout=10"
STOCK=10000          # 목표값 고정. 부하만 바꾼다
LOG="$HERE/measure.log"
say() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

# probe.sh 는 ~/scripts 에 있고 cd ~ 로 올라가 load/issue.js 와 results/ 를 본다
probe() {  # probe <prefix> <version> <vus> <hosts> [statHost]
	local PREFIX=$1 V=$2 VUS=$3 HOSTS=$4 STAT=${5:-$APP1_PRIV:8081}
	say "  $PREFIX  $V / $VUS"
	$SSH "ec2-user@$LOAD_IP" \
		"PREFIX=$PREFIX HOSTS='$HOSTS' HOST='${HOSTS%%,*}' STAT='$STAT' ./scripts/probe.sh $V $VUS $STOCK" \
		2>&1 | grep -E "요청 |성공  |거절  |저장 처리율|적체|poolPending|동시성|GC 비율|드레인|!!" \
		| sed 's/^/    /' | tee -a "$LOG"
	sleep 25
}

restart_app() {  # restart_app <1|2> <pool>
	eval "local H=\$APP$1_IP"
	$SSH "ec2-user@$H" "~/app/run.sh $2" | sed 's/^/    /'
}

stop_app2() { $SSH "ec2-user@$APP2_IP" "pkill -9 -f app.jar || true"; }

say "===== AWS 측정 시작  재고 $STOCK 고정 ====="
say "db $DB_PRIV / app1 $APP1_PRIV / app2 $APP2_PRIV"

# 워밍업 - JIT 때문에 먼저 측정한 버전이 손해를 본다
say "워밍업 (폐기)"
for V in v0 v1 v2 v3; do
	$SSH "ec2-user@$LOAD_IP" \
		"PREFIX=warmup HOSTS=$APP1_PRIV:8080 STAT=$APP1_PRIV:8081 ./scripts/probe.sh $V 1000 $STOCK" \
		>/dev/null 2>&1
	sleep 5
done
sleep 20

# ── A. 목표값 20,000 — 순위 재현 ──
say ""
say "### A. 목표 시나리오  재고 10,000 / 동시 20,000"
stop_app2
restart_app 1 10
for V in v0 v1 v2 v3; do
	probe aws "$V" 20000 "$APP1_PRIV:8080"
done

# ── B. 붕괴점 탐색 — v1 이 언제 무너지나 ──
say ""
say "### B. 붕괴점 탐색  30,000 → 50,000"
say "    v0 는 제외한다. 20,000 에서 이미 무너져 더 올려도 정보가 없다"
for VUS in 30000 40000 50000; do
	for V in v1 v2 v3; do
		probe aws "$V" "$VUS" "$APP1_PRIV:8080"
	done
done

# ── C. — 진짜 CPU 분리 ──
say ""
say "### C. 수평 확장 (CPU 가 실제로 분리된 상태)"
say "    로컬은 앱 2대가 같은 10코어를 나눠 썼다. 그 한계를 여기서 없앤다"

say "-- N1  앱 1대 pool 10 --"
stop_app2; restart_app 1 10
probe scale-N1 v1 20000 "$APP1_PRIV:8080"

say "-- N1-20  앱 1대 pool 20 (커넥션만 늘린 대조군) --"
restart_app 1 20
probe scale-N1-20 v1 20000 "$APP1_PRIV:8080"

say "-- N2  앱 2대 각 pool 10 (총 커넥션 동일) --"
restart_app 1 10; restart_app 2 10
probe scale-N2 v1 20000 "$APP1_PRIV:8080,$APP2_PRIV:8080"

# ── D. pool 민감도 — 붕괴점이 밀리나 ──
say ""
say "### D. pool 민감도  pool 50"
stop_app2; restart_app 1 50
probe pool50 v1 20000 "$APP1_PRIV:8080"
probe pool50 v1 40000 "$APP1_PRIV:8080"
restart_app 1 10

say ""
say "===== 완료 ====="
echo
echo "회수:  scp -i $KEY_FILE -r ec2-user@$LOAD_IP:results/. ./results/"
echo "정리:  ./aws/teardown.sh      ← 잊지 말 것"
