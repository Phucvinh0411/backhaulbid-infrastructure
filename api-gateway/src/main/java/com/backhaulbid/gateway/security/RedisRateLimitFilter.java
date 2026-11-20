package com.backhaulbid.gateway.security;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.DefaultRedisScript;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.PathContainer;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.http.server.reactive.ServerHttpResponse;
import org.springframework.lang.Nullable;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.server.ServerWebExchange;
import org.springframework.web.util.pattern.PathPattern;
import org.springframework.web.util.pattern.PathPatternParser;
import reactor.core.publisher.Mono;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;

@Component
public class RedisRateLimitFilter implements GlobalFilter, Ordered {

    private static final Logger log = LoggerFactory.getLogger(RedisRateLimitFilter.class);

    static final long WINDOW_MS = 60_000L;
    static final Duration REDIS_TIMEOUT = Duration.ofMillis(400);
    static final String RATE_LIMIT_LIMIT_HEADER = "X-RateLimit-Limit";
    static final String RATE_LIMIT_REMAINING_HEADER = "X-RateLimit-Remaining";
    static final String RATE_LIMIT_BODY =
            "{\"status\":429,\"code\":\"RATE_LIMIT_EXCEEDED\",\"message\":\"Bạn thao tác quá nhanh. Vui lòng đợi ít giây rồi thử lại.\"}";
    private static final byte[] RATE_LIMIT_BODY_BYTES = RATE_LIMIT_BODY.getBytes(StandardCharsets.UTF_8);

    static final DefaultRedisScript<Long> INCREMENT_SCRIPT = new DefaultRedisScript<>(
            "local c = redis.call('INCR', KEYS[1]); if c == 1 then redis.call('PEXPIRE', KEYS[1], ARGV[1]); end; return c;",
            Long.class
    );

    private static final PathPattern CONTRACT_SIGN_OTP_PATTERN =
            PathPatternParser.defaultInstance.parse("/api/v1/contracts/*/sign/otp");

    private static final Bucket AUTH_WRITE_BUCKET = new Bucket("auth-write", 30);
    private static final Bucket BID_WRITE_BUCKET = new Bucket("bid-write", 60);

    record Bucket(String name, long limit) {}

    @Nullable
    private final ReactiveStringRedisTemplate redisTemplate;

    public RedisRateLimitFilter(@Nullable ReactiveStringRedisTemplate redisTemplate) {
        this.redisTemplate = redisTemplate;
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE + 1;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest request = exchange.getRequest();
        Bucket bucket = resolveBucket(request);
        if (bucket == null || redisTemplate == null) {
            return chain.filter(exchange);
        }

        String actor = resolveActor(request);
        long window = System.currentTimeMillis() / WINDOW_MS;
        String key = "gw:rl:" + bucket.name() + ":" + actor + ":" + window;

        return Mono.defer(() -> redisTemplate.execute(
                        INCREMENT_SCRIPT,
                        List.of(key),
                        List.of(String.valueOf(WINDOW_MS)))
                .next())
                .timeout(REDIS_TIMEOUT)
                .onErrorResume(ex -> {
                    log.debug("Redis rate-limit check failed for key {}, failing open: {}", key, ex.toString());
                    return Mono.just(-1L);
                })
                .defaultIfEmpty(-1L)
                .flatMap(count -> {
                    if (count < 0) {
                        return chain.filter(exchange);
                    }
                    long remaining = Math.max(0L, bucket.limit() - count);
                    ServerHttpResponse response = exchange.getResponse();
                    response.getHeaders().set(RATE_LIMIT_LIMIT_HEADER, String.valueOf(bucket.limit()));
                    response.getHeaders().set(RATE_LIMIT_REMAINING_HEADER, String.valueOf(remaining));

                    if (count > bucket.limit()) {
                        response.setStatusCode(HttpStatus.TOO_MANY_REQUESTS);
                        response.getHeaders().set(HttpHeaders.CONTENT_TYPE, "application/json;charset=UTF-8");
                        response.getHeaders().set(HttpHeaders.RETRY_AFTER, "60");
                        return response.writeWith(Mono.just(response.bufferFactory().wrap(RATE_LIMIT_BODY_BYTES)));
                    }

                    return chain.filter(exchange);
                });
    }

    @Nullable
    static Bucket resolveBucket(ServerHttpRequest request) {
        if (request.getMethod() != HttpMethod.POST) {
            return null;
        }
        String rawPath = request.getPath().value();
        String path = (rawPath.length() > 1 && rawPath.endsWith("/"))
                ? rawPath.substring(0, rawPath.length() - 1)
                : rawPath;

        if (path.equals("/api/v1/auth/login")
                || path.equals("/api/v1/auth/register")
                || path.equals("/api/v1/auth/google")
                || CONTRACT_SIGN_OTP_PATTERN.matches(PathContainer.parsePath(path))) {
            return AUTH_WRITE_BUCKET;
        }

        if (path.equals("/api/v1/bidding")
                || path.startsWith("/api/v1/bidding/")
                || path.equals("/api/v1/bids")
                || path.startsWith("/api/v1/bids/")) {
            return BID_WRITE_BUCKET;
        }

        return null;
    }

    static String resolveActor(ServerHttpRequest request) {
        String userId = request.getHeaders().getFirst(JwtGlobalFilter.USER_ID_HEADER);
        if (StringUtils.hasText(userId)) {
            return userId.trim();
        }
        String forwardedFor = request.getHeaders().getFirst("X-Forwarded-For");
        if (StringUtils.hasText(forwardedFor)) {
            String firstIp = forwardedFor.split(",")[0].trim();
            if (StringUtils.hasText(firstIp)) {
                return firstIp;
            }
        }
        InetSocketAddress remoteAddress = request.getRemoteAddress();
        if (remoteAddress != null) {
            if (remoteAddress.getAddress() != null) {
                return remoteAddress.getAddress().getHostAddress();
            }
            if (StringUtils.hasText(remoteAddress.getHostString())) {
                return remoteAddress.getHostString();
            }
        }
        return "unknown";
    }
}
