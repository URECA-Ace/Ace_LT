#!/usr/bin/env bash
# 탐색 측정
#   ./scripts/probe.sh v0 1000
set -u

VERSION="${1:-v0}"
VUS="${2:-1000}"
# 재고를 VU 의 절반으로
# 본 측정 비율(20,000 VU / 재고 10,000)을 축소해서 유지
# 재고가 VU 보다 많으면 거절이 안 나와 거절 비용을 못 본다
STOCK="${3:-$((VUS / 2))}"
HOST="${HOST:-localhost:8080}"
# 폴러 전용 커넥터
STAT="${STAT:-localhost:8081}"
# run.sh 는 PREFIX=main 으로 불러 본 측정과 탐색을 구분
TAG="${PREFIX:-probe}_${VERSION}_${VUS}_$(date +%H%M%S)"

cd "$(dirname "$0")/.."
mkdir -p results

command -v k6 >/dev/null || { echo "k6 없음. brew install k6"; exit 1; }
curl -sf "http://$STAT/actuator/health" >/dev/null || { echo "앱이 안 떠 있음: $HOST"; exit 1; }

echo "탐색 ${VERSION}  VU ${VUS}  재고 ${STOCK}"
curl -s -X POST "http://$STAT/reset?stock=$STOCK" >/dev/null

# 200ms 폴러 - dbIssued(t) / poolPending(t) / GC 타임라인
( while :; do curl -s "http://$STAT/stat"; echo; sleep 0.2; done ) > "results/${TAG}_timeline.ndjson" 2>/dev/null &
POLLER=$!
trap 'kill $POLLER 2>/dev/null' EXIT

k6 run -q \
	-e VERSION="$VERSION" -e VUS="$VUS" -e HOST="$HOST" -e TAG="$TAG" -e STOCK="$STOCK" \
	-e SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
	load/issue.js

# 비동기 저장이 따라잡을 때까지 대기 - 응답 이후의 지연

# streamPending == 0 을 조건으로 쓰면 안 된다.
# v3 는 "다 처리됨" 과 "아직 배달 안 됨" 이 둘 다 0 이라 배달 전에 측정을 끝내버린다.
# 불변식을 쓴다 -> 발급된 건은 결국 DB 에 있어야 한다 (dbIssued >= redisIssuedBits)
DRAIN_START=$(python3 -c 'import time;print(int(time.time()*1000))')
for _ in $(seq 1 300); do
	DONE=$(curl -s "http://$STAT/stat" | python3 -c \
		'import sys,json;d=json.load(sys.stdin);print(1 if d["dbIssued"]>=d.get("redisIssuedBits",0) and d.get("queueSize",0)==0 and d.get("streamPending",0)==0 else 0)' 2>/dev/null || echo 1)
	[ "$DONE" = "1" ] && break
	sleep 0.2
done
DRAIN_MS=$(( $(python3 -c 'import time;print(int(time.time()*1000))') - DRAIN_START ))

sleep 1
kill $POLLER 2>/dev/null
curl -s "http://$STAT/stat" > "results/${TAG}_stat.json"

python3 scripts/probe-report.py "results/${TAG}.json" "results/${TAG}_stat.json" "results/${TAG}_timeline.ndjson"
echo "  드레인 대기 ${DRAIN_MS}ms - 응답 이후 저장 완료까지 (비동기가 지불하는 대가)"
echo
