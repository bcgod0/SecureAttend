package com.secureattend.common.entity

import jakarta.persistence.*
import java.time.Instant
import java.util.UUID

@Entity
@Table(name = "scan_layer_results")
data class ScanLayerResult(
    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    val id: UUID? = null,

    @Column(name = "scan_id", nullable = false)
    val scanId: UUID,

    @Column(name = "layer_name", nullable = false, length = 50)
    val layerName: String,

    @Column(nullable = false)
    val passed: Boolean,

    val score: Double? = null,

    @Column(columnDefinition = "text")
    val detail: String? = null,

    @Column(name = "evaluated_at", nullable = false)
    val evaluatedAt: Instant = Instant.now()
)
