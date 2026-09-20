package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "device_registrations")
data class DeviceRegistration(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(name = "student_id", nullable = false)
    val studentId: UUID,

    @Column(name = "fingerprint_hash", nullable = false, length = 64)
    val fingerprintHash: String,

    @Column(name = "device_info", columnDefinition = "text")
    val deviceInfo: String? = null,

    @Column(name = "is_active", nullable = false)
    var isActive: Boolean = true,

    @Column(name = "registered_at", nullable = false)
    val registeredAt: Instant = Instant.now(),

    @Column(name = "deactivated_at")
    var deactivatedAt: Instant? = null
)
