#!/usr/bin/env python3
"""탐색 측정 요약 출력. 본 측정 리포트는 parse.py 가 따로 만든다."""
import json
import sys


def ms(v):
    return "-" if v is None else f"{v:>8.1f}"


def main(k6_path, stat_path, timeline_path):
    k6 = json.load(open(k6_path))
    stat = json.load(open(stat_path))

    timeline = []
    with open(timeline_path) as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    timeline.append(json.loads(line))
                except json.JSONDecodeError:
                    pass

    c = k6["count"]
    total = c["success"] + c["reject"] + c["error"]
    err_rate = 100 * c["error"] / total if total else 0

    print(f"\n=== 탐색 측정 {k6['tag']}  (sha {k6['sha']}) — 본 측정 아님 ===\n")

    print(f"  요청 {total}  성공 {c['success']}  거절 {c['reject']}  에러 {c['error']} ({err_rate:.0f}%)")
    print(f"  소요 {k6['elapsedSec']:.1f}s   유효 TPS {k6['tps']:.0f}   (닫힌 모델 — '초당 처리량' 아님)")

    # 타임아웃이 섞이면 p99 는 잘린 값
    # TPS 도 좋아 보인다 (coordinated omission)
    if err_rate >= 5:
        print(f"  !! 에러율 {err_rate:.0f}% — p99/TPS 해석 금지. 응답 못 받은 요청이 통계에서 빠져")
        print("     느린 요청일수록 잘려나가 오히려 좋아 보인다")

    print("\n  TTFB(http_req_waiting) ms")
    print("            p95      p99      max")
    for label, key in (("성공", "success"), ("거절", "reject")):
        w = k6["waitMs"][key]
        print(f"    {label}  {ms(w['p95'])} {ms(w['p99'])} {ms(w['max'])}")

    stock = k6.get("stock", 10000)
    print(f"\n  정확성  dbIssued {stat['dbIssued']} / 재고 {stock}"
          f"   dbRemaining {stat['dbRemaining']}   redisRemaining {stat['redisRemaining']}")
    if stat["dbIssued"] > stock:
        print("  !! 초과 발급 - 성능 수치는 무의미. 원인부터")

    gap = c["success"] - stat["dbIssued"]
    if gap > 0:
        print(f"  유실  성공응답 {c['success']} - dbIssued {stat['dbIssued']} = {gap}")
        print("        발급했다고 응답해놓고 저장은 안 됨")
    elif gap < 0:
        print(f"  미수신  dbIssued {stat['dbIssued']} - 성공응답 {c['success']} = {-gap}")
        print("        서버는 저장했는데 클라이언트가 타임아웃으로 포기 (유실 아님)")

    if timeline:
        peak_pending = max(t.get("poolPending", 0) for t in timeline)
        peak_old = max(t.get("oldGenUsedMb", 0) for t in timeline)
        gc0, gc1 = timeline[0].get("gcTimeMs", 0), timeline[-1].get("gcTimeMs", 0)
        span = (timeline[-1]["ts"] - timeline[0]["ts"]) or 1
        # 저장 계층이 실제로 밀렸는지
        # streamPending 을 쓰면 X
        # relay 가 배달받은 것만 세므로 배치 크기(500)에서 상한이 걸림
        # 아직 안 읽은 엔트리가 진짜 -> streamLen - dbIssued
        peak_backlog = max(
            max(t.get("queueSize", 0), t.get("streamLen", 0) - t["dbIssued"], 0)
            for t in timeline)
        db_series = [(t["ts"], t["dbIssued"]) for t in timeline]
        rate = 0
        if len(db_series) >= 2:
            sec = (db_series[-1][0] - db_series[0][0]) / 1000 or 1
            rate = (db_series[-1][1] - db_series[0][1]) / sec
        print(f"\n  저장 처리율 {rate:.0f}/s", end="")
        if k6["version"] in ("v2", "v3"):
            print(f"   저장 적체 최대 {peak_backlog}건")
            if peak_backlog < 100:
                print("  ! 적체 거의 없음 - 저장 계층이 밀리지 않았다")
        else:
            print("   (동기라 적체 개념 없음)")

        peak_inflight = max(t.get("inFlightPeak", 0) for t in timeline)
        print(f"\n  서버가 겪은 동시성 최대 {peak_inflight} / 쏜 VU {k6['vus']}"
              f"  ({100 * peak_inflight / k6['vus']:.0f}%)")
        print(f"  poolPending 최대 {peak_pending} (tomcat threads 에서 포화)   oldGen 최대 {peak_old}MB")
        print(f"  GC 비율 {100 * (gc1 - gc0) / span:.2f}%  (1% 미만이면 병목 아님)")

    warn = []
    if c["dropped"]:
        print(f"\n  !! dropped_iterations {c['dropped']} - 부하 생성기가 먼저 무너짐. 회차 폐기")
    if k6["durationMs"]["blockedP99"] and k6["durationMs"]["blockedP99"] > 1:
        warn.append(f"http_req_blocked p99 {k6['durationMs']['blockedP99']:.1f}ms — 클라이언트가 커넥션 대기")
    for w in warn:
        print(f"  ! {w}")
    print()


if __name__ == "__main__":
    main(*sys.argv[1:4])
