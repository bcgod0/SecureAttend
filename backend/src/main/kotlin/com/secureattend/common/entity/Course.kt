package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "courses")
data class Course(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(nullable = false, unique = true, length = 50)
    val code: String,

    @Column(nullable = false)
    val name: String,

    @Column(nullable = true)
    var branch: String? = null,

    @Column(name = "course_year", nullable = true)
    var year: Int? = null,

    @Column(nullable = true)
    var semester: Int? = null,

    @Column(name = "faculty_id", nullable = true)
    var facultyId: UUID? = null,

    @Column(name = "academic_session", nullable = true)
    var academicSession: String? = null,

    @Column(name = "course_type", nullable = true)
    var courseType: String? = null,

    @Column(nullable = true)
    var credits: Int? = null,

    @Column(name = "is_active", nullable = false, columnDefinition = "BOOLEAN DEFAULT TRUE")
    var isActive: Boolean = true,

    @Column(name = "created_by", nullable = false)
    val createdBy: UUID,

    @Column(name = "created_at", nullable = false)
    val createdAt: Instant = Instant.now(),

    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant = Instant.now()
)
