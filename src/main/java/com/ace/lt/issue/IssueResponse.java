package com.ace.lt.issue;

// 응답 바디는 최소로
public record IssueResponse(String code) {

	public static final IssueResponse ISSUED = new IssueResponse("ISSUED");
	// v2/v3 - 저장 완료가 아니라 발급 확보
	public static final IssueResponse ACCEPTED = new IssueResponse("ACCEPTED");
	public static final IssueResponse SOLD_OUT = new IssueResponse("SOLD_OUT");
	public static final IssueResponse DUPLICATE = new IssueResponse("DUPLICATE");
	public static final IssueResponse ERROR = new IssueResponse("ERROR");
}
