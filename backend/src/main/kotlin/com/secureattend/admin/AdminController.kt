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
    @field:NotBlank val name: String,
    val branch: String? = null,
    val year: Int? = null,
    val semester: Int? = null,
    val facultyId: UUID? = null,
    val academicSession: String? = null,
    val courseType: String? = null,
    val credits: Int? = null,
    val isActive: Boolean = true
)

data class UpdateCourseRequest(
    val code: String? = null,
    val name: String? = null,
    val branch: String? = null,
    val year: Int? = null,
    val semester: Int? = null,
    val facultyId: UUID? = null,
    val academicSession: String? = null,
    val courseType: String? = null,
    val credits: Int? = null,
    val isActive: Boolean? = null
)

data class CourseResponse(
    val id: UUID,
    val code: String,
    val name: String,
    val branch: String? = null,
    val year: Int? = null,
    val semester: Int? = null,
    val facultyId: UUID? = null,
    val facultyName: String? = null,
    val facultyEmail: String? = null,
    val academicSession: String? = null,
    val courseType: String? = null,
    val credits: Int? = null,
    val isActive: Boolean = true,
    val enrolledCount: Long = 0,
    val createdAt: Instant
)

data class EnrollStudentsRequest(
    val studentIds: List<UUID>
)

data class EnrollStudentsResponse(
    val enrolled: Int,
    val alreadyEnrolled: Int
)

data class EnrolledStudentResponse(
    val id: UUID,
    val fullName: String,
    val username: String? = null,
    val email: String,
    val rollNo: String? = null,
    val branch: String? = null,
    val section: String? = null,
    val semester: Int? = null,
    val status: UserStatus,
    val enrolledAt: Instant
)

data class BulkEnrollPreviewResponse(
    val branch: String?,
    val totalBranchStudents: Int,
    val alreadyEnrolledCount: Int,
    val newToEnrollCount: Int
)

data class BulkEnrollResponse(
    val enrolledCount: Int,
    val alreadyEnrolledCount: Int,
    val totalBranchStudents: Int,
    val branch: String?
)

// ---- User DTOs ----

data class CreateUserRequest(
    @field:Email @field:NotBlank val email: String,
    val username: String? = null,
    @field:NotBlank @field:Size(min = 8) val password: String,
    @field:NotBlank val fullName: String,
    val role: UserRole,
    val branch: String? = null,
    val section: String? = null,
    val rollNo: String? = null,
    val fatherName: String? = null,
    val semester: Int? = null
)

data class UpdateUserRequest(
    val fullName: String? = null,
    val username: String? = null,
    val email: String? = null,
    val branch: String? = null,
    val section: String? = null,
    val rollNo: String? = null,
    val fatherName: String? = null,
    val semester: Int? = null
)

data class UpdateUserStatusRequest(
    val status: UserStatus
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
    val semester: Int? = null,
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
        val normalizedCode = request.code.trim().uppercase()
        if (courseRepository.existsByCode(normalizedCode)) {
            throw ResourceAlreadyExistsException("Course", normalizedCode)
        }

        if (request.facultyId != null) {
            val faculty = userRepository.findById(request.facultyId).orElseThrow {
                ResourceNotFoundException("Faculty", request.facultyId.toString())
            }
            if (faculty.role != UserRole.FACULTY && faculty.role != UserRole.ADMIN) {
                throw com.secureattend.common.exception.ValidationException("facultyId", "Assigned user must have FACULTY role")
            }
        }

        val course = courseRepository.save(
            Course(
                code = normalizedCode,
                name = request.name.trim(),
                branch = request.branch?.trim(),
                year = request.year,
                semester = request.semester,
                facultyId = request.facultyId,
                academicSession = request.academicSession?.trim(),
                courseType = request.courseType?.trim()?.uppercase(),
                credits = request.credits,
                isActive = request.isActive,
                createdBy = currentUserId()
            )
        )

        log.info("Course created: {} ({}) with faculty: {}", course.code, course.id, course.facultyId)
        return course.toResponse()
    }

    @GetMapping("/courses")
    fun listCourses(
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) branch: String?,
        @RequestParam(required = false) facultyId: UUID?,
        @RequestParam(required = false) semester: Int?,
        @RequestParam(required = false) academicSession: String?,
        @RequestParam(required = false) isActive: Boolean?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "50") size: Int
    ): Page<CourseResponse> {
        val pageable = PageRequest.of(page, size)
        val courses = courseRepository.filterCourses(
            branch = if (branch.isNullOrBlank()) null else branch.trim(),
            facultyId = facultyId,
            semester = semester,
            academicSession = if (academicSession.isNullOrBlank()) null else academicSession.trim(),
            isActive = isActive,
            search = if (search.isNullOrBlank()) null else search.trim(),
            pageable = pageable
        )
        return courses.map { it.toResponse() }
    }

    @PutMapping("/courses/{courseId}")
    fun updateCourse(
        @PathVariable courseId: UUID,
        @RequestBody request: UpdateCourseRequest
    ): CourseResponse {
        val course = courseRepository.findById(courseId)
            .orElseThrow { ResourceNotFoundException("Course", courseId.toString()) }

        if (request.code != null && request.code.trim().uppercase() != course.code) {
            val normalizedCode = request.code.trim().uppercase()
            if (courseRepository.existsByCode(normalizedCode)) {
                throw ResourceAlreadyExistsException("Course", normalizedCode)
            }
        }

        if (request.facultyId != null) {
            val faculty = userRepository.findById(request.facultyId).orElseThrow {
                ResourceNotFoundException("Faculty", request.facultyId.toString())
            }
            if (faculty.role != UserRole.FACULTY && faculty.role != UserRole.ADMIN) {
                throw com.secureattend.common.exception.ValidationException("facultyId", "Assigned user must have FACULTY role")
            }
        }

        val updated = courseRepository.save(
            course.copy(
                code = request.code?.trim()?.uppercase() ?: course.code,
                name = request.name?.trim() ?: course.name,
                branch = if (request.branch != null) request.branch.trim() else course.branch,
                year = request.year ?: course.year,
                semester = request.semester ?: course.semester,
                facultyId = if (request.facultyId != null) request.facultyId else course.facultyId,
                academicSession = if (request.academicSession != null) request.academicSession.trim() else course.academicSession,
                courseType = if (request.courseType != null) request.courseType.trim().uppercase() else course.courseType,
                credits = request.credits ?: course.credits,
                isActive = request.isActive ?: course.isActive,
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
        val course = courseRepository.findById(courseId)
            .orElseThrow { ResourceNotFoundException("Course", courseId.toString()) }

        val courseBranch = course.branch
        if (courseBranch.isNullOrBlank()) {
            throw com.secureattend.common.exception.ValidationException(
                "branch",
                "Cannot enroll students: Course '${course.code}' has no branch assigned."
            )
        }

        var enrolled = 0
        var alreadyEnrolled = 0

        request.studentIds.forEach { studentId ->
            val student = userRepository.findById(studentId).orElse(null) ?: return@forEach

            // Enforce that student and course must have the same branch
            if (student.branch.isNullOrBlank() || !student.branch.equals(courseBranch, ignoreCase = true)) {
                throw com.secureattend.common.exception.ValidationException(
                    "branch",
                    "Student '${student.fullName}' (${student.branch ?: "No Branch"}) cannot be enrolled in course '${course.code}' ($courseBranch). Student and course must belong to the same branch."
                )
            }

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
        log.info("Unenrolled student {} from course {}", studentId, courseId)
    }

    @GetMapping("/courses/{courseId}/students")
    fun listCourseStudents(@PathVariable courseId: UUID): List<EnrolledStudentResponse> {
        if (!courseRepository.existsById(courseId)) {
            throw ResourceNotFoundException("Course", courseId.toString())
        }

        val enrollments = courseEnrollmentRepository.findByIdCourseId(courseId)
        val studentIds = enrollments.map { it.id.studentId }
        val studentsMap = userRepository.findAllById(studentIds).associateBy { it.id!! }

        return enrollments.mapNotNull { enrollment ->
            val student = studentsMap[enrollment.id.studentId] ?: return@mapNotNull null
            EnrolledStudentResponse(
                id = student.id!!,
                fullName = student.fullName,
                username = student.username,
                email = student.email,
                rollNo = student.rollNo,
                branch = student.branch,
                section = student.section,
                semester = student.semester,
                status = student.status,
                enrolledAt = enrollment.enrolledAt
            )
        }.sortedBy { it.fullName }
    }

    @GetMapping("/courses/{courseId}/enroll-preview")
    fun getBulkEnrollPreview(@PathVariable courseId: UUID): BulkEnrollPreviewResponse {
        val course = courseRepository.findById(courseId)
            .orElseThrow { ResourceNotFoundException("Course", courseId.toString()) }

        val branch = course.branch
        if (branch.isNullOrBlank()) {
            return BulkEnrollPreviewResponse(
                branch = null,
                totalBranchStudents = 0,
                alreadyEnrolledCount = 0,
                newToEnrollCount = 0
            )
        }

        val branchStudents = userRepository.findByRoleAndStatusAndBranch(UserRole.STUDENT, UserStatus.ACTIVE, branch)
        val enrollments = courseEnrollmentRepository.findByIdCourseId(courseId)
        val enrolledStudentIds = enrollments.map { it.id.studentId }.toSet()

        val alreadyEnrolled = branchStudents.count { enrolledStudentIds.contains(it.id!!) }
        val newToEnroll = branchStudents.count { !enrolledStudentIds.contains(it.id!!) }

        return BulkEnrollPreviewResponse(
            branch = branch,
            totalBranchStudents = branchStudents.size,
            alreadyEnrolledCount = alreadyEnrolled,
            newToEnrollCount = newToEnroll
        )
    }

    @PostMapping("/courses/{courseId}/enroll-branch")
    fun bulkEnrollBranch(@PathVariable courseId: UUID): BulkEnrollResponse {
        val course = courseRepository.findById(courseId)
            .orElseThrow { ResourceNotFoundException("Course", courseId.toString()) }

        val branch = course.branch
        if (branch.isNullOrBlank()) {
            throw com.secureattend.common.exception.ValidationException(
                "branch",
                "Cannot bulk enroll by branch: Course has no branch/department assigned."
            )
        }

        val branchStudents = userRepository.findByRoleAndStatusAndBranch(UserRole.STUDENT, UserStatus.ACTIVE, branch)
        val enrollments = courseEnrollmentRepository.findByIdCourseId(courseId)
        val enrolledStudentIds = enrollments.map { it.id.studentId }.toSet()

        var enrolled = 0
        var alreadyEnrolled = 0

        branchStudents.forEach { student ->
            if (enrolledStudentIds.contains(student.id!!)) {
                alreadyEnrolled++
            } else {
                courseEnrollmentRepository.save(
                    CourseEnrollment(id = CourseEnrollmentId(student.id!!, courseId))
                )
                enrolled++
            }
        }

        log.info("Bulk enrolled {} students from branch '{}' into course {} ({} already enrolled)",
            enrolled, branch, courseId, alreadyEnrolled)

        return BulkEnrollResponse(
            enrolledCount = enrolled,
            alreadyEnrolledCount = alreadyEnrolled,
            totalBranchStudents = branchStudents.size,
            branch = branch
        )
    }

    // ---- User Management ----

    @GetMapping("/users")
    fun listUsers(
        @RequestParam(required = false) role: UserRole?,
        @RequestParam(required = false) search: String?,
        @RequestParam(required = false) status: UserStatus?,
        @RequestParam(required = false) branch: String?,
        @RequestParam(required = false) semester: Int?,
        @RequestParam(defaultValue = "0") page: Int,
        @RequestParam(defaultValue = "100") size: Int
    ): Page<UserListItem> {
        val pageable = PageRequest.of(page, size)

        val users = userRepository.filterUsers(
            role = role,
            status = status,
            branch = if (branch.isNullOrBlank()) null else branch.trim(),
            semester = semester,
            search = if (search.isNullOrBlank()) null else search.trim(),
            pageable = pageable
        )

        return users.map { it.toListItem() }
    }

    @GetMapping("/users/{userId}")
    fun getUser(@PathVariable userId: UUID): UserListItem {
        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }
        return user.toListItem()
    }

    @PostMapping("/users")
    @ResponseStatus(HttpStatus.CREATED)
    fun createUser(@Valid @RequestBody request: CreateUserRequest): UserListItem {
        val normalizedEmail = request.email.trim().lowercase()
        val normalizedUsername = request.username?.trim()?.lowercase()

        // If student or faculty, email must end with @kiet.edu
        if (request.role in listOf(UserRole.STUDENT, UserRole.FACULTY)) {
            if (!normalizedEmail.endsWith("@kiet.edu")) {
                throw com.secureattend.common.exception.ValidationException("email", "Email must end with @kiet.edu")
            }
        }

        if (userRepository.existsByEmail(normalizedEmail)) {
            throw ResourceAlreadyExistsException("User", normalizedEmail)
        }

        if (!normalizedUsername.isNullOrEmpty()) {
            if (!normalizedUsername.matches(Regex("^[a-zA-Z0-9_]{3,30}$"))) {
                throw com.secureattend.common.exception.ValidationException(
                    "username",
                    "Username must be 3-30 characters long and contain only letters, numbers, and underscores"
                )
            }
            if (userRepository.existsByUsername(normalizedUsername)) {
                throw ResourceAlreadyExistsException("Username", normalizedUsername)
            }
        }

        if (request.role == UserRole.STUDENT) {
            if (request.rollNo != null && !request.rollNo.trim().matches(Regex("^[0-9]+$"))) {
                throw com.secureattend.common.exception.ValidationException("rollNo", "Roll number must be numerical only")
            }
        }

        // Admin-created users are immediately ACTIVE
        val user = userRepository.save(
            User(
                email = normalizedEmail,
                username = normalizedUsername,
                passwordHash = passwordEncoder.encode(request.password),
                fullName = request.fullName.trim(),
                role = request.role,
                status = UserStatus.ACTIVE,
                branch = request.branch?.trim(),
                section = request.section?.trim(),
                rollNo = request.rollNo?.trim(),
                fatherName = request.fatherName?.trim(),
                semester = request.semester
            )
        )

        log.info("Admin created new user: {} (username: {}) with role {}", user.email, user.username, user.role)
        return user.toListItem()
    }

    @PutMapping("/users/{userId}")
    fun updateUser(
        @PathVariable userId: UUID,
        @RequestBody request: UpdateUserRequest
    ): UserListItem {
        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }

        val newEmail = request.email?.trim()?.lowercase()
        if (newEmail != null && newEmail != user.email) {
            if (user.role in listOf(UserRole.STUDENT, UserRole.FACULTY) && !newEmail.endsWith("@kiet.edu")) {
                throw com.secureattend.common.exception.ValidationException("email", "Email must end with @kiet.edu")
            }
            if (userRepository.existsByEmail(newEmail)) {
                throw ResourceAlreadyExistsException("User", newEmail)
            }
        }

        val newUsername = request.username?.trim()?.lowercase()
        if (newUsername != null && newUsername != user.username) {
            if (!newUsername.matches(Regex("^[a-zA-Z0-9_]{3,30}$"))) {
                throw com.secureattend.common.exception.ValidationException(
                    "username",
                    "Username must be 3-30 characters long and contain only letters, numbers, and underscores"
                )
            }
            if (userRepository.existsByUsername(newUsername)) {
                throw ResourceAlreadyExistsException("Username", newUsername)
            }
        }

        if (user.role == UserRole.STUDENT && request.rollNo != null) {
            if (!request.rollNo.trim().matches(Regex("^[0-9]+$"))) {
                throw com.secureattend.common.exception.ValidationException("rollNo", "Roll number must be numerical only")
            }
        }

        val updated = userRepository.save(
            user.copy(
                email = newEmail ?: user.email,
                username = newUsername ?: user.username,
                fullName = request.fullName?.trim() ?: user.fullName,
                branch = if (request.branch != null) request.branch.trim() else user.branch,
                section = if (request.section != null) request.section.trim() else user.section,
                rollNo = if (request.rollNo != null) request.rollNo.trim() else user.rollNo,
                fatherName = if (request.fatherName != null) request.fatherName.trim() else user.fatherName,
                semester = request.semester ?: user.semester,
                updatedAt = Instant.now()
            )
        )

        log.info("Admin updated user profile: {}", userId)
        return updated.toListItem()
    }

    @PatchMapping("/users/{userId}/status")
    fun updateUserStatus(
        @PathVariable userId: UUID,
        @RequestBody request: UpdateUserStatusRequest
    ): UserListItem {
        val currentAdminId = currentUserId()
        if (userId == currentAdminId && request.status != UserStatus.ACTIVE) {
            throw com.secureattend.common.exception.ValidationException("status", "Cannot deactivate your own admin account")
        }

        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }

        val updated = userRepository.save(
            user.copy(status = request.status, updatedAt = Instant.now())
        )
        log.info("Admin updated status for user {} to {}", user.email, request.status)
        return updated.toListItem()
    }

    @DeleteMapping("/users/{userId}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    fun deleteUser(@PathVariable userId: UUID) {
        val currentAdminId = currentUserId()
        if (userId == currentAdminId) {
            throw com.secureattend.common.exception.ValidationException("userId", "Cannot delete your own admin account")
        }

        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }

        try {
            // Remove device registrations
            deviceRegistrationRepository.findByStudentIdAndIsActiveTrue(userId)?.let {
                deviceRegistrationRepository.delete(it)
            }
            // Remove face embeddings
            faceEmbeddingRepository.findByStudentId(userId)?.let {
                faceEmbeddingRepository.delete(it)
            }
            // Remove course enrollments
            courseEnrollmentRepository.findByIdStudentId(userId).forEach {
                courseEnrollmentRepository.delete(it)
            }
            // If faculty, unassign courses
            if (user.role == UserRole.FACULTY) {
                val assignedCourses = courseRepository.findAll().filter { it.facultyId == userId }
                assignedCourses.forEach { course ->
                    courseRepository.save(course.copy(facultyId = null, updatedAt = Instant.now()))
                }
            }
            userRepository.deleteById(userId)
            log.info("Admin permanently deleted user: {} ({})", user.email, userId)
        } catch (e: Exception) {
            log.error("Failed to delete user $userId", e)
            throw com.secureattend.common.exception.ValidationException(
                "userId",
                "Cannot delete user due to associated records. Consider deactivating the account instead."
            )
        }
    }

    // ---- User Approval ----

    @PatchMapping("/users/{userId}/approve")
    fun approveUser(@PathVariable userId: UUID): UserListItem {
        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }
        val updated = userRepository.save(
            user.copy(status = UserStatus.ACTIVE, updatedAt = Instant.now())
        )
        log.info("Admin approved user: {} ({})", updated.email, updated.id)
        return updated.toListItem()
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

    private fun Course.toResponse(): CourseResponse {
        val faculty = facultyId?.let { userRepository.findById(it).orElse(null) }
        val enrolledCount = if (id != null) courseEnrollmentRepository.countByIdCourseId(id!!) else 0L
        return CourseResponse(
            id = id!!,
            code = code,
            name = name,
            branch = branch,
            year = year,
            semester = semester,
            facultyId = facultyId,
            facultyName = faculty?.fullName,
            facultyEmail = faculty?.email,
            academicSession = academicSession,
            courseType = courseType,
            credits = credits,
            isActive = isActive,
            enrolledCount = enrolledCount,
            createdAt = createdAt
        )
    }

    private fun User.toListItem(): UserListItem {
        val faceEnrolled = if (role == UserRole.STUDENT && id != null) faceEmbeddingRepository.existsByStudentId(id) else null
        val deviceRegistered = if (role == UserRole.STUDENT && id != null) deviceRegistrationRepository.existsByStudentIdAndIsActiveTrue(id) else null

        return UserListItem(
            id = id!!,
            email = email,
            username = username,
            fullName = fullName,
            role = role,
            status = status,
            branch = branch,
            section = section,
            rollNo = rollNo,
            fatherName = fatherName,
            semester = semester,
            createdAt = createdAt,
            faceEnrolled = faceEnrolled,
            deviceRegistered = deviceRegistered
        )
    }
}
