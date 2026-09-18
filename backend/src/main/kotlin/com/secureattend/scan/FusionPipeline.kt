package com.secureattend.scan

import com.secureattend.common.repository.DeviceRegistrationRepository
import com.secureattend.common.repository.FaceEmbeddingRepository
import com.secureattend.config.SecureAttendProperties
import com.secureattend.session.QrTokenService
import org.slf4j.LoggerFactory
import org.springframework.http.MediaType
import org.springframework.stereotype.Service
import org.springframework.web.reactive.function.BodyInserters
import org.springframework.web.reactive.function.client.WebClient
import java.nio.ByteBuffer
import java.time.Duration
import java.util.UUID
import kotlin.math.*

/**
 * FR-12: Fusion pipeline — deterministic four-layer verification + anomaly scoring.
 *
 * Pipeline order (per FR-8 through FR-11):
 * 1. QR Validation (signature + expiry + replay)
 * 2. Device Match (fingerprint hash comparison)
 * 3. Geofence (Haversine distance ≤ radius)
 * 4. Face Verification (cosine similarity via ML service + liveness)
 * 5. Anomaly Scoring (Isolation Forest via ML service)
 *
 * Each layer's pass/fail/score is independently logged (FR-13, NFR-6).
 */
@Service
class FusionPipeline(
    private val qrTokenService: QrTokenService,
    private val deviceRegistrationRepository: DeviceRegistrationRepository,
    private val faceEmbeddingRepository: FaceEmbeddingRepository,
    private val mlServiceWebClient: WebClient,
    private val props: SecureAttendProperties
) {
    private val log = LoggerFactory.getLogger(javaClass)

    companion object {
        private const val EARTH_RADIUS_METERS = 6_371_000.0 // Mean Earth radius
    }

    /**
     * Execute the full pipeline. Returns a FusionResult with the final status
     * and all per-layer results regardless of where the pipeline stopped.
     */
    fun execute(input: ScanInput, sessionId: UUID, session: com.secureattend.common.entity.Session): FusionResult {
        val layerResults = mutableListOf<LayerResult>()
        var flaggedReason: String? = null

        // --- Layer 1: QR Validation (FR-8) ---
        val qrResult = validateQr(input.qrToken, input.studentId)
        layerResults.add(qrResult)
        if (!qrResult.passed) {
            log.info("[SCAN] [LAYER:QR_VALIDATION] result=FAIL detail={} student={}", qrResult.detail, input.studentId)
            return FusionResult(
                finalStatus = com.secureattend.common.entity.ScanStatus.REJECTED,
                layerResults = layerResults,
                flaggedReason = null
            )
        }
        log.info("[SCAN] [LAYER:QR_VALIDATION] result=PASS detail={} student={}", qrResult.detail, input.studentId)

        // --- Layer 2: Device Match (FR-9) ---
        val deviceResult = validateDevice(input.deviceFingerprint, input.studentId)
        layerResults.add(deviceResult)
        if (!deviceResult.passed) {
            log.info("[SCAN] [LAYER:DEVICE_MATCH] result=FAIL detail={} student={}", deviceResult.detail, input.studentId)
            return FusionResult(
                finalStatus = com.secureattend.common.entity.ScanStatus.REJECTED,
                layerResults = layerResults
            )
        }
        log.info("[SCAN] [LAYER:DEVICE_MATCH] result=PASS detail={} student={}", deviceResult.detail, input.studentId)

        // --- Layer 3: Geofence (FR-10) ---
        val geoResult = validateGeofence(
            input.latitude, input.longitude,
            session.geofenceLat, session.geofenceLon,
            session.geofenceRadiusMeters
        )
        layerResults.add(geoResult)
        if (!geoResult.passed) {
            log.info("[SCAN] [LAYER:GEOFENCE] result=FAIL detail={} student={}", geoResult.detail, input.studentId)
            return FusionResult(
                finalStatus = com.secureattend.common.entity.ScanStatus.REJECTED,
                layerResults = layerResults
            )
        }
        log.info("[SCAN] [LAYER:GEOFENCE] result=PASS detail={} student={}", geoResult.detail, input.studentId)

        // --- Layer 4: Face Verification (FR-11) ---
        val faceResult = validateFace(input.faceFrameBytes, input.studentId)
        layerResults.add(faceResult)
        if (!faceResult.passed) {
            flaggedReason = faceResult.detail
            log.info("[SCAN] [LAYER:FACE_VERIFICATION] result=FAIL detail={} student={}", faceResult.detail, input.studentId)
            // Face failure → FLAGGED (not REJECTED), per NFR-7
        } else {
            log.info("[SCAN] [LAYER:FACE_VERIFICATION] result=PASS detail={} student={}", faceResult.detail, input.studentId)
        }

        // --- Layer 5: Anomaly Scoring ---
        val anomalyResult = scoreAnomaly(input.studentId, input.latitude, input.longitude, faceResult.score)
        layerResults.add(anomalyResult)
        if (!anomalyResult.passed && flaggedReason == null) {
            flaggedReason = anomalyResult.detail
        }
        log.info("[SCAN] [LAYER:ANOMALY] result={} score={} detail={} student={}",
            if (anomalyResult.passed) "PASS" else "FAIL", anomalyResult.score, anomalyResult.detail, input.studentId)

        // --- Fusion Decision (FR-12) ---
        val finalStatus = when {
            !faceResult.passed -> com.secureattend.common.entity.ScanStatus.FLAGGED
            !anomalyResult.passed -> com.secureattend.common.entity.ScanStatus.FLAGGED
            else -> com.secureattend.common.entity.ScanStatus.PRESENT
        }

        return FusionResult(
            finalStatus = finalStatus,
            layerResults = layerResults,
            flaggedReason = flaggedReason
        )
    }

    // ---- Layer Implementations ----

    /**
     * Layer 1: QR token validation — HMAC signature + expiry + replay check.
     */
    private fun validateQr(token: String, studentId: UUID): LayerResult {
        val sessionId = qrTokenService.validateToken(token, studentId)
        return if (sessionId != null) {
            LayerResult(
                layerName = LayerResult.LAYER_QR_VALIDATION,
                passed = true,
                detail = "Token valid, session $sessionId"
            )
        } else {
            LayerResult(
                layerName = LayerResult.LAYER_QR_VALIDATION,
                passed = false,
                detail = "Invalid, expired, or replayed QR token"
            )
        }
    }

    /**
     * Layer 2: Device fingerprint match.
     */
    private fun validateDevice(fingerprint: String, studentId: UUID): LayerResult {
        val registration = deviceRegistrationRepository.findByStudentIdAndIsActiveTrue(studentId)
            ?: return LayerResult(
                layerName = LayerResult.LAYER_DEVICE_MATCH,
                passed = false,
                detail = "No active device registered for student"
            )

        val matched = registration.fingerprintHash == fingerprint
        return LayerResult(
            layerName = LayerResult.LAYER_DEVICE_MATCH,
            passed = matched,
            detail = if (matched) "Device matched" else "Device fingerprint mismatch"
        )
    }

    /**
     * Layer 3: Geofence check using Haversine formula.
     */
    private fun validateGeofence(
        scanLat: Double, scanLon: Double,
        centerLat: Double, centerLon: Double,
        radiusMeters: Int
    ): LayerResult {
        val distance = haversineDistance(centerLat, centerLon, scanLat, scanLon)
        val passed = distance <= radiusMeters

        return LayerResult(
            layerName = LayerResult.LAYER_GEOFENCE,
            passed = passed,
            score = distance,
            detail = if (passed) {
                "Within ${distance.roundTo(1)}m of center (limit: ${radiusMeters}m)"
            } else {
                "Outside geofence: ${distance.roundTo(1)}m from center (limit: ${radiusMeters}m)"
            }
        )
    }

    /**
     * Layer 4: Face verification via ML microservice.
     * NFR-7: If ML service is unavailable, degrade to FLAGGED.
     */
    private fun validateFace(faceFrameBytes: ByteArray, studentId: UUID): LayerResult {
        // Get stored embedding
        val storedEmbedding = faceEmbeddingRepository.findByStudentId(studentId)
            ?: return LayerResult(
                layerName = LayerResult.LAYER_FACE_VERIFICATION,
                passed = false,
                detail = "No face embedding enrolled for student"
            )

        // Convert stored embedding bytes to float list
        val embeddingFloats = bytesToFloats(storedEmbedding.embedding)

        return try {
            data class FaceVerifyResponse(
                val match: Boolean,
                val similarity: Double,
                val liveness_passed: Boolean,
                val liveness_detail: String
            )

            val response = mlServiceWebClient.post()
                .uri("/api/face/verify")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(mapOf(
                    "face_frame_base64" to java.util.Base64.getEncoder().encodeToString(faceFrameBytes),
                    "stored_embedding" to embeddingFloats,
                    "similarity_threshold" to props.face.similarityThreshold
                ))
                .retrieve()
                .bodyToMono(FaceVerifyResponse::class.java)
                .timeout(Duration.ofSeconds(props.mlService.timeoutSeconds))
                .block()

            if (response == null) {
                return LayerResult(
                    layerName = LayerResult.LAYER_FACE_VERIFICATION,
                    passed = false,
                    detail = "ML service returned empty response — flagged for manual review"
                )
            }

            val passed = response.match && response.liveness_passed
            LayerResult(
                layerName = LayerResult.LAYER_FACE_VERIFICATION,
                passed = passed,
                score = response.similarity,
                detail = when {
                    !response.liveness_passed -> "Liveness check failed: ${response.liveness_detail}"
                    !response.match -> "Face similarity ${response.similarity} < threshold ${props.face.similarityThreshold}"
                    else -> "Match confirmed (${response.similarity} ≥ ${props.face.similarityThreshold})"
                }
            )
        } catch (ex: Exception) {
            // NFR-7: ML service unavailable → FLAGGED, never silently pass or block
            log.warn("ML service unavailable for face verification: {}", ex.message)
            LayerResult(
                layerName = LayerResult.LAYER_FACE_VERIFICATION,
                passed = false,
                detail = "ML service unavailable — flagged for manual review"
            )
        }
    }

    /**
     * Layer 5: Behavioral anomaly scoring via ML microservice.
     */
    private fun scoreAnomaly(
        studentId: UUID,
        latitude: Double,
        longitude: Double,
        faceSimilarity: Double?
    ): LayerResult {
        return try {
            data class AnomalyResponse(
                val anomaly_score: Double,
                val is_anomalous: Boolean,
                val reason: String
            )

            val now = java.time.LocalDateTime.now()
            val response = mlServiceWebClient.post()
                .uri("/api/anomaly/score")
                .contentType(MediaType.APPLICATION_JSON)
                .bodyValue(mapOf(
                    "student_id" to studentId.toString(),
                    "scan_features" to mapOf(
                        "time_of_day" to (now.hour + now.minute / 60.0),
                        "day_of_week" to (now.dayOfWeek.value - 1), // 0=Monday
                        "location_lat" to latitude,
                        "location_lon" to longitude,
                        "face_similarity" to (faceSimilarity ?: 0.0)
                    )
                ))
                .retrieve()
                .bodyToMono(AnomalyResponse::class.java)
                .timeout(Duration.ofSeconds(props.mlService.timeoutSeconds))
                .block()

            if (response == null) {
                return LayerResult(
                    layerName = LayerResult.LAYER_ANOMALY,
                    passed = true,
                    score = 0.0,
                    detail = "Anomaly scoring unavailable — defaulting to normal"
                )
            }

            val passed = response.anomaly_score <= props.anomaly.flagThreshold
            LayerResult(
                layerName = LayerResult.LAYER_ANOMALY,
                passed = passed,
                score = response.anomaly_score,
                detail = if (passed) "Normal behavior pattern" else "Anomaly detected: ${response.reason}"
            )
        } catch (ex: Exception) {
            log.warn("Anomaly scoring unavailable: {}", ex.message)
            // If anomaly service is down, default to passing (don't block attendance)
            LayerResult(
                layerName = LayerResult.LAYER_ANOMALY,
                passed = true,
                score = 0.0,
                detail = "Anomaly scoring unavailable — defaulting to normal"
            )
        }
    }

    // ---- Utility Functions ----

    /**
     * Haversine formula to compute great-circle distance between two GPS points.
     * Returns distance in meters.
     */
    private fun haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ): Double {
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)

        val a = sin(dLat / 2).pow(2) +
                cos(Math.toRadians(lat1)) * cos(Math.toRadians(lat2)) *
                sin(dLon / 2).pow(2)

        val c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return EARTH_RADIUS_METERS * c
    }

    /**
     * Convert a byte array (big-endian float32s) to a list of doubles.
     */
    private fun bytesToFloats(bytes: ByteArray): List<Double> {
        val buffer = ByteBuffer.wrap(bytes)
        val floats = mutableListOf<Double>()
        while (buffer.hasRemaining()) {
            floats.add(buffer.float.toDouble())
        }
        return floats
    }

    private fun Double.roundTo(decimals: Int): Double {
        val factor = 10.0.pow(decimals)
        return (this * factor).roundToLong() / factor
    }

    private fun Double.roundToLong(): Long = kotlin.math.round(this).toLong()
}
