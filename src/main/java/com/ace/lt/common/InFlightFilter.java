package com.ace.lt.common;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

// 발급 요청만
// 폴러의 /stat 이 섞이면 값이 오염된다
@Component
public class InFlightFilter extends OncePerRequestFilter {

	private final InFlightMeter meter;

	public InFlightFilter(InFlightMeter meter) {
		this.meter = meter;
	}

	@Override
	protected boolean shouldNotFilter(HttpServletRequest request) {
		return !request.getRequestURI().endsWith("/issue");
	}

	@Override
	protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
			FilterChain chain) throws ServletException, IOException {
		meter.enter();
		try {
			chain.doFilter(request, response);
		}
		finally {
			meter.exit();
		}
	}
}
