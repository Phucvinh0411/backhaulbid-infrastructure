package com.backhaulbid.gateway.security;

import io.jsonwebtoken.Claims;
import io.jsonwebtoken.JwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.security.Key;
import java.util.Collection;
import java.util.UUID;

@Component
public class JwtTokenService {
    static final String DRIVER_ISSUER = "backhaulbid-identity";
    static final String DRIVER_AUDIENCE = "backhaulbid-driver";

    private final Key signingKey;

    public JwtTokenService(@Value("${app.jwt.secret}") String jwtSecret) {
        this.signingKey = Keys.hmacShaKeyFor(Decoders.BASE64.decode(jwtSecret));
    }

    public AuthenticatedUser parseAccessToken(String token) {
        Claims claims = Jwts.parserBuilder()
                .setSigningKey(signingKey)
                .build()
                .parseClaimsJws(token)
                .getBody();
        String authType = claims.get("auth_type", String.class);
        if (authType == null || AuthenticatedUser.ACCOUNT.equals(authType)) {
            return new AuthenticatedUser(claims.getSubject(), claims.get("role", String.class));
        }
        if (!AuthenticatedUser.DRIVER_ASSIGNMENT.equals(authType)) throw new JwtException("Unsupported auth type");
        // A driver-session token is only valid with its issuer, audience, DRIVER role and the full scope.
        if (!DRIVER_ISSUER.equals(claims.getIssuer()) || !audienceContains(claims.get("aud"), DRIVER_AUDIENCE)
                || !"DRIVER".equals(claims.get("role", String.class))) {
            throw new JwtException("Driver session token has an invalid issuer, audience or role");
        }
        String trip = uuid(claims.get("trip_id", String.class));
        String profile = uuid(claims.get("driver_profile_id", String.class));
        String assignment = uuid(claims.get("assignment_id", String.class));
        Object version = claims.get("assignment_version");
        if (!(version instanceof Number number) || number.longValue() < 0) throw new JwtException("Driver session token has no assignment version");
        return new AuthenticatedUser(uuid(claims.getSubject()), "DRIVER", authType, trip, profile, assignment, number.longValue());
    }

    private static boolean audienceContains(Object audience, String expected) {
        if (audience instanceof String value) return expected.equals(value);
        if (audience instanceof Collection<?> values) return values.contains(expected);
        return false;
    }

    private static String uuid(String value) {
        try {
            return UUID.fromString(value).toString();
        } catch (RuntimeException invalid) {
            throw new JwtException("Driver session token has an invalid scope identifier");
        }
    }
}
