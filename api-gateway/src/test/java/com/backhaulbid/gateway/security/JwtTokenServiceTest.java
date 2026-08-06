package com.backhaulbid.gateway.security;

import io.jsonwebtoken.ExpiredJwtException;
import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.io.Decoders;
import io.jsonwebtoken.security.Keys;
import org.junit.jupiter.api.Test;

import java.security.Key;
import java.time.Instant;
import java.util.Date;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class JwtTokenServiceTest {

    private static final String SIGNING_SECRET =
            "404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970";
    private static final String DIFFERENT_SECRET =
            "504E635266556A586E3272357538782F413F4428472B4B6250645367566B5971";

    @Test
    void parseAccessToken_validSignedToken_returnsAuthenticatedUser() {
        // Given
        JwtTokenService service = new JwtTokenService(SIGNING_SECRET);
        String token = createToken(
                SIGNING_SECRET,
                "8f14e45f-ea43-4a4f-b716-3f8f68f74201",
                "CARRIER",
                "2099-01-01T00:00:00Z");

        // When
        AuthenticatedUser actualUser = service.parseAccessToken(token);

        // Then
        assertThat(actualUser.accountId()).isEqualTo("8f14e45f-ea43-4a4f-b716-3f8f68f74201");
        assertThat(actualUser.role()).isEqualTo("CARRIER");
    }

    @Test
    void parseAccessToken_expiredToken_throwsExpiredJwtException() {
        // Given
        JwtTokenService service = new JwtTokenService(SIGNING_SECRET);
        String token = createToken(
                SIGNING_SECRET,
                "8f14e45f-ea43-4a4f-b716-3f8f68f74201",
                "SHIPPER",
                "2020-01-01T00:00:00Z");

        // When-Then
        assertThatThrownBy(() -> service.parseAccessToken(token))
                .isInstanceOf(ExpiredJwtException.class);
    }

    @Test
    void parseAccessToken_tokenSignedWithDifferentKey_throwsJwtException() {
        // Given
        JwtTokenService service = new JwtTokenService(SIGNING_SECRET);
        String token = createToken(
                DIFFERENT_SECRET,
                "8f14e45f-ea43-4a4f-b716-3f8f68f74201",
                "ADMIN",
                "2099-01-01T00:00:00Z");

        // When-Then
        assertThatThrownBy(() -> service.parseAccessToken(token))
                .isInstanceOf(io.jsonwebtoken.JwtException.class);
    }

    private String createToken(String secret, String subject, String role, String expiration) {
        Key signingKey = Keys.hmacShaKeyFor(Decoders.BASE64.decode(secret));
        return Jwts.builder()
                .setSubject(subject)
                .claim("role", role)
                .setIssuedAt(Date.from(Instant.parse("2026-01-01T00:00:00Z")))
                .setExpiration(Date.from(Instant.parse(expiration)))
                .signWith(signingKey, SignatureAlgorithm.HS256)
                .compact();
    }
}
