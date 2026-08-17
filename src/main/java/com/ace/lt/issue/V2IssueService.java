package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import java.util.List;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Service;

// v2: Redis Lua 판정 + 비동기 저장
// 저장을 기다리지 않고 202 로 끊음
@Service
public class V2IssueService {

	private static final long DUPLICATE = -1L;
	private static final long SOLD_OUT = -2L;

	private final StringRedisTemplate redis;
	private final RedisScript<Long> issueScript;
	private final MemoryQueueDrainer queue;

	public V2IssueService(StringRedisTemplate redis, RedisScript<Long> issueScript,
			MemoryQueueDrainer queue) {
		this.redis = redis;
		this.issueScript = issueScript;
		this.queue = queue;
	}

	public IssueResponse issue(long userId) {
		Long code = redis.execute(issueScript,
				List.of(PocKeys.STOCK, PocKeys.ISSUED), String.valueOf(userId));

		if (code == null) {
			return IssueResponse.ERROR;
		}
		if (code == DUPLICATE) {
			return IssueResponse.DUPLICATE;
		}
		if (code == SOLD_OUT) {
			return IssueResponse.SOLD_OUT;
		}

		queue.offer(userId);
		return IssueResponse.ACCEPTED;
	}
}
