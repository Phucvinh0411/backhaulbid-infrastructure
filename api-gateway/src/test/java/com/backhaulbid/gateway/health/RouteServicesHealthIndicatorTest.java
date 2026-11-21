package com.backhaulbid.gateway.health;

import org.junit.jupiter.api.Test;
import org.springframework.boot.actuate.health.Status;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.cloud.client.DefaultServiceInstance;
import org.springframework.cloud.client.discovery.DiscoveryClient;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class RouteServicesHealthIndicatorTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withUserConfiguration(RouteServicesHealthIndicator.class)
            .withBean(DiscoveryClient.class, () -> mock(DiscoveryClient.class));

    @Test
    void registersHealthIndicatorByDefaultAndWhenEurekaEnabled() {
        contextRunner.run(context ->
                assertThat(context).hasSingleBean(RouteServicesHealthIndicator.class));

        contextRunner
                .withPropertyValues("eureka.client.enabled=true")
                .run(context -> assertThat(context).hasSingleBean(RouteServicesHealthIndicator.class));
    }

    @Test
    void disablesEurekaDiscoveryHealthCheckWhenEurekaIsDisabledForKubernetesDns() {
        contextRunner
                .withPropertyValues("eureka.client.enabled=false")
                .run(context -> assertThat(context).doesNotHaveBean(RouteServicesHealthIndicator.class));
    }

    @Test
    void reportsDownWhenRequiredServiceMissingAndUpWhenAllRegistered() {
        DiscoveryClient discoveryClient = mock(DiscoveryClient.class);
        RouteServicesHealthIndicator indicator = new RouteServicesHealthIndicator(discoveryClient);

        when(discoveryClient.getInstances("identity-service")).thenReturn(List.of());
        assertThat(indicator.health().getStatus()).isEqualTo(Status.DOWN);

        for (String svc : List.of("identity-service", "fleet-service", "wallet-service", "contract-service")) {
            when(discoveryClient.getInstances(svc))
                    .thenReturn(List.of(new DefaultServiceInstance(svc + "-1", svc, svc, 8080, false)));
        }
        assertThat(indicator.health().getStatus()).isEqualTo(Status.UP);
    }
}
