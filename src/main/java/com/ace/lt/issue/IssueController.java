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

	public IssueController(V0IssueService v0) {
		this.v0 = v0;
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
			// 트랜잭션 프록시를 빠져나오며 이미 롤백됨
			return ResponseEntity.status(HttpStatus.CONFLICT).body(IssueResponse.DUPLICATE);
		}
	}
}
