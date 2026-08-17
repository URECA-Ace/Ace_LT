package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import java.util.List;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.dao.DuplicateKeyException;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.stereotype.Service;

// v1: Redis Lua 판정 + MySQL 동기 저장
@Service
public class V1IssueService {

	private static final long DUPLICATE = -1L;
	private static final long SOLD_OUT = -2L;

	private final StringRedisTemplate redis;
	private final RedisScript<Long> issueScript;
	private final IssuePersistenceService persistence;
	private final IssueCompensator compensator;

	public V1IssueService(StringRedisTemplate redis,
			@Qualifier("issueScript") RedisScript<Long> issueScript,
			IssuePersistenceService persistence, IssueCompensator compensator) {
		this.redis = redis;
		this.issueScript = issueScript;
		this.persistence = persistence;
		this.compensator = compensator;
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

		try {
			persistence.persist(userId);
			return IssueResponse.ISSUED;
		}
		catch (DuplicateKeyException e) {
			// Redis 는 통과했는데 DB 에 이미 있는 경우에는 재고만 되돌린다
			compensator.restoreStockOnly();
			return IssueResponse.DUPLICATE;
		}
		catch (RuntimeException e) {
			compensator.compensate(userId);
			return IssueResponse.ERROR;
		}
	}
}
