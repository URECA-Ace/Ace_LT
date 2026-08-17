-- v3 판정 + Outbox
-- issue.lua 와 같고 XADD 만 추가
-- KEYS[1] = stock   KEYS[2] = issued   KEYS[3] = stream
-- ARGV[1] = userId
-- 반환  -1 중복 / -2 재고 소진 / 0 성공
-- 서버가 죽어도 이벤트가 Redis 에 남음

if redis.call('GETBIT', KEYS[2], ARGV[1]) == 1 then
    return -1
end

local r = redis.call('DECR', KEYS[1])
if r < 0 then
    redis.call('INCR', KEYS[1])
    return -2
end

redis.call('SETBIT', KEYS[2], ARGV[1], 1)
redis.call('XADD', KEYS[3], '*', 'u', ARGV[1])
return 0
