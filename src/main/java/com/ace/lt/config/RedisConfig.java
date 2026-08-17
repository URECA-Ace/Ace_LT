package com.ace.lt.config;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.data.redis.core.script.RedisScript;

@Configuration
public class RedisConfig {

	// v1 / v2 공용
	@Bean
	public RedisScript<Long> issueScript() {
		return script("scripts/issue.lua");
	}

	// v3 - XADD 만 추가
	@Bean
	public RedisScript<Long> issueStreamScript() {
		return script("scripts/issue_stream.lua");
	}

	// setLocation 을 쓰면 Spring 이 EVALSHA 를 자동 처리
	private RedisScript<Long> script(String path) {
		DefaultRedisScript<Long> script = new DefaultRedisScript<>();
		script.setLocation(new ClassPathResource(path));
		script.setResultType(Long.class);
		return script;
	}
}
