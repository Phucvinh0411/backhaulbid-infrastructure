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

import java.util.List;
import java.util.Optional;

@Component
public class JwtGlobalFilter implements GlobalFilter, Ordered {

    static final String ACCESS_TOKEN_COOKIE = "accessToken";
    static final String USER_ID_HEADER = "X-User-Id";
    static final String USER_ROLE_HEADER = "X-User-Role";
    static final String AUTH_TYPE_HEADER = "X-Auth-Type";
    static final String DRIVER_TRIP_HEADER = "X-Driver-Trip-Id";
    static final String DRIVER_PROFILE_HEADER = "X-Driver-Profile-Id";
    static final String ASSIGNMENT_ID_HEADER = "X-Assignment-Id";
    static final String ASSIGNMENT_VERSION_HEADER = "X-Assignment-Version";
    /** Identity headers only the gateway may set; every client copy is removed first. */
    static final List<String> TRUSTED_HEADERS = List.of(USER_ID_HEADER, USER_ROLE_HEADER, AUTH_TYPE_HEADER,
            DRIVER_TRIP_HEADER, DRIVER_PROFILE_HEADER, ASSIGNMENT_ID_HEADER, ASSIGNMENT_VERSION_HEADER);

    private final JwtTokenService jwtTokenService;

    public JwtGlobalFilter(JwtTokenService jwtTokenService) {
        this.jwtTokenService = jwtTokenService;
    }

    @Override
    public Mono<Void> filter(ServerWebExchange exchange, GatewayFilterChain chain) {
        ServerHttpRequest sanitizedRequest = exchange.getRequest().mutate()
                .headers(headers -> TRUSTED_HEADERS.forEach(headers::remove))
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
            if (user.isDriverSession() && !DriverSessionAllowlist.allows(sanitizedRequest.getMethod(),
                    sanitizedRequest.getPath().value(), user.tripId())) {
                return forbidden(exchange);
            }

            ServerHttpRequest authenticatedRequest = sanitizedRequest.mutate()
                    .headers(headers -> {
                        headers.set(USER_ID_HEADER, user.accountId());
                        headers.set(USER_ROLE_HEADER, user.role());
                        headers.set(AUTH_TYPE_HEADER, user.authType());
                        if (user.isDriverSession()) {
                            headers.set(DRIVER_TRIP_HEADER, user.tripId());
                            headers.set(DRIVER_PROFILE_HEADER, user.driverProfileId());
                            headers.set(ASSIGNMENT_ID_HEADER, user.assignmentId());
                            headers.set(ASSIGNMENT_VERSION_HEADER, String.valueOf(user.assignmentVersion()));
                        }
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

        // Các đường dẫn cho phép bypass Gateway JWT check
        if (request.getMethod() == HttpMethod.OPTIONS) return true;
        if (path.startsWith("/api/v1/auth/")) {
            // Driver redeem/refresh authenticate with the code or refresh secret inside identity.
            return !(path.equals("/api/v1/auth/me") || path.equals("/api/v1/auth/logout")
                    || path.equals("/api/v1/auth/driver/logout"));
        }
        if (path.startsWith("/swagger-ui") || path.startsWith("/v3/api-docs")) return true;
        if (path.equals("/actuator/health") || path.equals("/actuator/info")) return true;
        // SePay authenticates this server-to-server callback with X-Secret-Key.
        if (path.equals("/api/v1/payments/sepay/ipn")) return true;

        // Các API của backend CẦN bảo vệ
        boolean isBackendSecuredApi = path.startsWith("/api/v1/")
                || path.startsWith("/bidding-socket/")
                || path.startsWith("/notification-socket/");

        // Nếu KHÔNG phải backend API (ví dụ: Next.js /api/auth/*, /, /login, /_next/*) thì coi như public để forward cho web-portal xử lý
        return !isBackendSecuredApi;
    }

    /**
     * An explicit bearer token wins over the cookie, so a web owner's cookie on the same origin can never
     * silently replace the principal an app request was made with.
     */
    private Optional<String> resolveAccessToken(ServerHttpRequest request) {
        String authorization = request.getHeaders().getFirst(HttpHeaders.AUTHORIZATION);
        if (StringUtils.hasText(authorization) && authorization.startsWith("Bearer ")) {
            String token = authorization.substring(7);
            if (StringUtils.hasText(token)) {
                return Optional.of(token);
            }
        }

        HttpCookie cookie = request.getCookies().getFirst(ACCESS_TOKEN_COOKIE);
        if (cookie != null && StringUtils.hasText(cookie.getValue())) {
            return Optional.of(cookie.getValue());
        }

        return Optional.empty();
    }

    private Mono<Void> unauthorized(ServerWebExchange exchange) {
        exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
        return exchange.getResponse().setComplete();
    }

    private Mono<Void> forbidden(ServerWebExchange exchange) {
        exchange.getResponse().setStatusCode(HttpStatus.FORBIDDEN);
        return exchange.getResponse().setComplete();
    }
}
