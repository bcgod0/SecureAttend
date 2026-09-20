package com.secureattend.scan

import com.secureattend.common.entity.DeviceRegistration
import com.secureattend.common.entity.FaceEmbedding
import com.secureattend.common.entity.ScanStatus
import com.secureattend.common.entity.Session
import com.secureattend.common.entity.SessionStatus
import com.secureattend.common.repository.DeviceRegistrationRepository
import com.secureattend.common.repository.FaceEmbeddingRepository
import com.secureattend.config.SecureAttendProperties
import com.secureattend.session.QrTokenService
import io.mockk.every
import io.mockk.mockk
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.http.HttpStatus
import org.springframework.web.reactive.function.client.ClientResponse
import org.springframework.web.reactive.function.client.WebClient
import reactor.core.publisher.Mono
import java.nio.ByteBuffer
import java.util.UUID

class FusionPipelineTest {

    private val qrTokenService = mockk<QrTokenService>()
    private val deviceRegistrationRepository = mockk<DeviceRegistrationRepository>()
    private val faceEmbeddingRepository = mockk<FaceEmbeddingRepository>()
    private val props = SecureAttendProperties()

    private val studentId = UUID.randomUUID()
    private val sessionId = UUID.randomUUID()
    private val courseId = UUID.randomUUID()
    private val facultyId = UUID.randomUUID()
    private val validFingerprint = "test-device-fingerprint-sha256-hash-value"

    // Classroom geofence: Delhi / Noida coordinates
    private val centerLat = 28.5355
    private val centerLon = 77.3910
    private val radiusMeters = 100

    private lateinit var activeSession: Session

    @BeforeEach
    fun setUp() {
        activeSession = Session(
            id = sessionId,
            courseId = courseId,
            facultyId = facultyId,
            geofenceLat = centerLat,
            geofenceLon = centerLon,
            geofenceRadiusMeters = radiusMeters,
            qrRotationSeconds = 15,
            status = SessionStatus.ACTIVE
        )

        // Mock device registration
        every { deviceRegistrationRepository.findByStudentIdAndIsActiveTrue(studentId) } returns DeviceRegistration(
            studentId = studentId,
            fingerprintHash = validFingerprint,
            isActive = true
        )

        // Mock face embedding (float array of 512 dimensions packed into byte array)
        val dummyEmbedding = ByteArray(512 * 4) { 0 }
        every { faceEmbeddingRepository.findByStudentId(studentId) } returns FaceEmbedding(
            studentId = studentId,
            embedding = dummyEmbedding
        )
    }

    private fun createWebClient(
        faceMatch: Boolean = true,
        similarity: Double = 0.88,
        liveness: Boolean = true,
        anomalyScore: Double = 0.1,
        shouldFail: Boolean = false
    ): WebClient {
        return WebClient.builder()
            .exchangeFunction { request ->
                if (shouldFail) {
                    return@exchangeFunction Mono.error(RuntimeException("ML Service Connection Refused"))
                }
                val path = request.url().path
                when {
                    path.endsWith("/api/face/verify") -> {
                        val body = """{
                            "match": $faceMatch,
                            "similarity": $similarity,
                            "liveness_passed": $liveness,
                            "liveness_detail": "${if (liveness) "passed" else "failed"}"
                        }""".trimIndent()
                        Mono.just(
                            ClientResponse.create(HttpStatus.OK)
                                .header("Content-Type", "application/json")
                                .body(body)
                                .build()
                        )
                    }
                    path.endsWith("/api/anomaly/score") -> {
                        val body = """{
                            "anomaly_score": $anomalyScore,
                            "is_anomalous": ${anomalyScore > props.anomaly.flagThreshold},
                            "reason": "${if (anomalyScore > props.anomaly.flagThreshold) "Suspicious time pattern" else "normal"}"
                        }""".trimIndent()
                        Mono.just(
                            ClientResponse.create(HttpStatus.OK)
                                .header("Content-Type", "application/json")
                                .body(body)
                                .build()
                        )
                    }
                    else -> Mono.just(ClientResponse.create(HttpStatus.NOT_FOUND).build())
                }
            }
            .build()
    }

    @Test
    fun `all 4 layers pass with low anomaly score results in PRESENT status`() {
        every { qrTokenService.validateToken("valid-token", studentId) } returns sessionId

        val webClient = createWebClient(faceMatch = true, similarity = 0.90, liveness = true, anomalyScore = 0.05)
        val pipeline = FusionPipeline(qrTokenService, deviceRegistrationRepository, faceEmbeddingRepository, webClient, props)

        val input = ScanInput(
            studentId = studentId,
            qrToken = "valid-token",
            deviceFingerprint = validFingerprint,
            latitude = centerLat,
            longitude = centerLon,
            faceFrameBytes = byteArrayOf(1, 2, 3)
        )

        val result = pipeline.execute(input, sessionId, activeSession)

        assertEquals(ScanStatus.PRESENT, result.finalStatus)
        assertEquals(5, result.layerResults.size)
        assertTrue(result.layerResults.all { it.passed })
        assertNull(result.flaggedReason)
    }

    @Test
    fun `invalid or expired QR token immediately REJECTS scan`() {
        every { qrTokenService.validateToken("expired-token", studentId) } returns null

        val webClient = createWebClient()
        val pipeline = FusionPipeline(qrTokenService, deviceRegistrationRepository, faceEmbeddingRepository, webClient, props)

        val input = ScanInput(
            studentId = studentId,
            qrToken = "expired-token",
            deviceFingerprint = validFingerprint,
            latitude = centerLat,
            longitude = centerLon,
            faceFrameBytes = byteArrayOf(1, 2, 3)
        )

        val result = pipeline.execute(input, sessionId, activeSession)

        assertEquals(ScanStatus.REJECTED, result.finalStatus)
        assertEquals(1, result.layerResults.size, "Subsequent layers should be aborted after QR failure")
        assertEquals(LayerResult.LAYER_QR_VALIDATION, result.layerResults.first().layerName)
        assertFalse(result.layerResults.first().passed)
    }

    @Test
    fun `device fingerprint mismatch REJECTS scan`() {
        every { qrTokenService.validateToken("valid-token", studentId) } returns sessionId

        val webClient = createWebClient()
        val pipeline = FusionPipeline(qrTokenService, deviceRegistrationRepository, faceEmbeddingRepository, webClient, props)

        val input = ScanInput(
            studentId = studentId,
            qrToken = "valid-token",
            deviceFingerprint = "unregistered-proxy-phone-fingerprint",
            latitude = centerLat,
            longitude = centerLon,
            faceFrameBytes = byteArrayOf(1, 2, 3)
        )

        val result = pipeline.execute(input, sessionId, activeSession)

        assertEquals(ScanStatus.REJECTED, result.finalStatus)
        assertEquals(2, result.layerResults.size)
        assertTrue(result.layerResults[0].passed) // QR passed
        assertFalse(result.layerResults[1].passed) // Device failed
    }

    @Test
    fun `location outside geofence radius REJECTS scan`() {
        every { qrTokenService.validateToken("valid-token", studentId) } returns sessionId

        val webClient = createWebClient()
        val pipeline = FusionPipeline(qrTokenService, deviceRegistrationRepository, faceEmbeddingRepository, webClient, props)

        // Lat/Lon 0.1 degree away is approximately 11 kilometers away (outside 100m radius)
        val outsideLat = centerLat + 0.1
        val outsideLon = centerLon + 0.1

        val input = ScanInput(
            studentId = studentId,
            qrToken = "valid-token",
            deviceFingerprint = validFingerprint,
            latitude = outsideLat,
            longitude = outsideLon,
            faceFrameBytes = byteArrayOf(1, 2, 3)
        )

        val result = pipeline.execute(input, sessionId, activeSession)

        assertEquals(ScanStatus.REJECTED, result.finalStatus)
        assertEquals(3, result.layerResults.size)
        assertTrue(result.layerResults[0].passed) // QR passed
        assertTrue(result.layerResults[1].passed) // Device passed
        assertFalse(result.layerResults[2].passed) // Geofence failed
    }

    @Test
    fun `face verification mismatch results in FLAGGED status per NFR-7`() {
        every { qrTokenService.validateToken("valid-token", studentId) } returns sessionId

        // Face similarity 0.35 is below default 0.55 threshold
        val webClient = createWebClient(faceMatch = false, similarity = 0.35, liveness = true)
        val pipeline = FusionPipeline(qrTokenService, deviceRegistrationRepository, faceEmbeddingRepository, webClient, props)

        val input = ScanInput(
            studentId = studentId,
            qrToken = "valid-token",
            deviceFingerprint = validFingerprint,
            latitude = centerLat,
            longitude = centerLon,
            faceFrameBytes = byteArrayOf(1, 2, 3)
        )

        val result = pipeline.execute(input, sessionId, activeSession)

        assertEquals(ScanStatus.FLAGGED, result.finalStatus)
        assertNotNull(result.flaggedReason)
        assertTrue(result.layerResults.any { it.layerName == LayerResult.LAYER_FACE_VERIFICATION && !it.passed })
    }

    @Test
    fun `high anomaly score results in FLAGGED status`() {
        every { qrTokenService.validateToken("valid-token", studentId) } returns sessionId

        // Anomaly score 0.95 is above 0.70 threshold
        val webClient = createWebClient(faceMatch = true, similarity = 0.88, liveness = true, anomalyScore = 0.95)
        val pipeline = FusionPipeline(qrTokenService, deviceRegistrationRepository, faceEmbeddingRepository, webClient, props)

        val input = ScanInput(
            studentId = studentId,
            qrToken = "valid-token",
            deviceFingerprint = validFingerprint,
            latitude = centerLat,
            longitude = centerLon,
            faceFrameBytes = byteArrayOf(1, 2, 3)
        )

        val result = pipeline.execute(input, sessionId, activeSession)

        assertEquals(ScanStatus.FLAGGED, result.finalStatus)
        assertTrue(result.layerResults.any { it.layerName == LayerResult.LAYER_ANOMALY && !it.passed })
    }

    @Test
    fun `ML service outage gracefully degrades to FLAGGED without crashing`() {
        every { qrTokenService.validateToken("valid-token", studentId) } returns sessionId

        val webClient = createWebClient(shouldFail = true)
        val pipeline = FusionPipeline(qrTokenService, deviceRegistrationRepository, faceEmbeddingRepository, webClient, props)

        val input = ScanInput(
            studentId = studentId,
            qrToken = "valid-token",
            deviceFingerprint = validFingerprint,
            latitude = centerLat,
            longitude = centerLon,
            faceFrameBytes = byteArrayOf(1, 2, 3)
        )

        val result = pipeline.execute(input, sessionId, activeSession)

        // NFR-7: Degradation to FLAGGED
        assertEquals(ScanStatus.FLAGGED, result.finalStatus)
        assertTrue(result.layerResults.any { it.layerName == LayerResult.LAYER_FACE_VERIFICATION && !it.passed })
    }
}
