package com.backhaulbid.gateway;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.reactive.AutoConfigureWebTestClient;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.web.reactive.server.WebTestClient;

import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(
        webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = {
                "SWAGGER_ENABLED=true",
                // Keep the integration test deterministic; Compose supplies JWT_SECRET in production.
                "JWT_SECRET=404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970",
                "eureka.client.enabled=false",
                "spring.cloud.discovery.enabled=false"
        })
@AutoConfigureWebTestClient
class SwaggerCatalogTest {

    @Autowired
    private WebTestClient webTestClient;

    @Test
    void swaggerConfig_listsEveryBusinessService() {
        webTestClient.get()
                .uri("/v3/api-docs/swagger-config")
                .exchange()
                .expectStatus().isOk()
                .expectBody()
                .jsonPath("$.urls.length()").isEqualTo(7)
                .consumeWith(response -> assertThat(new String(response.getResponseBody(), StandardCharsets.UTF_8))
                        .contains(
                                "\"name\":\"Identity Service\"",
                                "\"url\":\"/v3/api-docs/identity-service\"",
                                "\"name\":\"Fleet Service\"",
                                "\"url\":\"/v3/api-docs/fleet-service\"",
                                "\"name\":\"Wallet Service\"",
                                "\"url\":\"/v3/api-docs/wallet-service\"",
                                "\"name\":\"Contract Service\"",
                                "\"url\":\"/v3/api-docs/contract-service\"",
                                "\"name\":\"Media Service\"",
                                "\"url\":\"/v3/api-docs/media-service\"",
                                "\"name\":\"Notification Service\"",
                                "\"url\":\"/v3/api-docs/notification-service\"",
                                "\"name\":\"Bidding Service\"",
                                "\"url\":\"/v3/api-docs/bidding-service\""
                        ));
    }
}
