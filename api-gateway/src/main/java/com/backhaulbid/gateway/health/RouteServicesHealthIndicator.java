package com.backhaulbid.gateway.health;

import org.springframework.boot.actuate.health.Health;
import org.springframework.boot.actuate.health.HealthIndicator;
import org.springframework.cloud.client.discovery.DiscoveryClient;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
public class RouteServicesHealthIndicator implements HealthIndicator {

    private static final List<String> REQUIRED_SERVICES = List.of(
            "identity-service",
            "fleet-service",
            "wallet-service",
            "contract-service"
    );

    private final DiscoveryClient discoveryClient;

    public RouteServicesHealthIndicator(DiscoveryClient discoveryClient) {
        this.discoveryClient = discoveryClient;
    }

    @Override
    public Health health() {
        List<String> missingServices = REQUIRED_SERVICES.stream()
                .filter(service -> discoveryClient.getInstances(service).isEmpty())
                .toList();

        if (!missingServices.isEmpty()) {
            return Health.down()
                    .withDetail("missingServices", missingServices)
                    .build();
        }

        return Health.up().build();
    }
}
