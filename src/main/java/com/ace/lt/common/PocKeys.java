package com.ace.lt.common;

// Redis 키와 재고 상수
public final class PocKeys {

	// 재고 카운터
	public static final String STOCK = "stock";

	// 발급자 비트맵 (userId = 비트 오프셋)
	public static final String ISSUED = "issued";

	public static final String STREAM = "issue-stream";

	public static final String GROUP = "issue-relay";

	// 재고 총량
	public static final int TOTAL_STOCK = 10_000;

	public static final long STOCK_ID = 1L;

	private PocKeys() {
	}
}
