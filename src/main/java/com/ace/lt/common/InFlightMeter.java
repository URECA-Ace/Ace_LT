package com.ace.lt.common;

import java.util.concurrent.atomic.AtomicInteger;
import org.springframework.stereotype.Component;

// 서버가 실제로 겪은 동시 요청 수
@Component
public class InFlightMeter {

	private final AtomicInteger current = new AtomicInteger();
	private final AtomicInteger peak = new AtomicInteger();

	public void enter() {
		int now = current.incrementAndGet();
		peak.getAndUpdate(p -> Math.max(p, now));
	}

	public void exit() {
		current.decrementAndGet();
	}

	public void reset() {
		peak.set(current.get());
	}

	public int current() {
		return current.get();
	}

	public int peak() {
		return peak.get();
	}
}
