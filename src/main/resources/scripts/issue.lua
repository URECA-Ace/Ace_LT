-- 발급 판정 스크립트

-- KEYS[1] = stock   (재고 카운터)
-- KEYS[2] = issued  (발급자 비트맵)
-- ARGV[1] = userId
--
-- 반환  -1 = 중복 발급
--       -2 = 재고 소진
--        0 = 발급 성공

if redis.call('GETBIT', KEYS[2], ARGV[1]) == 1 then
    return -1
end

local r = redis.call('DECR', KEYS[1])
if r < 0 then
    -- 음수까지 내려간 경우 되돌린다.
    redis.call('INCR', KEYS[1])
    return -2
end

redis.call('SETBIT', KEYS[2], ARGV[1], 1)
return 0
