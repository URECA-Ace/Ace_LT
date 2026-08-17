package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.stereotype.Component;

// 보상은 트랜잭션 밖에서만 호출
@Component
public class IssueCompensator {

	private final StringRedisTemplate redis;

	public IssueCompensator(StringRedisTemplate redis) {
		this.redis = redis;
	}

	// 저장 실패
	// 재고와 발급 기록을 모두 되돌린다
	public void compensate(long userId) {
		redis.opsForValue().increment(PocKeys.STOCK);
		redis.opsForValue().setBit(PocKeys.ISSUED, userId, false);
	}

	// 중복
	// 사용자는 이미 발급받았으므로 비트는 그대로 두고 재고만 되돌린다
	public void restoreStockOnly() {
		redis.opsForValue().increment(PocKeys.STOCK);
	}
}
