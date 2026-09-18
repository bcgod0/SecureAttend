package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "review_queue")
data class ReviewQueueEntry(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(name = "scan_id", nullable = false, unique = true)
    val scanId: UUID,

    @Column(name = "flagged_reason", nullable = false, columnDefinition = "text")
    val flaggedReason: String,

    @Column(name = "reviewed_by")
    var reviewedBy: UUID? = null,

    @Enumerated(EnumType.STRING)
    @Column(name = "review_decision")
    var reviewDecision: ReviewDecision? = null,

    @Column(name = "review_notes", columnDefinition = "text")
    var reviewNotes: String? = null,

    @Column(name = "flagged_at", nullable = false)
    val flaggedAt: Instant = Instant.now(),

    @Column(name = "reviewed_at")
    var reviewedAt: Instant? = null
)

enum class ReviewDecision {
    APPROVED, REJECTED
}
