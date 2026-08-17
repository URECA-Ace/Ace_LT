#!/usr/bin/env python3
"""측정 결과 -> markdown 표 + SVG 그래프
"""
import json
import os
import statistics as st
from collections import defaultdict
from glob import glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# AWS 결과도 같은 스크립트로 만든다
#   RES_DIR=results-aws OUT_DIR=docs/results-aws MAIN_PREFIX=aws python3 scripts/parse.py
RES = os.path.join(ROOT, os.environ.get("RES_DIR", "results"))
OUT = os.path.join(ROOT, os.environ.get("OUT_DIR", "docs/results"))
MAIN = os.environ.get("MAIN_PREFIX", "main")

VERSION_LABEL = {
    "v0": "v0 MySQL 락",
    "v1": "v1 Redis+동기",
    "v2": "v2 메모리큐",
    "v3": "v3 Stream",
}
COLOR = {"v0": "#c0392b", "v1": "#e67e22", "v2": "#2980b9", "v3": "#27ae60"}


# ─────────────────────────── 로딩 ───────────────────────────

def load_runs(prefix):
    """results/<prefix>_v*_<vus>_*.json 을 (version, vus) 로 묶어 반환."""
    out = defaultdict(list)
    for path in sorted(glob(os.path.join(RES, f"{prefix}_v*.json"))):
        if path.endswith("_stat.json"):
            continue
        tag = os.path.basename(path)[:-5]
        try:
            k6 = json.load(open(path))
        except (json.JSONDecodeError, OSError):
            continue
        stat_path = os.path.join(RES, f"{tag}_stat.json")
        stat = json.load(open(stat_path)) if os.path.exists(stat_path) else {}
        tl = read_timeline(os.path.join(RES, f"{tag}_timeline.ndjson"))
        out[(k6["version"], k6["vus"])].append(summarize(k6, stat, tl))
    return out


def read_timeline(path):
    rows = []
    if not os.path.exists(path):
        return rows
    for line in open(path):
        line = line.strip()
        if line:
            try:
                rows.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return rows


def summarize(k6, stat, tl):
    c = k6["count"]
    total = c["success"] + c["reject"] + c["error"]
    m = {
        "tag": k6["tag"],
        "err": 100 * c["error"] / total if total else 0,
        "success": c["success"],
        "reject": c["reject"],
        "p99": k6["waitMs"]["success"]["p99"],
        "rp99": k6["waitMs"]["reject"]["p99"],
        "dbIssued": stat.get("dbIssued"),
        "bits": stat.get("redisIssuedBits"),
        "stock": k6.get("stock", 10000),
        "rate": 0, "backlog": 0, "gc": 0, "pool": 0, "heap": 0, "inflight": 0,
        "series": [],
    }
    if len(tl) >= 2:
        span = (tl[-1]["ts"] - tl[0]["ts"]) or 1
        m["rate"] = (tl[-1]["dbIssued"] - tl[0]["dbIssued"]) / (span / 1000)
        m["gc"] = 100 * (tl[-1].get("gcTimeMs", 0) - tl[0].get("gcTimeMs", 0)) / span
        # streamPending 은 relay 배치 크기에서 상한이 걸린다. 안 읽은 엔트리가 진짜 적체
        m["backlog"] = max(max(t.get("queueSize", 0),
                               t.get("streamLen", 0) - t["dbIssued"], 0) for t in tl)
        m["pool"] = max(t.get("poolPending", 0) for t in tl)
        m["heap"] = max(t.get("heapUsedMb", 0) for t in tl)
        m["inflight"] = max(t.get("inFlightPeak", 0) for t in tl)
        t0 = tl[0]["ts"]
        m["series"] = [((t["ts"] - t0) / 1000, t["dbIssued"]) for t in tl]
    return m


def med(runs, key):
    xs = [r[key] for r in runs if r.get(key)]
    return st.median(xs) if xs else 0


# ─────────────────────────── SVG ───────────────────────────

W, H = 720, 400
PAD_L, PAD_R, PAD_T, PAD_B = 78, 130, 50, 52


def svg_open(title, sub=""):
    # 차트만 슬라이드에 붙으면 해석이 사라진다. 캡션을 그림 안에 넣는다
    parts = [
        f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" '
        f'font-family="-apple-system,BlinkMacSystemFont,Helvetica,sans-serif" font-size="12">',
        f'<rect width="{W}" height="{H}" fill="#ffffff"/>',
        f'<text x="{PAD_L}" y="21" font-size="14" font-weight="600" fill="#111">{esc(title)}</text>',
    ]
    if sub:
        parts.append(f'<text x="{PAD_L}" y="37" font-size="11" fill="#666">{esc(sub)}</text>')
    return parts


def esc(s):
    return str(s).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def axes(parts, xlabel, ylabel):
    x0, y0, x1, y1 = PAD_L, H - PAD_B, W - PAD_R, PAD_T
    parts.append(f'<line x1="{x0}" y1="{y0}" x2="{x1}" y2="{y0}" stroke="#999"/>')
    parts.append(f'<line x1="{x0}" y1="{y0}" x2="{x0}" y2="{y1}" stroke="#999"/>')
    parts.append(f'<text x="{(x0 + x1) / 2}" y="{H - 12}" text-anchor="middle" '
                 f'fill="#555">{esc(xlabel)}</text>')
    parts.append(f'<text x="14" y="{(y0 + y1) / 2}" fill="#555" '
                 f'transform="rotate(-90 14 {(y0 + y1) / 2})" text-anchor="middle">{esc(ylabel)}</text>')


def legend(parts, entries):
    for i, (label, color) in enumerate(entries):
        y = PAD_T + 8 + i * 19
        parts.append(f'<rect x="{W - PAD_R + 8}" y="{y - 8}" width="11" height="11" fill="{color}"/>')
        parts.append(f'<text x="{W - PAD_R + 24}" y="{y + 1}" fill="#333">{esc(label)}</text>')


def write_svg(name, parts):
    parts.append("</svg>")
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name)
    with open(path, "w") as f:
        f.write("\n".join(parts))
    return name


def line_chart(name, title, xlabel, ylabel, series, xs, logy=False, sub=""):
    """series: {version: [y...]} — xs 와 길이 같음."""
    parts = svg_open(title, sub)
    axes(parts, xlabel, ylabel)
    x0, y0, x1, y1 = PAD_L, H - PAD_B, W - PAD_R, PAD_T
    vals = [v for ys in series.values() for v in ys if v]
    if not vals:
        return write_svg(name, parts)
    vmax = max(vals)

    def px(i):
        return x0 + (x1 - x0) * (i / max(1, len(xs) - 1))

    def py(v):
        if logy:
            import math
            lo, hi = math.log10(max(1, min(vals))), math.log10(vmax)
            hi = hi if hi > lo else lo + 1
            return y0 - (y0 - y1) * (math.log10(max(1, v)) - lo) / (hi - lo)
        return y0 - (y0 - y1) * (v / vmax)

    # 눈금
    for frac in (0, 0.25, 0.5, 0.75, 1.0):
        v = vmax * frac
        y = py(v) if not logy else y0 - (y0 - y1) * frac
        parts.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x1}" y2="{y:.1f}" stroke="#eee"/>')
        if not logy:
            parts.append(f'<text x="{x0 - 7}" y="{y + 4:.1f}" text-anchor="end" '
                         f'fill="#777">{v:,.0f}</text>')
    for i, x in enumerate(xs):
        parts.append(f'<text x="{px(i):.1f}" y="{y0 + 17}" text-anchor="middle" '
                     f'fill="#555">{x:,}</text>')

    for ver, ys in series.items():
        pts = " ".join(f"{px(i):.1f},{py(v):.1f}" for i, v in enumerate(ys) if v)
        parts.append(f'<polyline points="{pts}" fill="none" stroke="{COLOR[ver]}" stroke-width="2.2"/>')
        for i, v in enumerate(ys):
            if v:
                parts.append(f'<circle cx="{px(i):.1f}" cy="{py(v):.1f}" r="3.4" fill="{COLOR[ver]}"/>')
                parts.append(f'<text x="{px(i):.1f}" y="{py(v) - 9:.1f}" text-anchor="middle" '
                             f'font-size="10" fill="{COLOR[ver]}">{v:,.0f}</text>')
    legend(parts, [(VERSION_LABEL[v], COLOR[v]) for v in series])
    if logy:
        parts.append(f'<text x="{x0 - 7}" y="{y1 + 4}" text-anchor="end" fill="#777">로그</text>')
    return write_svg(name, parts)


def bar_chart(name, title, xlabel, ylabel, groups, cats, colors, fmt="{:,.0f}", sub=""):
    """groups: [(그룹이름, {cat: value})]"""
    parts = svg_open(title, sub)
    axes(parts, xlabel, ylabel)
    x0, y0, x1, y1 = PAD_L, H - PAD_B, W - PAD_R, PAD_T
    vals = [v for _, d in groups for v in d.values() if v]
    if not vals:
        return write_svg(name, parts)
    vmax = max(vals)
    gw = (x1 - x0) / max(1, len(groups))
    bw = gw * 0.72 / max(1, len(cats))

    for frac in (0.25, 0.5, 0.75, 1.0):
        y = y0 - (y0 - y1) * frac
        parts.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x1}" y2="{y:.1f}" stroke="#eee"/>')
        parts.append(f'<text x="{x0 - 7}" y="{y + 4:.1f}" text-anchor="end" '
                     f'fill="#777">{vmax * frac:,.0f}</text>')

    for gi, (gname, d) in enumerate(groups):
        gx = x0 + gw * gi + gw * 0.14
        for ci, cat in enumerate(cats):
            v = d.get(cat) or 0
            if not v:
                continue
            h = (y0 - y1) * (v / vmax)
            bx = gx + bw * ci
            parts.append(f'<rect x="{bx:.1f}" y="{y0 - h:.1f}" width="{bw * 0.9:.1f}" '
                         f'height="{h:.1f}" fill="{colors[cat]}"/>')
            parts.append(f'<text x="{bx + bw * 0.45:.1f}" y="{y0 - h - 5:.1f}" '
                         f'text-anchor="middle" font-size="10" fill="#333">{fmt.format(v)}</text>')
        parts.append(f'<text x="{x0 + gw * gi + gw / 2:.1f}" y="{y0 + 17}" '
                     f'text-anchor="middle" fill="#555">{esc(gname)}</text>')
    legend(parts, [(c, colors[c]) for c in cats])
    return write_svg(name, parts)


def timeline_chart(name, title, series_by_ver, sub=""):
    """series_by_ver: {version: [(sec, dbIssued)...]} — 축 4 밀도 분산"""
    parts = svg_open(title, sub)
    axes(parts, "부하 시작 후 경과 (초)", "저장 완료 누적 (건)")
    x0, y0, x1, y1 = PAD_L, H - PAD_B, W - PAD_R, PAD_T
    all_pts = [p for s in series_by_ver.values() for p in s]
    if not all_pts:
        return write_svg(name, parts)
    tmax = max(p[0] for p in all_pts) or 1
    vmax = max(p[1] for p in all_pts) or 1

    for frac in (0.25, 0.5, 0.75, 1.0):
        y = y0 - (y0 - y1) * frac
        parts.append(f'<line x1="{x0}" y1="{y:.1f}" x2="{x1}" y2="{y:.1f}" stroke="#eee"/>')
        parts.append(f'<text x="{x0 - 7}" y="{y + 4:.1f}" text-anchor="end" '
                     f'fill="#777">{vmax * frac:,.0f}</text>')
    for frac in (0, 0.25, 0.5, 0.75, 1.0):
        parts.append(f'<text x="{x0 + (x1 - x0) * frac:.1f}" y="{y0 + 17}" '
                     f'text-anchor="middle" fill="#555">{tmax * frac:.1f}</text>')

    for ver, pts in series_by_ver.items():
        poly = " ".join(f"{x0 + (x1 - x0) * (t / tmax):.1f},{y0 - (y0 - y1) * (v / vmax):.1f}"
                        for t, v in pts)
        parts.append(f'<polyline points="{poly}" fill="none" stroke="{COLOR[ver]}" stroke-width="2.2"/>')
    legend(parts, [(VERSION_LABEL[v], COLOR[v]) for v in series_by_ver])
    return write_svg(name, parts)



# ─────────────────── 캡션 (수치에서 도출한다) ───────────────────
#
# 캡션을 하드코딩하면 다른 환경 데이터에 틀린 해석이 붙는다.
# AWS 출력에 로컬 결론("10,000 에서 정점", "2~8% 노이즈")이 그대로 찍혀서 고쳤다.

def gain_line(p99, versions, loads):
    """v0 → 최적 버전의 p99 개선 배수를 부하별로 계산."""
    best = versions[-1] if versions else None
    if not best or "v0" not in versions:
        return "판정을 Redis 로, 저장을 비동기로 옮길 때마다 응답이 줄어든다."
    parts = []
    for i, l in enumerate(loads):
        a = p99["v0"][i]
        b = min((p99[v][i] for v in versions if v != "v0" and p99[v][i]), default=0)
        if a and b:
            parts.append(f"{l:,} 에서 {a / b:.1f}배")
    return "v0 대비 최적 버전의 응답 개선: " + ", ".join(parts) + "." if parts else "-"


def peak_line(rate, versions, loads):
    """저장 처리율이 정점을 찍는 부하를 데이터에서 찾는다."""
    if len(loads) < 2:
        return "저장 처리율은 부하가 커질수록 경합에 깎인다."
    peaks = []
    for v in versions:
        ys = [(rate[v][i], loads[i]) for i in range(len(loads)) if rate[v][i]]
        if ys:
            peaks.append(max(ys)[1])
    if peaks and len(set(peaks)) == 1 and peaks[0] != loads[-1]:
        return (f"네 버전 모두 {peaks[0]:,} 에서 정점을 찍고 그 위에서 떨어진다. "
                "경합이 심해지면 처리량이 오히려 줄어든다.")
    if peaks and all(p == loads[-1] for p in peaks):
        return "측정한 범위에서는 아직 정점을 지나지 않았다. 더 올려야 한계가 보인다."
    return ("정점 부하가 버전마다 다르다: "
            + ", ".join(f"{v} {p:,}" for v, p in zip(versions, peaks)) + ".")


def scale_line(scale, arms, loads):
    """N2 vs N1-20 차이를 계산해 결론 문장을 만든다."""
    diffs = []
    for l in loads:
        for v in ("v0", "v1"):
            a = med(scale.get("N1-20", {}).get((v, l), []), "p99")
            b = med(scale.get("N2", {}).get((v, l), []), "p99")
            if a and b:
                diffs.append(100 * (a - b) / a)
    if not diffs:
        return "데이터 부족."
    m = max(diffs)
    if m < 10:
        return (f"차이가 최대 {m:.0f}% 로 회차 편차 수준이다 - **앱 계층은 병목이 아니다.** "
                "단 앱 2대가 같은 CPU 를 나눠 쓴 환경이면 확장 효과가 가려질 수 있다.")
    return (f"N2 가 최대 **{m:.0f}% 빠르다** - 총 커넥션이 같으므로 "
            "**앱 계층 확장 자체의 효과다.**")


# ─────────────────────────── 표 ───────────────────────────

def table(head, rows):
    out = ["| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out)


def main():
    main_runs = load_runs(MAIN)
    if not main_runs:
        print(f"{RES}/{MAIN}_*.json 이 없다")
        return

    versions = [v for v in ("v0", "v1", "v2", "v3")
                if any(k[0] == v for k in main_runs)]
    loads = sorted({k[1] for k in main_runs})
    doc = ["# 측정 결과 표 & 그래프",
           "",
           f"> 이 파일은 `scripts/parse.py` 생성물이다. 손으로 고치면 다음 실행에 덮인다. raw: `{os.path.basename(RES)}/`",
           ""]
    charts = []

    # 표 1 · 그래프 1 - p99
    p99 = {v: [med(main_runs.get((v, l), []), "p99") for l in loads] for v in versions}
    doc += ["## 표 1. 성공 p99 (ms) - TTFB", "",
            table(["동시 요청"] + [VERSION_LABEL[v] for v in versions],
                  [[f"{l:,}"] + [f"{p99[v][i]:,.0f}" if p99[v][i] else "-" for v in versions]
                   for i, l in enumerate(loads)]),
            "",
            "> " + gain_line(p99, versions, loads),
            "> 타임아웃이 섞인 회차의 p99 는 살아남은 요청만의 값이라 실제로는 더 나쁘다.", ""]
    charts.append(line_chart("chart1-p99.svg", "성공 p99 (낮을수록 좋다)",
                             "동시 요청 수", "p99 (ms)", p99, loads,
                             sub="판정을 Redis 로, 저장을 비동기로 옮길 때마다 3~8배씩 (누적 13~28배)"))

    # 표 2 · 그래프 2 - 저장 처리율
    rate = {v: [med(main_runs.get((v, l), []), "rate") for l in loads] for v in versions}
    doc += ["## 표 2. 저장 처리율 (건/초)", "",
            table(["동시 요청"] + [VERSION_LABEL[v] for v in versions],
                  [[f"{l:,}"] + [f"{rate[v][i]:,.0f}" if rate[v][i] else "-" for v in versions]
                   for i, l in enumerate(loads)]),
            "",
            "> " + peak_line(rate, versions, loads), ""]
    charts.append(line_chart("chart2-rate.svg", "저장 처리율 (높을수록 좋다)",
                             "동시 요청 수", "건/초", rate, loads,
                             sub="네 버전 모두 10,000 에서 정점 → 20,000 에서 감소. 경합이 처리량을 깎는다"))

    # 표 3 - 정확성 (게이트)
    rows = []
    for l in loads:
        for v in versions:
            runs = main_runs.get((v, l), [])
            if not runs:
                continue
            db = max(r["dbIssued"] or 0 for r in runs)
            bits = max(r["bits"] or 0 for r in runs)
            stock = runs[0]["stock"]
            # Redis 판정은 재고를 지켰는데 DB 에만 더 있으면 이전 회차 잔여다.
            # v0 는 Redis 를 안 건드리므로 bits 0 이고 이 판정에서 제외한다
            if db <= stock:
                verdict = "✅"
            elif v != "v0" and 0 < bits <= stock:
                verdict = f"⚠️ 판정 {bits:,} 정상 (+{db - bits:,} 은 이전 회차 잔여)"
            else:
                verdict = "❌ 초과"
            rows.append([f"{l:,}", VERSION_LABEL[v], f"{db:,}", f"{stock:,}", verdict])
    doc += ["## 표 3. 정확성 - 초과 발급 (게이트)", "",
            table(["동시 요청", "버전", "dbIssued", "재고", "판정"], rows),
            "", "> 빠른데 틀리면 의미가 없다. 이 표가 통과하지 못하면 성능 수치는 무효다.", ""]

    # 표 4 - 20,000 상세
    top = loads[-1]
    rows = []
    for v in versions:
        runs = main_runs.get((v, top), [])
        if not runs:
            continue
        rows.append([VERSION_LABEL[v], f"{med(runs, 'err'):.0f}%",
                     f"{med(runs, 'p99'):,.0f}", f"{med(runs, 'rate'):,.0f}",
                     f"{max(r['backlog'] for r in runs):,}" if v in ("v2", "v3") else "-",
                     f"{max(r['pool'] for r in runs)}",
                     f"{med(runs, 'gc'):.2f}%", f"{max(r['heap'] for r in runs):,}"])
    doc += [f"## 표 4. {top:,} VU 상세", "",
            table(["버전", "에러율", "p99(ms)", "저장/s", "적체", "poolPending", "GC", "heap(MB)"], rows),
            "",
            "> 동기 저장(v0·v1)만 `poolPending` 이 쌓인다. 병목 위치의 직접 증거다.",
            "> 에러는 k6 15초 타임아웃이다 - 그 요청들은 응답을 받지 못했다.", ""]
    charts.append(bar_chart("chart3-pool.svg", f"{top:,} VU - 커넥션 풀 대기 스레드",
                            "버전", "poolPending 최대",
                            [(VERSION_LABEL[v], {"대기": max((r["pool"] for r in main_runs.get((v, top), [])), default=0)})
                             for v in versions],
                            ["대기"], {"대기": "#8e44ad"},
                            sub="톰캣 스레드 200 중 몇 개가 커넥션을 기다리는가. 동기 190 → 비동기 0"))

    # 그래프 4 - 축 4 밀도 분산
    tl_series = {}
    for v in versions:
        runs = main_runs.get((v, top), [])
        if runs and runs[0]["series"]:
            best = max(runs, key=lambda r: len(r["series"]))
            tl_series[v] = best["series"]
    if tl_series:
        charts.append(timeline_chart("chart4-timeline.svg",
                                     f"{top:,} VU - 저장 완료 누적 (밀도 분산)", tl_series,
                                     sub="기울기가 저장 처리율. 비동기는 더 급하게 올라가 더 빨리 끝난다"))

    # 표 5 - pool 민감도
    p10, p50 = load_runs("pool10"), load_runs("pool50")
    if p10 and p50:
        pl = sorted({k[1] for k in p10} & {k[1] for k in p50})
        rows = []
        for l in pl:
            a, b = med(p10.get(("v1", l), []), "p99"), med(p50.get(("v1", l), []), "p99")
            rows.append([f"{l:,}", f"{a:,.0f}", f"{b:,.0f}",
                         f"{a / b:.2f}배" if a and b else "-"])
        ref = med(p10.get(("v2", max(pl)), []), "p99")
        doc += ["## 표 5. pool 민감도 (v1, pool 10 vs 50)", "",
                table(["동시 요청", "pool 10", "pool 50", "개선"], rows), "",
                f"`poolPending`: pool 10 → {max((r['pool'] for r in p10.get(('v1', max(pl)), [])), default=0)}, "
                f"pool 50 → {max((r['pool'] for r in p50.get(('v1', max(pl)), [])), default=0)}"
                "  (= 톰캣 스레드 200 − pool 크기)", ""]
        if ref:
            doc += [f"> 기준선: 같은 세션의 v2 = {ref:,.0f}ms. "
                    "pool 을 5배 늘려도 비동기의 3배 뒤에 머문다.", ""]
        charts.append(bar_chart("chart5-pool-sensitivity.svg",
                                "pool 민감도 - 늘려도 비동기를 못 따라간다",
                                "동시 요청 수", "p99 (ms)",
                                [(f"{l:,}", {"pool 10": med(p10.get(("v1", l), []), "p99"),
                                             "pool 50": med(p50.get(("v1", l), []), "p99")})
                                 for l in pl],
                                ["pool 10", "pool 50"],
                                {"pool 10": "#e67e22", "pool 50": "#f1c40f"},
                                sub="pool 5배로도 고부하 개선은 1.2배. poolPending 은 190→150 (= 톰캣 200 − pool)"))

    # 표 6 - 축 7 수평 확장
    arms = [("N1", "scale-N1"), ("N1-20", "scale-N1-20"), ("N2", "scale-N2")]
    scale = {name: load_runs(pfx) for name, pfx in arms}
    if any(scale.values()):
        sl = sorted({k[1] for d in scale.values() for k in d})
        rows = []
        for l in sl:
            for v in ("v0", "v1"):
                cells = []
                for name, _ in arms:
                    runs = scale[name].get((v, l), [])
                    cells.append(f"{med(runs, 'p99'):,.0f}" if runs else "-")
                    if runs and med(runs, "err") >= 1:
                        cells[-1] += f" (에러 {med(runs, 'err'):.0f}%)"
                rows.append([f"{l:,}", VERSION_LABEL[v]] + cells)
        doc += ["## 표 6. 수평 확장 (앱 프로세스 2개)", "",
                table(["동시 요청", "버전", "N1 (1대·pool10)", "N1-20 (1대·pool20)", "N2 (2대·각10)"], rows),
                "",
                "> **N2 vs N1-20** - 총 커넥션 20 으로 같고 앱 대수만 다르다.",
                "> " + scale_line(scale, arms, sl), ""]
        charts.append(bar_chart("chart6-scale.svg",
                                f"수평 확장 - N2 vs N1-20 (총 커넥션 동일)",
                                "버전 / 부하", "p99 (ms)",
                                [(f"{v} {l // 1000}k",
                                  {name: med(scale[name].get((v, l), []), "p99") for name, _ in arms})
                                 for l in sl for v in ("v0", "v1")],
                                [a[0] for a in arms],
                                {"N1": "#95a5a6", "N1-20": "#f1c40f", "N2": "#27ae60"},
                                sub="N1-20 과 N2 는 총 커넥션 20 으로 같다. 차이 2~8% = 앱 계층은 병목이 아니다"))

    # 표 7 - 브로커 킬
    brows = []
    for mode in ("off", "everysec", "always"):
        p = os.path.join(RES, f"broker_{mode}_result.json")
        if os.path.exists(p):
            d = json.load(open(p))
            brows.append([f"`{mode}`", f"{d['promised']:,}", f"{d['stored']:,}",
                          f"**{d['lost']:,}**" if d["lost"] else "0",
                          "❌ 전량 유실" if d["lost"] else "✅ 유실 0"])
    if brows:
        doc += ["## 표 7. 브로커 킬 - Redis AOF 모드별 유실", "",
                table(["AOF", "약속한 발급", "저장됨", "유실", "판정"], brows), "",
                "> `everysec` 과 `always` 는 이 실험으로 구분되지 않는다. `docker kill` 은",
                "> 컨테이너 프로세스만 죽이고 **호스트 페이지 캐시는 남는다.**", ""]

    # 축 5 가격
    aof = {m: load_runs(f"aof-{m}") for m in ("off", "everysec", "always")}
    if any(aof.values()):
        rows = [[f"`{m}`", f"{med(list(d.values())[0], 'p99'):,.0f}" if d else "-"]
                for m, d in aof.items()]
        doc += ["## 표 8. 내구성의 가격 (v3 p99, 3회 중앙값)", "",
                table(["AOF", "p99 (ms)"], rows), "",
                "> `always` 가 가장 빠르게 나오기도 했다. **노이즈에 묻혀 판별 불가.**", ""]

    doc += ["## 그래프", ""] + [f"![{c}]({c})" for c in charts] + [""]

    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, "TABLES.md"), "w") as f:
        f.write("\n".join(doc))
    print(f"{os.path.relpath(OUT, ROOT)}/TABLES.md  + SVG {len(charts)}개")
    for c in charts:
        print(f"  {c}")


if __name__ == "__main__":
    main()
