package com.ace.lt.issue;

import com.ace.lt.common.PocKeys;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.data.redis.connection.stream.Consumer;
import org.springframework.data.redis.connection.stream.MapRecord;
import org.springframework.data.redis.connection.stream.ReadOffset;
import org.springframework.data.redis.connection.stream.StreamOffset;
import org.springframework.data.redis.connection.stream.StreamReadOptions;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

// v3 저장
@Component
public class StreamRelay {

	private static final Logger log = LoggerFactory.getLogger(StreamRelay.class);
	private static final int BATCH = 500;

	// 고정 이름
	// 재기동 후 같은 컨슈머로 붙어야 함
	private static final String CONSUMER = "relay-1";

	private final StringRedisTemplate redis;
	private final JdbcTemplate jdbc;

	private final AtomicBoolean enabled = new AtomicBoolean(true);
	// 기동/리셋 직후엔 미ACK 엔트리부터 처리
	private final AtomicBoolean recoverPending = new AtomicBoolean(true);

	public StreamRelay(StringRedisTemplate redis, JdbcTemplate jdbc) {
		this.redis = redis;
		this.jdbc = jdbc;
	}

	public void setEnabled(boolean value) {
		enabled.set(value);
	}

	public boolean isEnabled() {
		return enabled.get();
	}

	public void onReset() {
		recoverPending.set(true);
	}

	@Scheduled(fixedDelay = 50)
	public void drain() {
		if (!enabled.get()) {
			return;
		}

		try {
			boolean recovering = recoverPending.get();
			// 컨슈머의 미ACK 목록 반환
			List<MapRecord<String, String, String>> records = read(
					recovering ? ReadOffset.from("0") : ReadOffset.lastConsumed());

			if (records == null || records.isEmpty()) {
				if (recovering) {
					recoverPending.set(false);
				}
				return;
			}

			persist(records);
			ack(records);
		}
		catch (RuntimeException e) {
			// ACK 하지 않았으므로 엔트리는 pending 에 남음
			log.warn("relay 실패, 재시도 예정: {}", e.getMessage());
		}
	}

	private List<MapRecord<String, String, String>> read(ReadOffset offset) {
		return redis.<String, String>opsForStream().read(
				Consumer.from(PocKeys.GROUP, CONSUMER),
				StreamReadOptions.empty().count(BATCH),
				StreamOffset.create(PocKeys.STREAM, offset));
	}

	private void persist(List<MapRecord<String, String, String>> records) {
		jdbc.batchUpdate("INSERT IGNORE INTO issue (stock_id, user_id) VALUES (?, ?)",
				records, records.size(),
				(ps, record) -> {
					ps.setLong(1, PocKeys.STOCK_ID);
					ps.setLong(2, Long.parseLong(record.getValue().get("u")));
				});
	}

	private void ack(List<MapRecord<String, String, String>> records) {
		String[] ids = records.stream()
				.map(record -> record.getId().getValue())
				.toArray(String[]::new);
		redis.opsForStream().acknowledge(PocKeys.STREAM, PocKeys.GROUP, ids);
	}
}
