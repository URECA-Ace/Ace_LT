package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.BlockingQueue;
import java.util.concurrent.LinkedBlockingQueue;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

// v2 저장
// 큐는 일부러 무한 -> 메모리 큐의 위험을 드러내는 것이 v2 테스트
@Component
public class MemoryQueueDrainer {

	private static final Logger log = LoggerFactory.getLogger(MemoryQueueDrainer.class);
	private static final int BATCH = 500;

	private final BlockingQueue<Long> queue = new LinkedBlockingQueue<>();
	private final JdbcTemplate jdbc;

	public MemoryQueueDrainer(JdbcTemplate jdbc) {
		this.jdbc = jdbc;
	}

	public void offer(long userId) {
		queue.offer(userId);
	}

	public int size() {
		return queue.size();
	}

	public void clear() {
		queue.clear();
	}

	@Scheduled(fixedDelay = 50)
	public void drain() {
		List<Long> batch = new ArrayList<>(BATCH);
		queue.drainTo(batch, BATCH);
		if (batch.isEmpty()) {
			return;
		}

		try {
			// INSERT IGNORE
			// 배치 안에 중복이 섞여도 배치 전체가 실패하지 않도록
			jdbc.batchUpdate("INSERT IGNORE INTO issue (stock_id, user_id) VALUES (?, ?)",
					batch, batch.size(),
					(ps, userId) -> {
						ps.setLong(1, PocKeys.STOCK_ID);
						ps.setLong(2, userId);
					});
		}
		catch (RuntimeException e) {
			// 이미 큐에서 꺼냈으므로 이 배치는 사라짐
			log.warn("drain 실패 {}건 유실: {}", batch.size(), e.getMessage());
		}
	}
}
