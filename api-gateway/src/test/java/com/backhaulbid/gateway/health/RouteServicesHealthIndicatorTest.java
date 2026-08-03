package com.backhaulbid.gateway.health;

import org.junit.jupiter.api.Test;
import org.springframework.boot.actuate.health.Status;
import org.springframework.cloud.client.ServiceInstance;
import org.springframework.cloud.client.discovery.DiscoveryClient;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class RouteServicesHealthIndicatorTest {

    private final DiscoveryClient discoveryClient = mock(DiscoveryClient.class);
    private final RouteServicesHealthIndicator indicator = new RouteServicesHealthIndicator(discoveryClient);

    @Test
    void health_isDownWhenARequiredRouteHasNoInstance() {
        when(discoveryClient.getInstances(anyString())).thenReturn(List.of(mock(ServiceInstance.class)));
        when(discoveryClient.getInstances("identity-service")).thenReturn(List.of());

        var health = indicator.health();

        assertThat(health.getStatus()).isEqualTo(Status.DOWN);
        assertThat(health.getDetails().get("missingServices")).isEqualTo(List.of("identity-service"));
    }

    @Test
    void health_isUpWhenEveryRequiredRouteHasAnInstance() {
        when(discoveryClient.getInstances(anyString())).thenReturn(List.of(mock(ServiceInstance.class)));

        assertThat(indicator.health().getStatus()).isEqualTo(Status.UP);
    }
}
