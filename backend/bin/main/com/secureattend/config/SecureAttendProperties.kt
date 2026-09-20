package com.secureattend.config

import org.springframework.boot.context.properties.ConfigurationProperties

@ConfigurationProperties(prefix = "secureattend")
data class SecureAttendProperties(
    val jwt: JwtProperties = JwtProperties(),
    val qr: QrProperties = QrProperties(),
    val mlService: MlServiceProperties = MlServiceProperties(),
    val geofence: GeofenceProperties = GeofenceProperties(),
    val face: FaceProperties = FaceProperties(),
    val anomaly: AnomalyProperties = AnomalyProperties(),
    val admin: AdminProperties = AdminProperties()
)

data class JwtProperties(
    val secret: String = "dev-jwt-secret-change-in-production-min-32-chars!!",
    val accessTokenExpiryMinutes: Long = 15,
    val refreshTokenExpiryDays: Long = 7
)

data class QrProperties(
    val hmacSecret: String = "dev-qr-hmac-secret-change-in-prod-min-32-chars!!",
    val defaultRotationSeconds: Int = 10
)

data class MlServiceProperties(
    val baseUrl: String = "http://localhost:8000",
    val timeoutSeconds: Long = 5
)

data class GeofenceProperties(
    val maxRadiusMeters: Int = 1000
)

data class FaceProperties(
    val similarityThreshold: Double = 0.55
)

data class AnomalyProperties(
    val flagThreshold: Double = 0.7
)

data class AdminProperties(
    val bootstrapEmail: String = "",
    val bootstrapPassword: String = ""
)
