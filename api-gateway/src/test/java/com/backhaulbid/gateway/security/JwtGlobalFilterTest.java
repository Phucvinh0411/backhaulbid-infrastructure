package com.backhaulbid.gateway.security;

import io.jsonwebtoken.JwtException;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.http.HttpCookie;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.mock.http.server.reactive.MockServerHttpRequest;
import org.springframework.mock.web.server.MockServerWebExchange;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;
import reactor.test.StepVerifier;

import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class JwtGlobalFilterTest {

    @Mock
    private JwtTokenService jwtTokenService;

    @InjectMocks
    private JwtGlobalFilter jwtGlobalFilter;

    @Test
    void filter_publicAuthRouteWithoutToken_forwardsRequest() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.post("/api/v1/auth/login").build());
        AtomicReference<ServerWebExchange> actualExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(actualExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(actualExchange.get()).isNotNull();
        verifyNoInteractions(jwtTokenService);
    }

    @Test
    void filter_optionsRequestWithoutToken_forwardsPreflight() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.method(HttpMethod.OPTIONS, "/api/v1/ekyc").build());
        AtomicReference<ServerWebExchange> actualExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(actualExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(actualExchange.get()).isNotNull();
        verifyNoInteractions(jwtTokenService);
    }

    @ParameterizedTest
    @ValueSource(strings = {
            "/swagger-ui.html",
            "/swagger-ui/index.html",
            "/v3/api-docs/swagger-config",
            "/v3/api-docs/identity-service"
    })
    void filter_documentationRouteWithoutToken_forwardsRequest(String path) {
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get(path).build());
        AtomicReference<ServerWebExchange> actualExchange = new AtomicReference<>();

        StepVerifier.create(jwtGlobalFilter.filter(exchange, capturingChain(actualExchange)))
                .verifyComplete();

        assertThat(actualExchange.get()).isNotNull();
        verifyNoInteractions(jwtTokenService);
    }

    @Test
    void filter_protectedRouteWithoutToken_returns401() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/ekyc").build());
        AtomicReference<ServerWebExchange> forwardedExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(forwardedExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(forwardedExchange.get()).isNull();
        verifyNoInteractions(jwtTokenService);
    }

    @Test
    void filter_notificationSocketWithoutToken_returns401() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/notification-socket/socket.io/").build());
        AtomicReference<ServerWebExchange> forwardedExchange = new AtomicReference<>();

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, capturingChain(forwardedExchange));

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(forwardedExchange.get()).isNull();
        verifyNoInteractions(jwtTokenService);
    }

    @Test
    void filter_notificationSocketWithValidToken_forwardsTrustedIdentityHeaders() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/notification-socket/socket.io/")
                        .cookie(new HttpCookie("accessToken", "cookie-token"))
                        .build());
        when(jwtTokenService.parseAccessToken("cookie-token"))
                .thenReturn(new AuthenticatedUser("notification-user", "SHIPPER"));
        AtomicReference<ServerWebExchange> actualExchange = new AtomicReference<>();

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, capturingChain(actualExchange));

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(actualExchange.get().getRequest().getHeaders().getFirst("X-User-Id"))
                .isEqualTo("notification-user");
        assertThat(actualExchange.get().getRequest().getHeaders().getFirst("X-User-Role"))
                .isEqualTo("SHIPPER");
    }

    @Test
    void filter_validAccessTokenCookie_forwardsTrustedIdentityHeaders() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/ekyc")
                        .cookie(new HttpCookie("accessToken", "cookie-token"))
                        .build());
        when(jwtTokenService.parseAccessToken("cookie-token"))
                .thenReturn(new AuthenticatedUser("account-123", "CARRIER"));
        AtomicReference<ServerWebExchange> actualExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(actualExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(actualExchange.get().getRequest().getHeaders().getFirst("X-User-Id"))
                .isEqualTo("account-123");
        assertThat(actualExchange.get().getRequest().getHeaders().getFirst("X-User-Role"))
                .isEqualTo("CARRIER");
    }

    @Test
    void filter_validBearerToken_forwardsTrustedIdentityHeaders() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/ekyc")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer bearer-token")
                        .build());
        when(jwtTokenService.parseAccessToken("bearer-token"))
                .thenReturn(new AuthenticatedUser("account-456", "SHIPPER"));
        AtomicReference<ServerWebExchange> actualExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(actualExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(actualExchange.get().getRequest().getHeaders().getFirst("X-User-Id"))
                .isEqualTo("account-456");
        assertThat(actualExchange.get().getRequest().getHeaders().getFirst("X-User-Role"))
                .isEqualTo("SHIPPER");
    }

    @Test
    void filter_spoofedIdentityHeaders_replacesWithJwtClaims() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/ekyc")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer valid-token")
                        .header("X-User-Id", "attacker-account")
                        .header("X-User-Role", "ADMIN")
                        .build());
        when(jwtTokenService.parseAccessToken("valid-token"))
                .thenReturn(new AuthenticatedUser("trusted-account", "CARRIER"));
        AtomicReference<ServerWebExchange> actualExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(actualExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(actualExchange.get().getRequest().getHeaders().get("X-User-Id"))
                .containsExactly("trusted-account");
        assertThat(actualExchange.get().getRequest().getHeaders().get("X-User-Role"))
                .containsExactly("CARRIER");
    }

    @Test
    void filter_invalidToken_returns401() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/ekyc")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer invalid-token")
                        .build());
        when(jwtTokenService.parseAccessToken("invalid-token"))
                .thenThrow(new JwtException("Invalid token"));
        AtomicReference<ServerWebExchange> forwardedExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(forwardedExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(forwardedExchange.get()).isNull();
    }

    @Test
    void filter_validTokenWithoutSubject_returns401() {
        // Given
        MockServerWebExchange exchange = MockServerWebExchange.from(
                MockServerHttpRequest.get("/api/v1/ekyc")
                        .header(HttpHeaders.AUTHORIZATION, "Bearer subjectless-token")
                        .build());
        when(jwtTokenService.parseAccessToken("subjectless-token"))
                .thenReturn(new AuthenticatedUser(null, "CARRIER"));
        AtomicReference<ServerWebExchange> forwardedExchange = new AtomicReference<>();
        GatewayFilterChain chain = capturingChain(forwardedExchange);

        // When
        Mono<Void> result = jwtGlobalFilter.filter(exchange, chain);

        // Then
        StepVerifier.create(result).verifyComplete();
        assertThat(exchange.getResponse().getStatusCode()).isEqualTo(HttpStatus.UNAUTHORIZED);
        assertThat(forwardedExchange.get()).isNull();
    }

    private GatewayFilterChain capturingChain(AtomicReference<ServerWebExchange> actualExchange) {
        return exchange -> {
            actualExchange.set(exchange);
            return Mono.empty();
        };
    }
}
