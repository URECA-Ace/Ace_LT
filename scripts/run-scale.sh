#!/usr/bin/env bash
# 수평 확장
# 앱을 늘리면 되나?

# 로컬에서 앱 프로세스를 2개
#   ./scripts/run-scale.sh
set -u

LOADS="${LOADS:-10000 20000}"
LOG=results/run-scale.log

cd "$(dirname "$0")/.."
mkdir -p results
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }

cleanup() {
	log "정리 - 2번 인스턴스 종료, 1번 pool 10 원복"
	./scripts/app.sh stop 2 >/dev/null 2>&1 || true
	./scripts/app.sh restart 1 8080 8081 10 >/dev/null 2>&1 || true
}
trap cleanup EXIT

arm() {  # arm <이름> <HOSTS>
	local NAME=$1 TARGETS=$2
	for VUS in $LOADS; do
		for V in v0 v1; do
			log "-- $NAME  $V / $VUS --"
			HOSTS="$TARGETS" HOST="${TARGETS%%,*}" STAT=localhost:8081 PREFIX="scale-${NAME}" \
				./scripts/probe.sh "$V" "$VUS" 10000 2>&1 \
				| grep -E "요청 |성공  |저장 처리율|poolPending" | sed "s/^/  /" | tee -a "$LOG"
			sleep 25
		done
	done
}

log "===== 수평 확장  sha $(git rev-parse --short HEAD 2>/dev/null) ====="

log ""
log "### N1  앱 1대 / pool 10 / 총 커넥션 10"
./scripts/app.sh stop 2 >/dev/null 2>&1 || true
./scripts/app.sh restart 1 8080 8081 10 | tee -a "$LOG"
PREFIX=warmup ./scripts/probe.sh v1 1000 10000 >/dev/null 2>&1 || true
sleep 15
arm N1 "localhost:8080"

log ""
log "### N1-20  앱 1대 / pool 20 / 총 커넥션 20  <- 대조군"
./scripts/app.sh restart 1 8080 8081 20 | tee -a "$LOG"
PREFIX=warmup ./scripts/probe.sh v1 1000 10000 >/dev/null 2>&1 || true
sleep 15
arm N1-20 "localhost:8080"

log ""
log "### N2  앱 2대 / 각 pool 10 / 총 커넥션 20  <- 처리군"
./scripts/app.sh restart 1 8080 8081 10 | tee -a "$LOG"
./scripts/app.sh start 2 8082 8083 10 | tee -a "$LOG"
PREFIX=warmup ./scripts/probe.sh v1 1000 10000 >/dev/null 2>&1 || true
sleep 15
arm N2 "localhost:8080,localhost:8082"

log ""
log "===== 완료 ====="
