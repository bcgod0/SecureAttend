package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "sessions")
data class Session(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(name = "course_id", nullable = false)
    val courseId: UUID,

    @Column(name = "faculty_id", nullable = false)
    val facultyId: UUID,

    @Column(name = "geofence_lat", nullable = false)
    val geofenceLat: Double,

    @Column(name = "geofence_lon", nullable = false)
    val geofenceLon: Double,

    @Column(name = "geofence_radius_meters", nullable = false)
    val geofenceRadiusMeters: Int = 100,

    @Column(name = "qr_rotation_seconds", nullable = false)
    val qrRotationSeconds: Int = 10,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    var status: SessionStatus = SessionStatus.ACTIVE,

    @Column(name = "started_at", nullable = false)
    val startedAt: Instant = Instant.now(),

    @Column(name = "closed_at")
    var closedAt: Instant? = null
)

enum class SessionStatus {
    ACTIVE, CLOSED
}
