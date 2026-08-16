# 선착순 발급 아키텍처 비교 PoC

동시성 제어 아키텍처 4종의 처리량 한계를 측정 비교

기술 선택을 위해 데이터로 비교하는 것이 목표

| 버전 | 방식 | 엔드포인트 | 증명하는 것 |
|---|---|---|---|
| **v0** | MySQL 비관적 락 (`SELECT ... FOR UPDATE`) | `POST /v0/issue?userId=` | 기준선 |
| **v1** | Redis Lua 판정 + MySQL **동기** 저장 | `POST /v1/issue?userId=` | v0 대비 → **Redis 근거** |
| **v2** | Redis Lua 판정 + **비동기** 저장 (메모리 큐 + 배치) | `POST /v2/issue?userId=` | v1 대비 → **비동기 근거** |
| **v3** | Redis Lua 판정 + **내구 로그** (Stream Outbox + relay) | `POST /v3/issue?userId=` | v2 대비 → **Kafka/내구로그 근거** |

재고 10,000 고정. 동시 요청을 늘려가며 **어디까지 버티고 어떻게 무너지는지** 본다.

---

## 빠른 시작

```bash
# 1. 인프라 (MySQL 3308 / Redis 6380)
docker compose up -d
docker compose ps          

# 2. 앱 기동 - schema.sql 이 자동 실행된다
./gradlew bootRun

# 3. 확인
curl localhost:8080/actuator/health
curl -s localhost:8080/actuator/prometheus | grep hikaricp_connections_pending
```

---

## 스택

`Ace_BE` 와 **동일하게 맞췄습니다.**

| | 버전 |
|---|---|
| Java | 21 (toolchain) |
| Spring Boot | **4.1.0** |
| Gradle | 9.5.1 (wrapper) |
| MySQL | 8.4 |
| Redis | 8.2 |

---
