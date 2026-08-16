-- PoC 스키마
-- 앱 기동 시 자동 실행 (spring.sql.init.mode=always)
-- 재고 10,000 고정, 동시 요청만 바꿔가며 측정

CREATE TABLE IF NOT EXISTS stock (
    id        BIGINT PRIMARY KEY,
    total     INT NOT NULL,
    remaining INT NOT NULL
);

CREATE TABLE IF NOT EXISTS issue (
    id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    stock_id   BIGINT NOT NULL,
    user_id    BIGINT NOT NULL,
    created_at DATETIME(6) DEFAULT CURRENT_TIMESTAMP(6),
    -- 1인 1매
    UNIQUE KEY uk_stock_user (stock_id, user_id)
);

INSERT INTO stock (id, total, remaining)
VALUES (1, 10000, 10000)
ON DUPLICATE KEY UPDATE id = id;
