package com.secureattend.common.entity

import jakarta.persistence.*
import java.io.Serializable
import java.time.Instant
import java.util.UUID

@Embeddable
data class CourseEnrollmentId(
    @Column(name = "student_id")
    val studentId: UUID = UUID.randomUUID(),

    @Column(name = "course_id")
    val courseId: UUID = UUID.randomUUID()
) : Serializable

@Entity
@Table(name = "course_enrollments")
data class CourseEnrollment(
    @EmbeddedId
    val id: CourseEnrollmentId,

    @Column(name = "enrolled_at", nullable = false)
    val enrolledAt: Instant = Instant.now()
)
