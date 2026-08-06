package com.backhaulbid.gateway.security;

public record AuthenticatedUser(String accountId, String role) {
}
