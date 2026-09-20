package com.secureattend.session

import com.secureattend.common.entity.Session
import com.secureattend.common.entity.SessionStatus
import com.secureattend.common.entity.UserRole
import com.secureattend.common.exception.ForbiddenException
import com.secureattend.common.exception.ResourceAlreadyExistsException
import com.secureattend.common.exception.ResourceNotFoundException
import com.secureattend.common.exception.SessionClosedException
import com.secureattend.common.exception.ValidationException
import com.secureattend.common.repository.CourseRepository
import com.secureattend.common.repository.ScanRepository
import com.secureattend.common.repository.SessionRepository
import com.secureattend.common.repository.UserRepository
import jakarta.validation.Valid
import jakarta.validation.constraints.Max
import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotNull
import org.slf4j.LoggerFactory
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.http.HttpStatus
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.web.bind.annotation.*
import java.time.Instant
import java.util.UUID

// ---- DTOs ----

data class CreateSessionRequest(
    @field:NotNull val courseId: UUID,
    @field:NotNull val geofenceLat: Double,
    @field:NotNull val geofenceLon: Double,
    @field:Min(10) @field:Max(1000) val geofenceRadiusMeters: Int = 100,
    @field:Min(5) @field:Max(60) val qrRotationSeconds: Int = 10
)

data class SessionResponse(
    val id: UUID,
    val courseId: UUID,
    val courseCode: String? = null,
    val courseName: String? = null,
    val facultyId: UUID,
    val geofenceLat: Double,
    val geofenceLon: Double,
    val geofenceRadiusMeters: Int,
    val qrRotationSeconds: Int,
    val status: SessionStatus,
    val startedAt: Instant,
    val closedAt: Instant? = null,
    val attendanceSummary: AttendanceSummary? = null
)

data class AttendanceSummary(
    val present: Long,
    val flagged: Long,
    val rejected: Long,
    val total: Long
)

data class SessionListItem(
    val id: UUID,
    val courseCode: String,
    val courseName: String,
    val status: SessionStatus,
    val startedAt: Instant,
    val attendanceCount: Long
)

// ---- Controller ----

@RestController
@RequestMapping("/api/sessions")
class SessionController(
    private val sessionRepository: SessionRepository,
    private val courseRepository: CourseRepository,
    private val scanRepository: ScanRepository,
    private val userRepository: UserRepository,
    private val qrTokenService: QrTokenService
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private fun currentUserId(): UUID =
        UUID.fromString(SecurityContextHolder.getContext().authentication.principal as String)

    /**
     * FR-4: Create a session bound to a course + geofence.
     */
    @PostMapping
    @ResponseStatus(HttpStatus.CREATED)
    fun createSession(@Valid @RequestBody request: CreateSessionRequest): SessionResponse {
        val facultyId = currentUserId()

        val course = courseRepository.findById(request.courseId)
            .orElseThrow { ResourceNotFoundException("Course", request.courseId.toString()) }

        if (!course.isActive) {
            throw ValidationException("courseId", "Cannot start session for an inactive course")
        }

        // Only assigned faculty (or admin) can create attendance session
        if (course.facultyId != null && course.facultyId != facultyId) {
            val user = userRepository.findById(facultyId).orElse(null)
            if (user?.role != UserRole.ADMIN) {
                val assignedFaculty = userRepository.findById(course.facultyId!!).orElse(null)
                val facultyName = assignedFaculty?.fullName ?: "another faculty member"
                throw ForbiddenException("Only the assigned faculty ($facultyName) can conduct attendance for this course")
            }
        }

        // Check no active session for this course
        sessionRepository.findByCourseIdAndStatus(request.courseId, SessionStatus.ACTIVE)?.let {
            throw ResourceAlreadyExistsException("Active session for course", course.code)
        }

        val session = sessionRepository.save(
            Session(
                courseId = request.courseId,
                facultyId = facultyId,
                geofenceLat = request.geofenceLat,
                geofenceLon = request.geofenceLon,
                geofenceRadiusMeters = request.geofenceRadiusMeters,
                qrRotationSeconds = request.qrRotationSeconds
            )
        )

        // Start QR rotation for this session
        qrTokenService.startRotation(session)

        log.info("Session created: {} for course {} by faculty {}", session.id, course.code, facultyId)
        return session.toResponse(course.code, course.name)
    }

    /**
     * FR-7: Close session — no scans accepted after closure.
     */
    @PatchMapping("/{sessionId}/close")
    fun closeSession(@PathVariable sessionId: UUID): SessionResponse {
        val session = sessionRepository.findById(sessionId)
            .orElseThrow { ResourceNotFoundException("Session", sessionId.toString()) }

        if (session.status == SessionStatus.CLOSED) {
            throw SessionClosedException(sessionId.toString())
        }

        session.status = SessionStatus.CLOSED
        session.closedAt = Instant.now()
        sessionRepository.save(session)

        // Stop QR rotation
        qrTokenService.stopRotation(sessionId)

        val course = courseRepository.findById(session.courseId).orElse(null)
        log.info("Session closed: {}", sessionId)
        return session.toResponse(course?.code, course?.name, includeAttendance = true)
    }

    /**
     * FR-6: Returns the current QR token for a session (REST polling fallback / Display Mode bootstrap).
     */
    @GetMapping("/{sessionId}/qr-token")
    fun getCurrentQrToken(@PathVariable sessionId: UUID): Map<String, Any> {
        val session = sessionRepository.findById(sessionId)
            .orElseThrow { ResourceNotFoundException("Session", sessionId.toString()) }

        if (session.status == SessionStatus.CLOSED) {
            throw SessionClosedException(sessionId.toString())
        }

        val token = qrTokenService.getCurrentToken(sessionId)
        if (token.isEmpty()) {
            throw ResourceNotFoundException("QR token for active session", sessionId.toString())
        }

        return mapOf(
            "token" to token,
            "rotationSeconds" to session.qrRotationSeconds,
            "expiresAt" to (System.currentTimeMillis() / 1000 + session.qrRotationSeconds + 5)
        )
    }

    @GetMapping("/{sessionId}")
    fun getSession(@PathVariable sessionId: UUID): SessionResponse {
        val session = sessionRepository.findById(sessionId)
            .orElseThrow { ResourceNotFoundException("Session", sessionId.toString()) }

        val course = courseRepository.findById(session.courseId).orElse(null)
        return session.toResponse(course?.code, course?.name, includeAttendance = true)
    }

    @GetMapping
    fun listSessions(
        @RequestParam(required = false) courseId: UUID?,
        @RequestParam(required = false) status: SessionStatus?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): Page<SessionListItem> {
        val facultyId = currentUserId()
        val pageable = PageRequest.of(page, size)

        val sessions = when {
            status != null -> sessionRepository.findByFacultyIdAndStatus(facultyId, status, pageable)
            else -> sessionRepository.findByFacultyId(facultyId, pageable)
        }

        return sessions.map { session ->
            val course = courseRepository.findById(session.courseId).orElse(null)
            SessionListItem(
                id = session.id!!,
                courseCode = course?.code ?: "N/A",
                courseName = course?.name ?: "N/A",
                status = session.status,
                startedAt = session.startedAt,
                attendanceCount = scanRepository.countTotal(session.id)
            )
        }
    }

    private fun Session.toResponse(
        courseCode: String? = null,
        courseName: String? = null,
        includeAttendance: Boolean = false
    ): SessionResponse {
        val summary = if (includeAttendance && id != null) {
            AttendanceSummary(
                present = scanRepository.countPresent(id),
                flagged = scanRepository.countFlagged(id),
                rejected = scanRepository.countRejected(id),
                total = scanRepository.countTotal(id)
            )
        } else null

        return SessionResponse(
            id = id!!,
            courseId = courseId,
            courseCode = courseCode,
            courseName = courseName,
            facultyId = facultyId,
            geofenceLat = geofenceLat,
            geofenceLon = geofenceLon,
            geofenceRadiusMeters = geofenceRadiusMeters,
            qrRotationSeconds = qrRotationSeconds,
            status = status,
            startedAt = startedAt,
            closedAt = closedAt,
            attendanceSummary = summary
        )
    }
}
