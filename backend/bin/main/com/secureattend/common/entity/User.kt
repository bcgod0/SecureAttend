package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

enum class UserStatus {
    PENDING, ACTIVE
}

@Entity
@Table(name = "users")
data class User(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(nullable = false, unique = true)
    val email: String,

    @Column(unique = true, nullable = true)
    var username: String? = null,

    @Column(name = "password_hash", nullable = false)
    var passwordHash: String,

    @Column(name = "full_name", nullable = false)
    val fullName: String,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    val role: UserRole,

    @Enumerated(EnumType.STRING)
    @Column(nullable = false, columnDefinition = "VARCHAR(20) DEFAULT 'ACTIVE'")
    var status: UserStatus = UserStatus.PENDING,

    @Column(nullable = true)
    var branch: String? = null,

    @Column(nullable = true)
    var section: String? = null,

    @Column(name = "roll_no", nullable = true)
    var rollNo: String? = null,

    @Column(name = "father_name", nullable = true)
    var fatherName: String? = null,

    @Column(name = "created_at", nullable = false)
    val createdAt: Instant = Instant.now(),

    @Column(name = "updated_at", nullable = false)
    var updatedAt: Instant = Instant.now()
)

enum class UserRole {
    STUDENT, FACULTY, ADMIN
}
