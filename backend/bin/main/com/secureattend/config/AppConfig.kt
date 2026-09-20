package com.secureattend.config

import org.springframework.boot.context.properties.EnableConfigurationProperties
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.web.reactive.function.client.WebClient

@Configuration
@EnableConfigurationProperties(SecureAttendProperties::class)
class AppConfig(
    private val properties: SecureAttendProperties
) {

    @Bean
    fun mlServiceWebClient(): WebClient {
        return WebClient.builder()
            .baseUrl(properties.mlService.baseUrl)
            .build()
    }
}
