package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "scans")
data class Scan(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(name = "session_id", nullable = false)
    val sessionId: UUID,

    @Column(name = "student_id", nullable = false)
    val studentId: UUID,

    @Enumerated(EnumType.STRING)
    @Column(name = "final_status", nullable = false)
    var finalStatus: ScanStatus,

    @Column(name = "submitted_at", nullable = false)
    val submittedAt: Instant = Instant.now(),

    @Column(name = "device_fingerprint", length = 64)
    val deviceFingerprint: String? = null,

    @Column(name = "location_lat")
    val locationLat: Double? = null,

    @Column(name = "location_lon")
    val locationLon: Double? = null
)

enum class ScanStatus {
    PRESENT, FLAGGED, REJECTED
}
