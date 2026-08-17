package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

// v1 저장
@Service
public class IssuePersistenceService {

	private final JdbcTemplate jdbc;

	public IssuePersistenceService(JdbcTemplate jdbc) {
		this.jdbc = jdbc;
	}

	@Transactional
	public void persist(long userId) {
		jdbc.update("INSERT INTO issue (stock_id, user_id) VALUES (?, ?)",
				PocKeys.STOCK_ID, userId);
	}
}
