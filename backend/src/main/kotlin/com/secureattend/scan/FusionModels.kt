package com.secureattend.scan

import com.secureattend.common.entity.ScanStatus
import java.util.UUID

/**
 * Represents the result of a single verification layer in the fusion pipeline.
 * Each layer produces one of these, which is independently logged (NFR-6, FR-13).
 */
data class LayerResult(
    val layerName: String,
    val passed: Boolean,
    val score: Double? = null,
    val detail: String
) {
    companion object {
        const val LAYER_QR_VALIDATION = "QR_VALIDATION"
        const val LAYER_DEVICE_MATCH = "DEVICE_MATCH"
        const val LAYER_GEOFENCE = "GEOFENCE"
        const val LAYER_FACE_VERIFICATION = "FACE_VERIFICATION"
        const val LAYER_ANOMALY = "ANOMALY"
    }
}

/**
 * Complete result of the fusion pipeline — final status + per-layer breakdown.
 */
data class FusionResult(
    val finalStatus: ScanStatus,
    val layerResults: List<LayerResult>,
    val flaggedReason: String? = null
)

/**
 * Input data for the fusion pipeline, collected from the scan request.
 */
data class ScanInput(
    val studentId: UUID,
    val qrToken: String,
    val deviceFingerprint: String,
    val latitude: Double,
    val longitude: Double,
    val faceFrameBytes: ByteArray
) {
    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is ScanInput) return false
        return studentId == other.studentId && qrToken == other.qrToken
    }
    override fun hashCode(): Int = studentId.hashCode()
}
