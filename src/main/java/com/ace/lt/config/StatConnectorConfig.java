package com.ace.lt.config;

import org.apache.catalina.connector.Connector;
import org.apache.coyote.http11.AbstractHttp11Protocol;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.tomcat.servlet.TomcatServletWebServerFactory;
import org.springframework.boot.web.server.WebServerFactoryCustomizer;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

// 폴러 전용 커넥터
// 기본 커넥터(8080)와 스레드풀이 분리
@Configuration
public class StatConnectorConfig {

	@Bean
	public WebServerFactoryCustomizer<TomcatServletWebServerFactory> statConnector(
			@Value("${poc.stat-port:8081}") int statPort) {
		return factory -> {
			Connector connector = new Connector("org.apache.coyote.http11.Http11NioProtocol");
			connector.setPort(statPort);
			if (connector.getProtocolHandler() instanceof AbstractHttp11Protocol<?> protocol) {
				protocol.setMaxThreads(20);
			}
			factory.addAdditionalConnectors(connector);
		};
	}
}
