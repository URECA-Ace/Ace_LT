package com.ace.lt.admin;

import com.ace.lt.common.PocKeys;
import com.zaxxer.hikari.HikariDataSource;
import com.zaxxer.hikari.HikariPoolMXBean;
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.lang.management.MemoryPoolMXBean;
import java.nio.charset.StandardCharsets;
import java.util.LinkedHashMap;
import java.util.Map;
import javax.sql.DataSource;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

// 측정 제어
// 폴러가 200ms 마다 /stat 을 긁어 타임라인을 만든다.
@RestController
public class AdminController {

	private static final long MB = 1024L * 1024L;

	private final JdbcTemplate jdbc;
	private final StringRedisTemplate redis;
	private final DataSource dataSource;
	private final String instanceId;

	public AdminController(JdbcTemplate jdbc, StringRedisTemplate redis, DataSource dataSource,
			@Value("${poc.instance}") String instanceId) {
		this.jdbc = jdbc;
		this.redis = redis;
		this.dataSource = dataSource;
		this.instanceId = instanceId;
	}

	// 회차 초기화
	// stock 파라미터는 소량 재고 정확성 검증용
	@PostMapping("/reset")
	public Map<String, Object> reset(
			@RequestParam(defaultValue = "" + PocKeys.TOTAL_STOCK) int stock) {
		jdbc.execute("TRUNCATE TABLE issue");
		jdbc.update("UPDATE stock SET remaining = ? WHERE id = ?", stock, PocKeys.STOCK_ID);

		redis.opsForValue().set(PocKeys.STOCK, String.valueOf(stock));
		redis.delete(PocKeys.ISSUED);

		return stat();
	}

	// 측정 지표 스냅샷
	@GetMapping("/stat")
	public Map<String, Object> stat() {
		Map<String, Object> stat = new LinkedHashMap<>();
		stat.put("ts", System.currentTimeMillis());
		stat.put("instance", instanceId);

		stat.put("dbIssued", jdbc.queryForObject("SELECT COUNT(*) FROM issue", Long.class));
		stat.put("dbRemaining", jdbc.queryForObject(
				"SELECT remaining FROM stock WHERE id = ?", Integer.class, PocKeys.STOCK_ID));

		stat.put("redisRemaining", redisRemaining());
		stat.put("redisIssuedBits", issuedBitCount());

		addPoolStat(stat);
		addJvmStat(stat);
		return stat;
	}

	private Long redisRemaining() {
		String raw = redis.opsForValue().get(PocKeys.STOCK);
		return raw == null ? null : Long.parseLong(raw);
	}

	private Long issuedBitCount() {
		return redis.execute(conn -> conn.stringCommands()
				.bitCount(PocKeys.ISSUED.getBytes(StandardCharsets.UTF_8)), true);
	}

	private void addPoolStat(Map<String, Object> stat) {
		if (dataSource instanceof HikariDataSource hikari) {
			HikariPoolMXBean pool = hikari.getHikariPoolMXBean();
			if (pool != null) {
				stat.put("poolActive", pool.getActiveConnections());
				stat.put("poolPending", pool.getThreadsAwaitingConnection());
				stat.put("poolTotal", pool.getTotalConnections());
			}
		}
	}

	// MXBean 직접 조회
	private void addJvmStat(Map<String, Object> stat) {
		long gcCount = 0;
		long gcTimeMs = 0;
		for (GarbageCollectorMXBean gc : ManagementFactory.getGarbageCollectorMXBeans()) {
			long count = gc.getCollectionCount();
			long time = gc.getCollectionTime();
			if (count > 0) {
				gcCount += count;
			}
			if (time > 0) {
				gcTimeMs += time;
			}
		}
		stat.put("gcCount", gcCount);
		stat.put("gcTimeMs", gcTimeMs);

		stat.put("heapUsedMb",
				ManagementFactory.getMemoryMXBean().getHeapMemoryUsage().getUsed() / MB);

		// ZGC 는 세대 구분이 없어 0 이 나온다
		long oldGen = 0;
		for (MemoryPoolMXBean pool : ManagementFactory.getMemoryPoolMXBeans()) {
			if (pool.getName().contains("Old Gen")) {
				oldGen += pool.getUsage().getUsed();
			}
		}
		stat.put("oldGenUsedMb", oldGen / MB);
	}
}
