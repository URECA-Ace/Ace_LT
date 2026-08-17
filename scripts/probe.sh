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
TAG="probe_${VERSION}_${VUS}_$(date +%H%M%S)"

cd "$(dirname "$0")/.."
mkdir -p results

command -v k6 >/dev/null || { echo "k6 없음. brew install k6"; exit 1; }
curl -sf "http://$HOST/actuator/health" >/dev/null || { echo "앱이 안 떠 있음: $HOST"; exit 1; }

echo "탐색 ${VERSION}  VU ${VUS}  재고 ${STOCK}"
curl -s -X POST "http://$HOST/reset?stock=$STOCK" >/dev/null

# 200ms 폴러 - dbIssued(t) / poolPending(t) / GC 타임라인
( while :; do curl -s "http://$HOST/stat"; echo; sleep 0.2; done ) > "results/${TAG}_timeline.ndjson" 2>/dev/null &
POLLER=$!
trap 'kill $POLLER 2>/dev/null' EXIT

k6 run -q \
	-e VERSION="$VERSION" -e VUS="$VUS" -e HOST="$HOST" -e TAG="$TAG" -e STOCK="$STOCK" \
	-e SHA="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)" \
	load/issue.js

sleep 3   # 비동기 저장(v2/v3)이 따라잡을 시간
kill $POLLER 2>/dev/null
curl -s "http://$HOST/stat" > "results/${TAG}_stat.json"

python3 scripts/probe-report.py "results/${TAG}.json" "results/${TAG}_stat.json" "results/${TAG}_timeline.ndjson"
