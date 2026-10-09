package com.backhaulbid.gateway.security;

/**
 * Principal from a verified JWT. Account tokens carry only subject and role. Driver-session tokens
 * (authType DRIVER_ASSIGNMENT) also carry the single trip, fleet profile and assignment they are scoped to.
 */
public record AuthenticatedUser(String accountId, String role, String authType, String tripId, String driverProfileId,
                                String assignmentId, Long assignmentVersion) {
    public static final String ACCOUNT = "ACCOUNT";
    public static final String DRIVER_ASSIGNMENT = "DRIVER_ASSIGNMENT";

    public AuthenticatedUser(String accountId, String role) {
        this(accountId, role, ACCOUNT, null, null, null, null);
    }

    public boolean isDriverSession() {
        return DRIVER_ASSIGNMENT.equals(authType);
    }
}
