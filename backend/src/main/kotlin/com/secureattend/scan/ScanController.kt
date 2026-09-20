package com.secureattend.scan

import com.secureattend.common.entity.*
import com.secureattend.common.exception.*
import com.secureattend.common.repository.*
import org.slf4j.LoggerFactory
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.http.MediaType
import org.springframework.messaging.simp.SimpMessagingTemplate
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.web.bind.annotation.*
import org.springframework.web.multipart.MultipartFile
import java.time.Instant
import java.util.UUID

// ---- Response DTOs ----

data class LayerResultResponse(
    val layer: String,
    val passed: Boolean,
    val score: Double? = null,
    val detail: String
)

data class ScanResponse(
    val scanId: UUID,
    val sessionId: UUID,
    val finalStatus: ScanStatus,
    val layerResults: List<LayerResultResponse>,
    val submittedAt: Instant
)

data class AttendanceListItem(
    val scanId: UUID,
    val studentId: UUID,
    val studentName: String,
    val studentEmail: String,
    val finalStatus: ScanStatus,
    val submittedAt: Instant,
    val layerResults: List<LayerResultResponse>
)

// ---- Controller ----

@RestController
@RequestMapping("/api/scan")
class ScanController(
    private val fusionPipeline: FusionPipeline,
    private val sessionRepository: SessionRepository,
    private val scanRepository: ScanRepository,
    private val scanLayerResultRepository: ScanLayerResultRepository,
    private val reviewQueueRepository: ReviewQueueRepository,
    private val userRepository: UserRepository,
    private val courseRepository: CourseRepository,
    private val messagingTemplate: SimpMessagingTemplate
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private fun currentUserId(): UUID =
        UUID.fromString(SecurityContextHolder.getContext().authentication.principal as String)

    @GetMapping("/my-history")
    fun getMyHistory(): List<Map<String, Any>> {
        val studentId = currentUserId()
        val scans = scanRepository.findByStudentId(studentId)
        return scans.sortedByDescending { it.submittedAt }.map { scan ->
            val session = sessionRepository.findById(scan.sessionId).orElse(null)
            val course = session?.let { courseRepository.findById(it.courseId).orElse(null) }
            val layerResults = scanLayerResultRepository.findByScanId(scan.id!!)
            mapOf(
                "scanId" to scan.id!!,
                "sessionId" to scan.sessionId,
                "courseCode" to (course?.code ?: "Unknown"),
                "courseName" to (course?.name ?: "Unknown"),
                "finalStatus" to scan.finalStatus.name,
                "submittedAt" to scan.submittedAt,
                "layerResults" to layerResults.map {
                    mapOf(
                        "layer" to it.layerName,
                        "passed" to it.passed,
                        "score" to it.score,
                        "detail" to (it.detail ?: "")
                    )
                }
            )
        }
    }

    /**
     * FR-8 through FR-13: The core attendance verification endpoint.
     * Accepts all four signals, runs the fusion pipeline, persists result + per-layer audit.
     */
    @PostMapping("/verify", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    fun verify(
        @RequestParam("qrToken") qrToken: String,
        @RequestParam("deviceFingerprint") deviceFingerprint: String,
        @RequestParam("latitude") latitude: Double,
        @RequestParam("longitude") longitude: Double,
        @RequestParam("faceFrame") faceFrame: MultipartFile
    ): ScanResponse {
        val studentId = currentUserId()

        // Determine session from QR token (peek — actual validation happens in pipeline)
        // We need to extract sessionId first to check session status
        val sessionId = extractSessionIdFromToken(qrToken)
            ?: throw com.secureattend.common.exception.ValidationException("qrToken", "Invalid QR token format")

        // Check session exists and is active (FR-7)
        val session = sessionRepository.findById(sessionId)
            .orElseThrow { ResourceNotFoundException("Session", sessionId.toString()) }

        if (session.status == SessionStatus.CLOSED) {
            throw SessionClosedException(sessionId.toString())
        }

        // Check for duplicate attendance
        scanRepository.findAcceptedScan(sessionId, studentId)?.let {
            throw AlreadyAttendedException(sessionId.toString())
        }

        // Build pipeline input
        val input = ScanInput(
            studentId = studentId,
            qrToken = qrToken,
            deviceFingerprint = deviceFingerprint,
            latitude = latitude,
            longitude = longitude,
            faceFrameBytes = faceFrame.bytes
        )

        // Execute fusion pipeline
        val fusionResult = fusionPipeline.execute(input, sessionId, session)

        // Persist scan
        val scan = scanRepository.save(
            Scan(
                sessionId = sessionId,
                studentId = studentId,
                finalStatus = fusionResult.finalStatus,
                deviceFingerprint = deviceFingerprint,
                locationLat = latitude,
                locationLon = longitude
            )
        )

        // Persist per-layer results (FR-13, NFR-6)
        fusionResult.layerResults.forEach { layer ->
            scanLayerResultRepository.save(
                ScanLayerResult(
                    scanId = scan.id!!,
                    layerName = layer.layerName,
                    passed = layer.passed,
                    score = layer.score,
                    detail = layer.detail
                )
            )
        }

        // If FLAGGED, add to review queue (FR-14)
        if (fusionResult.finalStatus == ScanStatus.FLAGGED) {
            reviewQueueRepository.save(
                ReviewQueueEntry(
                    scanId = scan.id!!,
                    flaggedReason = fusionResult.flaggedReason ?: "Flagged by verification pipeline"
                )
            )
            log.info("[SCAN:{}] FLAGGED — reason: {}", scan.id, fusionResult.flaggedReason)
        }

        // Broadcast scan result to live attendance feed
        val student = userRepository.findById(studentId).orElse(null)
        messagingTemplate.convertAndSend(
            "/topic/session/$sessionId/attendance",
            mapOf(
                "scanId" to scan.id,
                "studentName" to (student?.fullName ?: "Unknown"),
                "finalStatus" to fusionResult.finalStatus.name,
                "submittedAt" to scan.submittedAt
            )
        )

        log.info("[SCAN:{}] Final: {} for student {} in session {}",
            scan.id, fusionResult.finalStatus, studentId, sessionId)

        return ScanResponse(
            scanId = scan.id!!,
            sessionId = sessionId,
            finalStatus = fusionResult.finalStatus,
            layerResults = fusionResult.layerResults.map { it.toResponse() },
            submittedAt = scan.submittedAt
        )
    }

    /**
     * Extract sessionId from QR token without full validation (for pre-checks).
     */
    private fun extractSessionIdFromToken(token: String): UUID? {
        return try {
            // Decode the JWT payload without verification just to get the session ID
            val parts = token.split(".")
            if (parts.size != 3) return null
            val payload = String(java.util.Base64.getUrlDecoder().decode(parts[1]))
            val mapper = com.fasterxml.jackson.databind.ObjectMapper()
            val claims = mapper.readTree(payload)
            UUID.fromString(claims.get("sid")?.asText())
        } catch (ex: Exception) {
            null
        }
    }

    private fun LayerResult.toResponse() = LayerResultResponse(
        layer = layerName,
        passed = passed,
        score = score,
        detail = detail
    )
}

// ---- Attendance Listing (used by SessionController) ----

@RestController
@RequestMapping("/api/sessions")
class AttendanceController(
    private val sessionRepository: SessionRepository,
    private val scanRepository: ScanRepository,
    private val scanLayerResultRepository: ScanLayerResultRepository,
    private val userRepository: UserRepository
) {

    @GetMapping("/{sessionId}/attendance")
    fun getAttendance(
        @PathVariable sessionId: UUID,
        @RequestParam(required = false) status: ScanStatus?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "50") size: Int
    ): Page<AttendanceListItem> {
        sessionRepository.findById(sessionId)
            .orElseThrow { ResourceNotFoundException("Session", sessionId.toString()) }

        val pageable = PageRequest.of(page, size)
        val scans = if (status != null) {
            scanRepository.findBySessionIdAndFinalStatus(sessionId, status, pageable)
        } else {
            scanRepository.findBySessionId(sessionId, pageable)
        }

        return scans.map { scan ->
            val student = userRepository.findById(scan.studentId).orElse(null)
            val layerResults = scanLayerResultRepository.findByScanId(scan.id!!)

            AttendanceListItem(
                scanId = scan.id,
                studentId = scan.studentId,
                studentName = student?.fullName ?: "Unknown",
                studentEmail = student?.email ?: "Unknown",
                finalStatus = scan.finalStatus,
                submittedAt = scan.submittedAt,
                layerResults = layerResults.map {
                    LayerResultResponse(
                        layer = it.layerName,
                        passed = it.passed,
                        score = it.score,
                        detail = it.detail ?: ""
                    )
                }
            )
        }
    }
}
