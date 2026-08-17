#!/usr/bin/env bash
# 본 측정
# 탐색(probe)과 달리 결과를 최종 표에 쓴다

#   ./scripts/app.sh start && ./scripts/run.sh
set -u

HOST="${HOST:-localhost:8080}"
STAT="${STAT:-localhost:8081}"
LOADS="${LOADS:-1000 10000 20000}"
LOG=results/run.log

cd "$(dirname "$0")/.."
mkdir -p results
export PREFIX=main HOST STAT

log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

one() {  # one <version> <vus>
	log "측정 $1 / $2"
	./scripts/probe.sh "$1" "$2" 10000 >> "$LOG" 2>&1 \
		|| log "  실패 - 다음 조합 계속"
	sleep 30   # 자원 회복
}

log "===== 본 측정 시작  sha $(git rev-parse --short HEAD 2>/dev/null) ====="
log "재고 10,000 고정. 부하: $LOADS"

log "워밍업 (결과 폐기)"
for V in v0 v1 v2 v3; do
	PREFIX=warmup ./scripts/probe.sh "$V" 1000 500 >> "$LOG" 2>&1 || true
	sleep 5
done
sleep 20

for VUS in $LOADS; do
	for V in v0 v1 v2 v3; do
		one "$V" "$VUS"
	done
done

for REP in 2 3; do
	for V in v2 v3; do
		one "$V" 20000
	done
done

# 정확성 - 1인 1매
log "정확성 검증 (dup.js)"
curl -s -X POST "http://$STAT/reset" >/dev/null
k6 run -q -e HOST="$HOST" -e VERSION=v3 load/dup.js >> "$LOG" 2>&1
sleep 3
curl -s "http://$STAT/stat" > results/main_dup_stat.json
python3 -c "
import json;d=json.load(open('results/main_dup_stat.json'))
print(('OK' if d['dbIssued']==100 else '실패'),'dbIssued',d['dbIssued'],'(기대 100)')" | tee -a "$LOG"

log "===== 완료. 다음: run-pool.sh / kill-test.sh / relay-test.sh / broker-kill-test.sh / run-scale.sh ====="
