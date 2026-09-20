package com.secureattend.review

import com.secureattend.common.entity.ReviewDecision
import com.secureattend.common.entity.ScanStatus
import com.secureattend.common.exception.ResourceAlreadyExistsException
import com.secureattend.common.exception.ResourceNotFoundException
import com.secureattend.common.repository.*
import com.secureattend.scan.LayerResultResponse
import jakarta.validation.Valid
import jakarta.validation.constraints.NotNull
import org.slf4j.LoggerFactory
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.web.bind.annotation.*
import java.time.Instant
import java.util.UUID

// ---- DTOs ----

data class ReviewQueueItem(
    val reviewId: UUID,
    val scanId: UUID,
    val sessionId: UUID,
    val courseCode: String?,
    val studentId: UUID,
    val studentName: String,
    val studentEmail: String,
    val flaggedReason: String,
    val flaggedAt: Instant,
    val layerResults: List<LayerResultResponse>
)

data class ReviewDecisionRequest(
    @field:NotNull val decision: ReviewDecision,
    val notes: String? = null
)

data class ReviewDecisionResponse(
    val scanId: UUID,
    val previousStatus: ScanStatus,
    val newStatus: ScanStatus,
    val reviewedBy: UUID,
    val reviewedAt: Instant
)

// ---- Controller ----

/**
 * FR-14: All FLAGGED scans appear in a faculty-facing review queue.
 * FR-15: Faculty can approve or reject flagged scans.
 */
@RestController
@RequestMapping("/api/review")
class ReviewController(
    private val reviewQueueRepository: ReviewQueueRepository,
    private val scanRepository: ScanRepository,
    private val scanLayerResultRepository: ScanLayerResultRepository,
    private val sessionRepository: SessionRepository,
    private val courseRepository: CourseRepository,
    private val userRepository: UserRepository
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private fun currentUserId(): UUID =
        UUID.fromString(SecurityContextHolder.getContext().authentication.principal as String)

    @GetMapping("/queue")
    fun getQueue(
        @RequestParam(required = false) sessionId: UUID?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): Page<ReviewQueueItem> {
        val pageable = PageRequest.of(page, size)

        val entries = if (sessionId != null) {
            reviewQueueRepository.findPendingBySession(sessionId, pageable)
        } else {
            reviewQueueRepository.findPending(pageable)
        }

        return entries.map { entry ->
            val scan = scanRepository.findById(entry.scanId).orElse(null)
            val student = scan?.let { userRepository.findById(it.studentId).orElse(null) }
            val session = scan?.let { sessionRepository.findById(it.sessionId).orElse(null) }
            val course = session?.let { courseRepository.findById(it.courseId).orElse(null) }
            val layers = scanLayerResultRepository.findByScanId(entry.scanId)

            ReviewQueueItem(
                reviewId = entry.id!!,
                scanId = entry.scanId,
                sessionId = scan?.sessionId ?: UUID.randomUUID(),
                courseCode = course?.code,
                studentId = scan?.studentId ?: UUID.randomUUID(),
                studentName = student?.fullName ?: "Unknown",
                studentEmail = student?.email ?: "Unknown",
                flaggedReason = entry.flaggedReason,
                flaggedAt = entry.flaggedAt,
                layerResults = layers.map {
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

    @PatchMapping("/{scanId}")
    fun reviewScan(
        @PathVariable scanId: UUID,
        @Valid @RequestBody request: ReviewDecisionRequest
    ): ReviewDecisionResponse {
        val facultyId = currentUserId()

        val entry = reviewQueueRepository.findByScanId(scanId)
            ?: throw ResourceNotFoundException("Review entry", scanId.toString())

        if (entry.reviewDecision != null) {
            throw ResourceAlreadyExistsException("Review decision", scanId.toString())
        }

        val scan = scanRepository.findById(scanId)
            .orElseThrow { ResourceNotFoundException("Scan", scanId.toString()) }

        val previousStatus = scan.finalStatus

        // Update scan status based on decision
        val newStatus = when (request.decision) {
            ReviewDecision.APPROVED -> ScanStatus.PRESENT
            ReviewDecision.REJECTED -> ScanStatus.REJECTED
        }
        scan.finalStatus = newStatus
        scanRepository.save(scan)

        // Update review entry
        entry.reviewDecision = request.decision
        entry.reviewedBy = facultyId
        entry.reviewNotes = request.notes
        entry.reviewedAt = Instant.now()
        reviewQueueRepository.save(entry)

        log.info("[REVIEW] Scan {} reviewed: {} → {} by faculty {}",
            scanId, previousStatus, newStatus, facultyId)

        return ReviewDecisionResponse(
            scanId = scanId,
            previousStatus = previousStatus,
            newStatus = newStatus,
            reviewedBy = facultyId,
            reviewedAt = entry.reviewedAt!!
        )
    }
}
