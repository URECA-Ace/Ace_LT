package com.ace.lt.issue;

import org.springframework.dao.DuplicateKeyException;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

// 발급 엔드포인트
@RestController
public class IssueController {

	private final V0IssueService v0;
	private final V1IssueService v1;
	private final V2IssueService v2;

	public IssueController(V0IssueService v0, V1IssueService v1, V2IssueService v2) {
		this.v0 = v0;
		this.v1 = v1;
		this.v2 = v2;
	}

	// SOLD_OUT 은 예외를 쓰지 X
	@PostMapping("/v0/issue")
	public ResponseEntity<IssueResponse> v0(@RequestParam long userId) {
		try {
			return v0.issue(userId) == IssueResult.ISSUED
					? ResponseEntity.ok(IssueResponse.ISSUED)
					: ResponseEntity.status(HttpStatus.CONFLICT).body(IssueResponse.SOLD_OUT);
		}
		catch (DuplicateKeyException e) {
			return ResponseEntity.status(HttpStatus.CONFLICT).body(IssueResponse.DUPLICATE);
		}
	}

	@PostMapping("/v1/issue")
	public ResponseEntity<IssueResponse> v1(@RequestParam long userId) {
		return toResponse(v1.issue(userId));
	}

	@PostMapping("/v2/issue")
	public ResponseEntity<IssueResponse> v2(@RequestParam long userId) {
		return toResponse(v2.issue(userId));
	}

	private ResponseEntity<IssueResponse> toResponse(IssueResponse body) {
		return switch (body.code()) {
			case "ISSUED" -> ResponseEntity.ok(body);
			case "ACCEPTED" -> ResponseEntity.accepted().body(body);
			case "ERROR" -> ResponseEntity.status(HttpStatus.INTERNAL_SERVER_ERROR).body(body);
			default -> ResponseEntity.status(HttpStatus.CONFLICT).body(body);
		};
	}
}
