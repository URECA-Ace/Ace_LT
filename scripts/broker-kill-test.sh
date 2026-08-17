#!/usr/bin/env bash
# 브로커 내구성(Redis 를 직접 죽임)
# Redis 가 죽으면?
#
# PART A 생존율 - AOF 3모드 × [relay 정지 → 부하 → 브로커 kill → 복구]
# PART B 가격 - 같은 3모드에서 v3 의 p99 (내구성이 성능을 얼마나 먹나)
#
#   ./scripts/app.sh start && ./scripts/broker-kill-test.sh
set -u

HOST="${HOST:-localhost:8080}"
STAT="${STAT:-localhost:8081}"
VUS="${VUS:-20000}"
REDIS=ace-lt-redis
LOG=results/broker-kill.log

cd "$(dirname "$0")/.."
mkdir -p results

# 종료 시 반드시 원복
trap 'echo "[trap] Redis AOF off 로 원복"; REDIS_AOF=no docker compose up -d --force-recreate redis >/dev/null 2>&1 || true' EXIT

rc() { docker exec "$REDIS" redis-cli "$@"; }
log() { echo "[$(date +%H:%M:%S)] $*" | tee -a "$LOG"; }
stat() { curl -s "http://$STAT/stat"; }
field() { stat | python3 -c "import sys,json;print(json.load(sys.stdin)['$1'])" 2>/dev/null || echo 0; }

# 컨테이너 재생성
set_mode() {  # set_mode off|everysec|always
	if [ "$1" = "off" ]; then
		REDIS_AOF=no REDIS_FSYNC=everysec docker compose up -d --force-recreate redis >/dev/null 2>&1
	else
		REDIS_AOF=yes REDIS_FSYNC="$1" docker compose up -d --force-recreate redis >/dev/null 2>&1
	fi
	for _ in $(seq 1 60); do
		rc PING 2>/dev/null | grep -q PONG && break
		sleep 1
	done
	sleep 2
	# 앞 회차 AOF 가 남아 있으면 다음 회차 결과에 섞인다
	rc FLUSHALL >/dev/null 2>&1
	log "  Redis 모드: appendonly=$(rc CONFIG GET appendonly | tail -1 | tr -d '\r') appendfsync=$(rc CONFIG GET appendfsync | tail -1 | tr -d '\r')"
}

wait_app() {
	for _ in $(seq 1 60); do
		curl -sf "http://$STAT/actuator/health" >/dev/null 2>&1 && return 0
		sleep 1
	done
	return 1
}

converge() {  # converge <기대값> - dbIssued 가 기대값에 도달할 때까지 (최대 30초)
	for _ in $(seq 1 150); do
		[ "$(field dbIssued)" = "$1" ] && return 0
		sleep 0.2
	done
	return 1
}

log "===== 브로커 킬 테스트  VU $VUS  sha $(git rev-parse --short HEAD 2>/dev/null) ====="

log ""
log "### PART A - 생존율"
for MODE in off everysec always; do
	log "--- AOF $MODE ---"
	set_mode "$MODE"

	curl -s -X POST "http://$STAT/reset" >/dev/null
	curl -s -X POST "http://$STAT/admin/relay?enabled=false" >/dev/null

	TAG="broker_${MODE}"
	k6 run -q -e VERSION=v3 -e VUS="$VUS" -e HOST="$HOST" -e TAG="$TAG" -e STOCK=10000 \
		load/issue.js >> "$LOG" 2>&1 || true
	sleep 2

	# 기준값은 k6 가 받은 성공 응답 수
	PROMISED=$(python3 -c "import json;print(json.load(open('results/${TAG}.json'))['count']['success'])")
	BEFORE_LEN=$(field streamLen)
	log "  약속한 발급 ${PROMISED}건   streamLen ${BEFORE_LEN}   dbIssued $(field dbIssued)"

	log "  docker kill -s KILL $REDIS"
	docker kill -s KILL "$REDIS" >/dev/null 2>&1
	sleep 2
	docker start "$REDIS" >/dev/null 2>&1
	for _ in $(seq 1 60); do
		rc PING 2>/dev/null | grep -q PONG && break
		sleep 1
	done
	sleep 2
	log "  Redis 재기동. streamLen $(field streamLen)"

	curl -s -X POST "http://$STAT/admin/relay?enabled=true" >/dev/null
	converge "$PROMISED" || true
	AFTER=$(field dbIssued)
	log "  ▶ 결과  약속 ${PROMISED} - 저장 ${AFTER} = 유실 $((PROMISED - AFTER))건"
	echo "{\"mode\":\"$MODE\",\"promised\":$PROMISED,\"stored\":$AFTER,\"lost\":$((PROMISED - AFTER))}" \
		> "results/broker_${MODE}_result.json"
	sleep 10
done

log ""
log "### PART B - 내구성의 가격 (v3 p99, 3회 중앙값)"
# 1회로는 방향이 뒤집힌다. 첫 시도에서 everysec(609ms) < off(1,745ms) 로 나왔다
for MODE in off everysec always; do
	log "--- AOF $MODE ---"
	set_mode "$MODE"
	for REP in 1 2 3; do
		PREFIX="aof-${MODE}" ./scripts/probe.sh v3 "$VUS" 10000 2>&1 \
			| grep -E "성공  |저장 처리율|GC 비율" | sed "s/^/  [$REP]/" | tee -a "$LOG"
		sleep 20
	done
done

log ""
log "===== 완료 모드 원복 ====="
REDIS_AOF=no docker compose up -d --force-recreate redis >/dev/null 2>&1
log "appendonly: $(rc CONFIG GET appendonly | tail -1 | tr -d '\r')"
