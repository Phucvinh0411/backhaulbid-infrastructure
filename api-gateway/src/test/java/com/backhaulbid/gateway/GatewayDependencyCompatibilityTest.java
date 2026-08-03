package com.backhaulbid.gateway;

import org.junit.jupiter.api.Test;
import org.springframework.http.HttpHeaders;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;

class GatewayDependencyCompatibilityTest {

    @Test
    void springWebProvidesHeaderApiRequiredByGateway() {
        assertDoesNotThrow(() -> HttpHeaders.class.getMethod("headerSet"));
    }
}
