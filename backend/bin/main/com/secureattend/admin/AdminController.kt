package com.secureattend.admin

import com.secureattend.common.entity.Course
import com.secureattend.common.entity.CourseEnrollment
import com.secureattend.common.entity.CourseEnrollmentId
import com.secureattend.common.entity.User
import com.secureattend.common.entity.UserRole
import com.secureattend.common.entity.UserStatus
import com.secureattend.common.exception.ResourceAlreadyExistsException
import com.secureattend.common.exception.ResourceNotFoundException
import com.secureattend.common.repository.CourseEnrollmentRepository
import com.secureattend.common.repository.CourseRepository
import com.secureattend.common.repository.FaceEmbeddingRepository
import com.secureattend.common.repository.DeviceRegistrationRepository
import com.secureattend.common.repository.UserRepository
import jakarta.validation.Valid
import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.slf4j.LoggerFactory
import org.springframework.data.domain.Page
import org.springframework.data.domain.PageRequest
import org.springframework.http.HttpStatus
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.web.bind.annotation.*
import java.time.Instant
import java.util.UUID

// ---- Course DTOs ----

data class CreateCourseRequest(
    @field:NotBlank val code: String,
    @field:NotBlank val name: String
)

data class UpdateCourseRequest(
    val code: String? = null,
    val name: String? = null
)

data class CourseResponse(
    val id: UUID,
    val code: String,
    val name: String,
    val createdAt: Instant
)

data class EnrollStudentsRequest(
    val studentIds: List<UUID>
)

data class EnrollStudentsResponse(
    val enrolled: Int,
    val alreadyEnrolled: Int
)

// ---- User DTOs ----

data class CreateUserRequest(
    @field:Email @field:NotBlank val email: String,
    @field:NotBlank @field:Size(min = 8) val password: String,
    @field:NotBlank val fullName: String,
    val role: UserRole
)

data class UserListItem(
    val id: UUID,
    val email: String,
    val username: String? = null,
    val fullName: String,
    val role: UserRole,
    val status: UserStatus,
    val branch: String? = null,
    val section: String? = null,
    val rollNo: String? = null,
    val fatherName: String? = null,
    val createdAt: Instant,
    val faceEnrolled: Boolean? = null,
    val deviceRegistered: Boolean? = null
)

// ---- Controller ----

@RestController
@RequestMapping("/api/admin")
class AdminController(
    private val courseRepository: CourseRepository,
    private val courseEnrollmentRepository: CourseEnrollmentRepository,
    private val userRepository: UserRepository,
    private val faceEmbeddingRepository: FaceEmbeddingRepository,
    private val deviceRegistrationRepository: DeviceRegistrationRepository,
    private val passwordEncoder: PasswordEncoder
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private fun currentUserId(): UUID =
        UUID.fromString(SecurityContextHolder.getContext().authentication.principal as String)

    // ---- Course CRUD ----

    @PostMapping("/courses")
    @ResponseStatus(HttpStatus.CREATED)
    fun createCourse(@Valid @RequestBody request: CreateCourseRequest): CourseResponse {
        if (courseRepository.existsByCode(request.code)) {
            throw ResourceAlreadyExistsException("Course", request.code)
        }

        val course = courseRepository.save(
            Course(
                code = request.code,
                name = request.name,
                createdBy = currentUserId()
            )
        )

        log.info("Course created: {} ({})", course.code, course.id)
        return course.toResponse()
    }

    @GetMapping("/courses")
    fun listCourses(
        @RequestParam(required = false) search: String?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): Page<CourseResponse> {
        val pageable = PageRequest.of(page, size)
        val courses = if (!search.isNullOrBlank()) {
            courseRepository.search(search, pageable)
        } else {
            courseRepository.findAll(pageable)
        }
        return courses.map { it.toResponse() }
    }

    @PutMapping("/courses/{courseId}")
    fun updateCourse(
        @PathVariable courseId: UUID,
        @RequestBody request: UpdateCourseRequest
    ): CourseResponse {
        val course = courseRepository.findById(courseId)
            .orElseThrow { ResourceNotFoundException("Course", courseId.toString()) }

        val updated = courseRepository.save(
            course.copy(
                code = request.code ?: course.code,
                name = request.name ?: course.name,
                updatedAt = Instant.now()
            )
        )

        log.info("Course updated: {}", courseId)
        return updated.toResponse()
    }

    @DeleteMapping("/courses/{courseId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteCourse(@PathVariable courseId: UUID) {
        if (!courseRepository.existsById(courseId)) {
            throw ResourceNotFoundException("Course", courseId.toString())
        }
        courseRepository.deleteById(courseId)
        log.info("Course deleted: {}", courseId)
    }

    // ---- Course Enrollment ----

    @PostMapping("/courses/{courseId}/enroll")
    fun enrollStudents(
        @PathVariable courseId: UUID,
        @RequestBody request: EnrollStudentsRequest
    ): EnrollStudentsResponse {
        if (!courseRepository.existsById(courseId)) {
            throw ResourceNotFoundException("Course", courseId.toString())
        }

        var enrolled = 0
        var alreadyEnrolled = 0

        request.studentIds.forEach { studentId ->
            if (courseEnrollmentRepository.existsByIdStudentIdAndIdCourseId(studentId, courseId)) {
                alreadyEnrolled++
            } else {
                courseEnrollmentRepository.save(
                    CourseEnrollment(id = CourseEnrollmentId(studentId, courseId))
                )
                enrolled++
            }
        }

        log.info("Enrolled {} students into course {} ({} already enrolled)", enrolled, courseId, alreadyEnrolled)
        return EnrollStudentsResponse(enrolled = enrolled, alreadyEnrolled = alreadyEnrolled)
    }

    @DeleteMapping("/courses/{courseId}/enroll/{studentId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun unenrollStudent(@PathVariable courseId: UUID, @PathVariable studentId: UUID) {
        val id = CourseEnrollmentId(studentId, courseId)
        if (!courseEnrollmentRepository.existsById(id)) {
            throw ResourceNotFoundException("Enrollment", "$studentId in $courseId")
        }
        courseEnrollmentRepository.deleteById(id)
    }

    // ---- User Management ----

    @GetMapping("/users")
    fun listUsers(
        @RequestParam(required = false) role: UserRole?,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) status: UserStatus?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "20") size: Int
    ): Page<UserListItem> {
        val pageable = PageRequest.of(page, size)

        val users = when {
            role != null && !search.isNullOrBlank() -> userRepository.searchByRoleAndNameOrEmail(role, search, pageable)
            role != null && status != null -> userRepository.findByRoleAndStatus(role, status, pageable)
            role != null -> userRepository.findByRole(role, pageable)
            status != null -> userRepository.findByStatus(status, pageable)
            else -> userRepository.findAll(pageable)
        }

        return users.map { user ->
            val faceEnrolled = if (user.role == UserRole.STUDENT) faceEmbeddingRepository.existsByStudentId(user.id!!) else null
            val deviceRegistered = if (user.role == UserRole.STUDENT) deviceRegistrationRepository.existsByStudentIdAndIsActiveTrue(user.id!!) else null

            UserListItem(
                id = user.id!!,
                email = user.email,
                username = user.username,
                fullName = user.fullName,
                role = user.role,
                status = user.status,
                branch = user.branch,
                section = user.section,
                rollNo = user.rollNo,
                fatherName = user.fatherName,
                createdAt = user.createdAt,
                faceEnrolled = faceEnrolled,
                deviceRegistered = deviceRegistered
            )
        }
    }

    @GetMapping("/users/{userId}")
    fun getUser(@PathVariable userId: UUID): UserListItem {
        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }

        val faceEnrolled = if (user.role == UserRole.STUDENT) faceEmbeddingRepository.existsByStudentId(user.id!!) else null
        val deviceRegistered = if (user.role == UserRole.STUDENT) deviceRegistrationRepository.existsByStudentIdAndIsActiveTrue(user.id!!) else null

        return UserListItem(
            id = user.id!!,
            email = user.email,
            username = user.username,
            fullName = user.fullName,
            role = user.role,
            status = user.status,
            branch = user.branch,
            section = user.section,
            rollNo = user.rollNo,
            fatherName = user.fatherName,
            createdAt = user.createdAt,
            faceEnrolled = faceEnrolled,
            deviceRegistered = deviceRegistered
        )
    }

    @PostMapping("/users")
    @ResponseStatus(HttpStatus.CREATED)
    fun createUser(@Valid @RequestBody request: CreateUserRequest): UserListItem {
        val normalizedEmail = request.email.trim().lowercase()
        if (userRepository.existsByEmail(normalizedEmail)) {
            throw ResourceAlreadyExistsException("User", normalizedEmail)
        }

        // Admin-created users are immediately ACTIVE
        val user = userRepository.save(
            User(
                email = normalizedEmail,
                passwordHash = passwordEncoder.encode(request.password),
                fullName = request.fullName.trim(),
                role = request.role,
                status = UserStatus.ACTIVE
            )
        )

        log.info("Admin created new user: {} with role {}", user.email, user.role)
        return UserListItem(
            id = user.id!!,
            email = user.email,
            username = user.username,
            fullName = user.fullName,
            role = user.role,
            status = user.status,
            branch = user.branch,
            section = user.section,
            rollNo = user.rollNo,
            fatherName = user.fatherName,
            createdAt = user.createdAt,
            faceEnrolled = false,
            deviceRegistered = false
        )
    }

    // ---- User Approval ----

    @PatchMapping("/users/{userId}/approve")
    fun approveUser(@PathVariable userId: UUID): UserListItem {
        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }
        val updated = userRepository.save(
            user.copy(status = UserStatus.ACTIVE, updatedAt = java.time.Instant.now())
        )
        log.info("Admin approved user: {} ({})", updated.email, updated.id)
        return UserListItem(
            id = updated.id!!,
            email = updated.email,
            username = updated.username,
            fullName = updated.fullName,
            role = updated.role,
            status = updated.status,
            branch = updated.branch,
            section = updated.section,
            rollNo = updated.rollNo,
            fatherName = updated.fatherName,
            createdAt = updated.createdAt
        )
    }

    @DeleteMapping("/users/{userId}/reject")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun rejectUser(@PathVariable userId: UUID) {
        if (!userRepository.existsById(userId)) {
            throw ResourceNotFoundException("User", userId.toString())
        }
        userRepository.deleteById(userId)
        log.info("Admin rejected and deleted user: {}", userId)
    }

    private fun Course.toResponse() = CourseResponse(
        id = id!!,
        code = code,
        name = name,
        createdAt = createdAt
    )
}
