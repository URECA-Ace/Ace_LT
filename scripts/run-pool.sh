#!/usr/bin/env bash
# pool 을 늘리면 해결되나?에 대한 측정
#   ./scripts/run-pool.sh
set -u

STAT="${STAT:-localhost:8081}"
LOADS="${LOADS:-1000 10000 20000}"
LOG=results/run-pool.log

cd "$(dirname "$0")/.."
mkdir -p results
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

run() {  # run <prefix> <version> <vus>
	PREFIX="$1" ./scripts/probe.sh "$2" "$3" 10000 2>&1 \
		| grep -E "성공  |저장 처리율|poolPending|GC 비율" | sed "s/^/  /" | tee -a "$LOG"
	sleep 25
}

log "===== pool 민감도  sha $(git rev-parse --short HEAD 2>/dev/null) ====="

for POOL in 10 50; do
	log ""
	log "### pool = $POOL"
	./scripts/app.sh stop 1 >/dev/null 2>&1
	./scripts/app.sh start 1 8080 8081 "$POOL" | tee -a "$LOG"
	# 워밍업
	PREFIX=warmup ./scripts/probe.sh v1 1000 10000 >/dev/null 2>&1 || true
	sleep 15

	for VUS in $LOADS; do
		log "-- v1 / $VUS (pool $POOL) --"
		run "pool${POOL}" v1 "$VUS"
	done

	if [ "$POOL" = "10" ]; then
		log "-- v2 / 20000 (기준선) --"
		run "pool${POOL}" v2 20000
	fi
done

log ""
log "===== 완료. pool 10 으로 원복 ====="
./scripts/app.sh restart 1 8080 8081 10 | tee -a "$LOG"
