package com.backhaulbid.gateway.security;

import io.jsonwebtoken.JwtException;
import org.springframework.cloud.gateway.filter.GatewayFilterChain;
import org.springframework.cloud.gateway.filter.GlobalFilter;
import org.springframework.core.Ordered;
import org.springframework.http.HttpCookie;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;
import org.springframework.web.server.ServerWebExchange;
import reactor.core.publisher.Mono;

import java.util.Optional;

@Component
public class JwtGlobalFilter implements GlobalFilter, Ordered {

    static final String ACCESS_TOKEN_COOKIE = "accessToken";
    static final String USER_ID_HEADER = "X-User-Id";
    static final String USER_ROLE_HEADER = "X-User-Role";

    private final JwtTokenService jwtTokenService;

    public JwtGlobalFilter(JwtTokenService jwtTokenService) {
        this.jwtTokenService = jwtTokenService;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest sanitizedRequest = exchange.getRequest().mutate()
                .headers(headers -> {
                    headers.remove(USER_ID_HEADER);
                    headers.remove(USER_ROLE_HEADER);
                })
                .build();
        ServerWebExchange sanitizedExchange = exchange.mutate()
                .request(sanitizedRequest)
                .build();

        if (isPublicRequest(sanitizedRequest)) {
            return chain.filter(sanitizedExchange);
        }

        Optional<String> accessToken = resolveAccessToken(sanitizedRequest);
        if (accessToken.isEmpty()) {
            return unauthorized(exchange);
        }

        try {
            AuthenticatedUser user = jwtTokenService.parseAccessToken(accessToken.get());
            if (!StringUtils.hasText(user.accountId()) || !StringUtils.hasText(user.role())) {
                return unauthorized(exchange);
            }

            ServerHttpRequest authenticatedRequest = sanitizedRequest.mutate()
                    .headers(headers -> {
                        headers.set(USER_ID_HEADER, user.accountId());
                        headers.set(USER_ROLE_HEADER, user.role());
                    })
                    .build();
            return chain.filter(sanitizedExchange.mutate()
                    .request(authenticatedRequest)
                    .build());
        } catch (JwtException | IllegalArgumentException exception) {
            return unauthorized(exchange);
        }
    }

    @Override
    public int getOrder() {
        return Ordered.HIGHEST_PRECEDENCE;
    }

    private boolean isPublicRequest(ServerHttpRequest request) {
        String path = request.getPath().value();
        return request.getMethod() == HttpMethod.OPTIONS
                || path.startsWith("/api/v1/auth/")
                || path.startsWith("/swagger-ui")
                || path.startsWith("/v3/api-docs")
                || path.equals("/actuator/health")
                || path.equals("/actuator/info")
                || (!path.startsWith("/api/v1/") && !path.startsWith("/api/") && !path.startsWith("/bidding-socket/")); // Web portal paths are public
    }

    private Optional<String> resolveAccessToken(ServerHttpRequest request) {
        HttpCookie cookie = request.getCookies().getFirst(ACCESS_TOKEN_COOKIE);
        if (cookie != null && StringUtils.hasText(cookie.getValue())) {
            return Optional.of(cookie.getValue());
        }

        String authorization = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        if (StringUtils.hasText(authorization) && authorization.startsWith("Bearer ")) {
            String token = authorization.substring(7);
            if (StringUtils.hasText(token)) {
                return Optional.of(token);
            }
        }

        return Optional.empty();
    }

    private Mono<Void> unauthorized(ServerWebExchange exchange) {
        exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
        return exchange.getResponse().setComplete();
    }
}
