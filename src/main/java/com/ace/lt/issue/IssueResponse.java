package com.ace.lt.issue;

// 응답 바디는 최소로
public record IssueResponse(String code) {

	public static final IssueResponse ISSUED = new IssueResponse("ISSUED");
	public static final IssueResponse SOLD_OUT = new IssueResponse("SOLD_OUT");
	public static final IssueResponse DUPLICATE = new IssueResponse("DUPLICATE");
	public static final IssueResponse ERROR = new IssueResponse("ERROR");
}
