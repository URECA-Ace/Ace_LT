import http from 'k6/http';
import { Counter } from 'k6/metrics';

// 1인 1매 검증 전용 1,000 VU 가 userId 100개를 공유
// 재고가 10,000 이라 소진은 일어나지 X 중복만 걸러짐
// 통과 조건: dbIssued == 100
const HOST = __ENV.HOST || 'localhost:8080';
const VERSION = __ENV.VERSION || 'v3';
const USERS = parseInt(__ENV.USERS || '100', 10);

export const options = {
	scenarios: {
		dup: { executor: 'per-vu-iterations', vus: 1000, iterations: 1, maxDuration: '60s' },
	},
};

const nIssued = new Counter('n_issued');
const nDuplicate = new Counter('n_duplicate');
const nOther = new Counter('n_other');

export default function () {
	const userId = (__VU % USERS) + 1;
	const res = http.post(`http://${HOST}/${VERSION}/issue?userId=${userId}`, null,
		{ timeout: '15s' });

	if (res.status === 200 || res.status === 202) {
		nIssued.add(1);
	} else if (res.status === 409) {
		nDuplicate.add(1);
	} else {
		nOther.add(1);
	}
}

export function handleSummary(data) {
	const get = (n) => (data.metrics[n] ? data.metrics[n].values.count : 0);
	const issued = get('n_issued');
	const dup = get('n_duplicate');
	const other = get('n_other');

	// 발급 응답이 유저 수를 넘으면 1인 1매 위반
	const verdict = issued === USERS && other === 0 ? 'OK' : '확인 필요';
	const lines = [
		'',
		`  1인 1매 검증  ${verdict}`,
		`    발급 응답 ${issued} (기대 ${USERS})   중복 거절 ${dup}   기타 ${other}`,
		'    ※ 최종 판정은 /stat 의 dbIssued 로 한다 (v2/v3 는 저장이 나중이므로)',
		'',
	];
	return {
		'results/dup.json': JSON.stringify({ issued, dup, other, users: USERS }, null, 2),
		stdout: lines.join('\n'),
	};
}
