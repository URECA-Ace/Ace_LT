package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

// v0: 판정과 저장을 모두 MySQL 에서 -> stock 단일 row 를 FOR UPDATE 로 잠근다
@Service
public class V0IssueService {

	private final JdbcTemplate jdbc;

	public V0IssueService(JdbcTemplate jdbc) {
		this.jdbc = jdbc;
	}

	// 중복이면 DuplicateKeyException
	// 재고 차감을 되돌려야 하므로 롤백이 필요
	@Transactional
	public IssueResult issue(long userId) {
		Integer remaining = jdbc.queryForObject(
				"SELECT remaining FROM stock WHERE id = ? FOR UPDATE",
				Integer.class, PocKeys.STOCK_ID);

		if (remaining == null || remaining <= 0) {
			return IssueResult.SOLD_OUT;
		}

		jdbc.update("UPDATE stock SET remaining = remaining - 1 WHERE id = ?", PocKeys.STOCK_ID);
		jdbc.update("INSERT INTO issue (stock_id, user_id) VALUES (?, ?)",
				PocKeys.STOCK_ID, userId);

		return IssueResult.ISSUED;
	}
}
