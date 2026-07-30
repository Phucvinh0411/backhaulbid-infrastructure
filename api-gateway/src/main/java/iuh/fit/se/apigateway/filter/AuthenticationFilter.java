package iuh.fit.se.apigateway.filter;

import iuh.fit.se.apigateway.util.JwtUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.cloud.gateway.filter.GatewayFilter;
import org.springframework.cloud.gateway.filter.factory.AbstractGatewayFilterFactory;
import org.springframework.http.HttpCookie;
import org.springframework.http.HttpStatus;
import org.springframework.http.server.reactive.ServerHttpRequest;
import org.springframework.stereotype.Component;

@Component
public class AuthenticationFilter extends AbstractGatewayFilterFactory<AuthenticationFilter.Config> {

    @Autowired
    private RouteValidator validator;

    @Autowired
    private JwtUtil jwtUtil;

    public AuthenticationFilter() {
        super(Config.class);
    }

    public static class Config {
    }

    @Override
    public GatewayFilter apply(Config config) {
        return ((exchange, chain) -> {
            ServerHttpRequest request = exchange.getRequest();

            if (validator.isSecured.test(request)) {
                // Lấy Token từ Cookie thay vì Header
                HttpCookie authCookie = request.getCookies().getFirst("accessToken");
                if (authCookie == null || authCookie.getValue().isEmpty()) {
                    exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
                    return exchange.getResponse().setComplete();
                }

                String token = authCookie.getValue();

                try {
                    jwtUtil.validateToken(token);

                    String userId = jwtUtil.getUserId(token);
                    String role = jwtUtil.getRole(token);

                    request = request.mutate()
                            .header("X-User-Id", userId)
                            .header("X-User-Role", role)
                            .build();

                } catch (Exception e) {
                    exchange.getResponse().setStatusCode(HttpStatus.UNAUTHORIZED);
                    return exchange.getResponse().setComplete();
                }
            }
            return chain.filter(exchange.mutate().request(request).build());
        });
    }
}
