#!/usr/bin/env bash
# 앱 기동/종료 관리
#
#   ./scripts/app.sh start              1번 인스턴스, 8080/8081, pool 10
#   ./scripts/app.sh start 2 8082 8083  2번 인스턴스
#   ./scripts/app.sh start 1 8080 8081 50   pool 50
#   ./scripts/app.sh kill 1             kill -9
#   ./scripts/app.sh stop 1             정상 종료
#   ./scripts/app.sh restart 1
set -u

CMD="${1:-start}"
N="${2:-1}"
PORT="${3:-$((8080 + (N - 1) * 2))}"
STAT_PORT="${4:-$((PORT + 1))}"
POOL="${5:-10}"

cd "$(dirname "$0")/.."
mkdir -p logs
PID_FILE="logs/app-${N}.pid"
JAR=build/libs/Ace_LT-0.0.1-SNAPSHOT.jar

: "${JAVA_HOME:=/opt/homebrew/Cellar/openjdk@21/21.0.11/libexec/openjdk.jdk/Contents/Home}"
export JAVA_HOME

build() {
	[ -f "$JAR" ] && return
	echo "jar 빌드..."
	./gradlew bootJar -q || exit 1
}

wait_up() {
	for _ in $(seq 1 90); do
		curl -sf "http://localhost:${STAT_PORT}/actuator/health" >/dev/null 2>&1 && return 0
		sleep 1
	done
	echo "기동 실패. logs/app-${N}.log 확인"
	return 1
}

start() {
	if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
		echo "이미 떠 있음 (pid $(cat "$PID_FILE"))"
		return 0
	fi
	build
	# 통제 변수는 기본값이 곧 기준값. 여기서 주입하는 것만 예외다
	SERVER_PORT="$PORT" INSTANCE_ID="app-${N}" POC_STAT_PORT="$STAT_PORT" POOL_SIZE="$POOL" \
		nohup "$JAVA_HOME/bin/java" -jar "$JAR" > "logs/app-${N}.log" 2>&1 &
	echo $! > "$PID_FILE"
	wait_up && echo "app-${N} 기동  포트 ${PORT}  폴러 ${STAT_PORT}  pool ${POOL}  pid $(cat "$PID_FILE")"
}

# kill -9. 큐/스트림 잔량이 어떻게 되는지 보는 게 목적이라 정상 종료를 쓰면 안 된다
hard_kill() {
	[ -f "$PID_FILE" ] || { echo "pid 파일 없음"; return 1; }
	kill -9 "$(cat "$PID_FILE")" 2>/dev/null
	rm -f "$PID_FILE"
	echo "app-${N} kill -9"
}

stop() {
	[ -f "$PID_FILE" ] || { echo "pid 파일 없음"; return 0; }
	kill "$(cat "$PID_FILE")" 2>/dev/null
	for _ in $(seq 1 30); do
		kill -0 "$(cat "$PID_FILE")" 2>/dev/null || break
		sleep 1
	done
	rm -f "$PID_FILE"
	echo "app-${N} 종료"
}

case "$CMD" in
	start) start ;;
	stop) stop ;;
	kill) hard_kill ;;
	restart) stop; start ;;
	status)
		if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
			echo "app-${N} 실행 중 (pid $(cat "$PID_FILE"))"
		else
			echo "app-${N} 없음"
		fi ;;
	*) echo "usage: app.sh start|stop|kill|restart|status [n] [port] [statPort] [pool]"; exit 1 ;;
esac
