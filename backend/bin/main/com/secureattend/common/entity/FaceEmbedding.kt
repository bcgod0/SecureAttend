package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "face_embeddings")
data class FaceEmbedding(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(name = "student_id", nullable = false, unique = true)
    val studentId: UUID,

    @Lob
    @Column(nullable = false, columnDefinition = "bytea")
    val embedding: ByteArray,

    @Column(name = "created_at", nullable = false)
    val createdAt: Instant = Instant.now()
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is FaceEmbedding) return false
        return id == other.id && studentId == other.studentId
    }

    override fun hashCode(): Int = id?.hashCode() ?: 0
}
