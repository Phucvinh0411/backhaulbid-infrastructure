package com.backhaulbid.gateway.security;

import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.core.Ordered;
import org.springframework.data.redis.core.ReactiveStringRedisTemplate;
import org.springframework.data.redis.core.script.RedisScript;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;

import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

class RedisRateLimitFilterTest {

    @Test
    @SuppressWarnings("unchecked")
    void underLimitPassesThroughWithRateLimitHeadersAndActorKey() {
        ReactiveStringRedisTemplate redisTemplate = mock(ReactiveStringRedisTemplate.class);
        when(redisTemplate.execute(any(RedisScript.class), anyList(), anyList()))
                .thenReturn(Flux.just(5L));

        RedisRateLimitFilter filter = new RedisRateLimitFilter(redisTemplate);
        assertThat(filter.getOrder()).isEqualTo(Ordered.HIGHEST_PRECEDENCE + 1);

        AtomicBoolean forwarded = new AtomicBoolean(false);
        GatewayFilterChain chain = exchange -> {
            forwarded.set(true);
            return Mono.empty();
        };

        MockServerWebExchange bidExchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/api/v1/bidding/auctions/auc-1/bids")
                        .header("X-User-Id", "carrier-42")
                        .build());

        filter.filter(bidExchange, chain).block();

        assertThat(forwarded).isTrue();
        assertThat(bidExchange.getResponse().getHeaders().getFirst("X-RateLimit-Limit")).isEqualTo("60");
        assertThat(bidExchange.getResponse().getHeaders().getFirst("X-RateLimit-Remaining")).isEqualTo("55");

        ArgumentCaptor<List<String>> keysCaptor = ArgumentCaptor.forClass(List.class);
        verify(redisTemplate).execute(any(RedisScript.class), keysCaptor.capture(), anyList());
        assertThat(keysCaptor.getValue().get(0)).startsWith("gw:rl:bid-write:carrier-42:");
    }

    @Test
    @SuppressWarnings("unchecked")
    void exceedingLimitReturns429WithVietnameseJsonAndRetryAfter() {
        ReactiveStringRedisTemplate redisTemplate = mock(ReactiveStringRedisTemplate.class);
        when(redisTemplate.execute(any(RedisScript.class), anyList(), anyList()))
                .thenReturn(Flux.just(31L));

        RedisRateLimitFilter filter = new RedisRateLimitFilter(redisTemplate);

        AtomicBoolean forwarded = new AtomicBoolean(false);
        GatewayFilterChain chain = exchange -> {
            forwarded.set(true);
            return Mono.empty();
        };

        MockServerWebExchange loginExchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/api/v1/auth/login")
                        .remoteAddress(new InetSocketAddress("203.0.113.10", 54321))
                        .build());

        filter.filter(loginExchange, chain).block();

        assertThat(forwarded).isFalse();
        assertThat(loginExchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.TOO_MANY_REQUESTS);
        assertThat(loginExchange.getResponse().getHeaders().getFirst(HttpHeaders.CONTENT_TYPE))
                .isEqualTo("application/json;charset=UTF-8");
        assertThat(loginExchange.getResponse().getHeaders().getFirst(HttpHeaders.RETRY_AFTER))
                .isEqualTo("60");
        assertThat(loginExchange.getResponse().getHeaders().getFirst("X-RateLimit-Limit"))
                .isEqualTo("30");
        assertThat(loginExchange.getResponse().getHeaders().getFirst("X-RateLimit-Remaining"))
                .isEqualTo("0");

        String body = loginExchange.getResponse().getBodyAsString().block();
        assertThat(body).isEqualTo(
                new String(
                        "{\"status\":429,\"code\":\"RATE_LIMIT_EXCEEDED\",\"message\":\"Bạn thao tác quá nhanh. Vui lòng đợi ít giây rồi thử lại.\"}"
                                .getBytes(StandardCharsets.UTF_8),
                        StandardCharsets.UTF_8));
    }

    @Test
    @SuppressWarnings("unchecked")
    void redisErrorOrTimeoutFailsOpenCleanly() {
        ReactiveStringRedisTemplate redisTemplate = mock(ReactiveStringRedisTemplate.class);
        when(redisTemplate.execute(any(RedisScript.class), anyList(), anyList()))
                .thenReturn(Flux.error(new RuntimeException("Redis connection refused")))
                .thenReturn(Flux.never());

        RedisRateLimitFilter filter = new RedisRateLimitFilter(redisTemplate);

        AtomicBoolean firstForwarded = new AtomicBoolean(false);
        MockServerWebExchange otpExchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/api/v1/contracts/contract-99/sign/otp")
                        .header("X-User-Id", "shipper-1")
                        .build());
        filter.filter(otpExchange, ex -> {
            firstForwarded.set(true);
            return Mono.empty();
        }).block();
        assertThat(firstForwarded).isTrue();
        assertThat(otpExchange.getResponse().getStatusCode()).isNull();

        AtomicBoolean timeoutForwarded = new AtomicBoolean(false);
        MockServerWebExchange googleExchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/api/v1/auth/google").build());
        filter.filter(googleExchange, ex -> {
            timeoutForwarded.set(true);
            return Mono.empty();
        }).block();
        assertThat(timeoutForwarded).isTrue();
        assertThat(googleExchange.getResponse().getStatusCode()).isNull();

        MockServerWebExchange getExchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/bidding/auctions").build());
        AtomicBoolean getForwarded = new AtomicBoolean(false);
        ReactiveStringRedisTemplate untouchedRedis = mock(ReactiveStringRedisTemplate.class);
        new RedisRateLimitFilter(untouchedRedis).filter(getExchange, ex -> {
            getForwarded.set(true);
            return Mono.empty();
        }).block();
        assertThat(getForwarded).isTrue();
        verifyNoInteractions(untouchedRedis);
    }
}
