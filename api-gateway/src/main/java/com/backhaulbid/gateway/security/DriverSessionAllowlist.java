package com.backhaulbid.gateway.security;

import org.springframework.http.HttpMethod;

import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * The only routes a driver-session token may use. {trip} must equal the token's trip; anything else
 * (wallet, fleet, bidding, contracts, notifications, account, eKYC, admin, sockets) is refused here, and
 * every downstream service checks the session again.
 */
final class DriverSessionAllowlist {
    private static final String UUID = "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}";
    private static final String TRIP = "/api/v1/trips/(?<trip>" + UUID + ")";
    private record Rule(HttpMethod method, Pattern path) {
    }

    private static final List<Rule> RULES = List.of(
            rule(HttpMethod.GET, "/api/v1/trips/mine"),
            rule(HttpMethod.GET, TRIP),
            rule(HttpMethod.GET, TRIP + "/tracking"),
            rule(HttpMethod.GET, TRIP + "/locations"),
            rule(HttpMethod.GET, TRIP + "/locations/latest"),
            rule(HttpMethod.GET, TRIP + "/locations/history"),
            rule(HttpMethod.POST, TRIP + "/locations"),
            rule(HttpMethod.POST, TRIP + "/locations/batch"),
            rule(HttpMethod.POST, TRIP + "/tracking-sessions"),
            rule(HttpMethod.POST, TRIP + "/tracking-sessions/" + UUID + "/stop"),
            rule(HttpMethod.GET, TRIP + "/journey-events"),
            rule(HttpMethod.POST, TRIP + "/journey-events"),
            rule(HttpMethod.GET, TRIP + "/delivery-proofs"),
            rule(HttpMethod.POST, TRIP + "/delivery-proofs"),
            rule(HttpMethod.GET, TRIP + "/milestones"),
            rule(HttpMethod.POST, TRIP + "/milestones/" + UUID + "/checkin"),
            rule(HttpMethod.GET, TRIP + "/handover"),
            rule(HttpMethod.PUT, TRIP + "/handover"),
            rule(HttpMethod.GET, TRIP + "/handover/photos/[0-9]{1,2}"),
            rule(HttpMethod.POST, "/api/v1/media/upload"),
            rule(HttpMethod.GET, "/api/v1/media/files/[a-z0-9-]{1,40}/[A-Za-z0-9._-]{1,120}"),
            rule(HttpMethod.POST, "/api/v1/auth/driver/logout"));

    private DriverSessionAllowlist() {
    }

    private static Rule rule(HttpMethod method, String path) {
        return new Rule(method, Pattern.compile(path));
    }

    /** {@code rawPath} is the undecoded request path, so encoded slashes or dots never match a rule. */
    static boolean allows(HttpMethod method, String rawPath, String tokenTrip) {
        if (rawPath == null || rawPath.contains("..") || rawPath.contains("//") || rawPath.contains("%")) return false;
        for (Rule rule : RULES) {
            if (rule.method() != method) continue;
            Matcher matcher = rule.path().matcher(rawPath);
            if (!matcher.matches()) continue;
            if (rule.path().pattern().contains("(?<trip>")) {
                return matcher.group("trip").toLowerCase(Locale.ROOT).equals(tokenTrip);
            }
            return true;
        }
        return false;
    }
}
