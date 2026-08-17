import http from 'k6/http';
import { Trend, Counter } from 'k6/metrics';

// 쉼표로 여러 대를 주면 VU 를 라운드로빈으로 나눈다 (nginx RR 대체)
const HOSTS = (__ENV.HOSTS || __ENV.HOST || 'localhost:8080').split(',');
const HOST = HOSTS[0];
const VERSION = __ENV.VERSION || 'v0';
const VUS = parseInt(__ENV.VUS || '1000', 10);
const TAG = __ENV.TAG || `${VERSION}_${VUS}`;
const SHA = __ENV.SHA || 'unknown';
const STOCK = parseInt(__ENV.STOCK || '10000', 10);

// per-vu-iterations 는 전 VU 를 t=0 에 동시 기동 (JMeter Synchronizing Timer 대체)
export const options = {
	scenarios: {
		spike: {
			executor: 'per-vu-iterations',
			vus: VUS,
			iterations: 1,
			maxDuration: '120s',
		},
	},
	// 임계값 없음
	// 붕괴를 관측하는 게 목적이라 실패로 중단X
	summaryTrendStats: ['avg', 'min', 'med', 'p(95)', 'p(99)', 'max'],
};

// timings.waiting = TTFB
const waitSuccess = new Trend('wait_success', true);
const waitReject = new Trend('wait_reject', true);
const waitError = new Trend('wait_error', true);
const nSuccess = new Counter('n_success');
const nReject = new Counter('n_reject');
const nError = new Counter('n_error');

export default function () {
	const target = HOSTS[(__VU - 1) % HOSTS.length];
	const res = http.post(
		`http://${target}/${VERSION}/issue?userId=${__VU}`,
		null,
		{ timeout: '15s' },
	);

	const w = res.timings.waiting;

	if (res.status === 200 || res.status === 202) {
		waitSuccess.add(w);
		nSuccess.add(1);
	} else if (res.status === 409) {
		waitReject.add(w);
		nReject.add(1);
	} else {
		waitError.add(w);
		nError.add(1);
	}
}

export function handleSummary(data) {
	const m = data.metrics;
	const get = (name, stat) => (m[name] && m[name].values[stat] != null ? m[name].values[stat] : null);

	const out = {
		tag: TAG,
		version: VERSION,
		hosts: HOSTS,
		vus: VUS,
		stock: STOCK,
		sha: SHA,
		ranAt: new Date().toISOString(),
		count: {
			success: get('n_success', 'count') || 0,
			reject: get('n_reject', 'count') || 0,
			error: get('n_error', 'count') || 0,
			dropped: get('dropped_iterations', 'count') || 0,
		},
		waitMs: {
			success: { p95: get('wait_success', 'p(95)'), p99: get('wait_success', 'p(99)'), max: get('wait_success', 'max') },
			reject: { p95: get('wait_reject', 'p(95)'), p99: get('wait_reject', 'p(99)'), max: get('wait_reject', 'max') },
			error: { p99: get('wait_error', 'p(99)') },
		},
		durationMs: {
			p99: get('http_req_duration', 'p(99)'),
			blockedP99: get('http_req_blocked', 'p(99)'),
		},
		elapsedSec: data.state.testRunDurationMs / 1000,
	};
	out.tps = out.count.success + out.count.reject + out.count.error > 0
		? (out.count.success + out.count.reject + out.count.error) / out.elapsedSec
		: 0;

	return {
		[`results/${TAG}.json`]: JSON.stringify(out, null, 2),
		stdout: '\n',
	};
}
