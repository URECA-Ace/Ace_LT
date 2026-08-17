package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import java.util.List;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Service;

// v3: Redis Lua 판정 + Outbox
// v2 와 큐만 다름
@Service
public class V3IssueService {

	private static final long DUPLICATE = -1L;
	private static final long SOLD_OUT = -2L;

	private final StringRedisTemplate redis;
	private final RedisScript<Long> issueStreamScript;

	public V3IssueService(StringRedisTemplate redis,
			@Qualifier("issueStreamScript") RedisScript<Long> issueStreamScript) {
		this.redis = redis;
		this.issueStreamScript = issueStreamScript;
	}

	public IssueResponse issue(long userId) {
		Long code = redis.execute(issueStreamScript,
				List.of(PocKeys.STOCK, PocKeys.ISSUED, PocKeys.STREAM),
				String.valueOf(userId));

		if (code == null) {
			return IssueResponse.ERROR;
		}
		if (code == DUPLICATE) {
			return IssueResponse.DUPLICATE;
		}
		if (code == SOLD_OUT) {
			return IssueResponse.SOLD_OUT;
		}
		return IssueResponse.ACCEPTED;
	}
}
