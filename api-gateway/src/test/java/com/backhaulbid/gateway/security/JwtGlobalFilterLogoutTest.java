package com.backhaulbid.gateway.security;

import org.junit.jupiter.api.Test;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.http.HttpCookie;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.concurrent.atomic.AtomicBoolean;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verifyNoInteractions;

class JwtGlobalFilterLogoutTest {

    @Test
    void logoutPassesThroughWithMissingOrExpiredCookieWhileMeAndDriverLogoutRequireAuth() {
        JwtTokenService tokenService = mock(JwtTokenService.class);
        JwtGlobalFilter filter = new JwtGlobalFilter(tokenService);

        AtomicBoolean logoutForwarded = new AtomicBoolean(false);
        GatewayFilterChain chain = exchange -> {
            logoutForwarded.set(true);
            return Mono.empty();
        };

        MockServerWebExchange logoutExchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/api/v1/auth/logout")
                        .cookie(new HttpCookie("accessToken", "expired.jwt.token"))
                        .build());
        filter.filter(logoutExchange, chain).block();
        assertThat(logoutForwarded).isTrue();
        verifyNoInteractions(tokenService);

        MockServerWebExchange meExchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/auth/me").build());
        filter.filter(meExchange, ex -> Mono.empty()).block();
        assertThat(meExchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);

        MockServerWebExchange driverLogoutExchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/api/v1/auth/driver/logout").build());
        filter.filter(driverLogoutExchange, ex -> Mono.empty()).block();
        assertThat(driverLogoutExchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
    }
}
