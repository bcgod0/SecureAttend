package com.secureattend.auth

import com.secureattend.common.entity.Course
import com.secureattend.common.entity.CourseEnrollment
import com.secureattend.common.entity.CourseEnrollmentId
import com.secureattend.common.entity.User
import com.secureattend.common.entity.UserRole
import com.secureattend.common.repository.CourseEnrollmentRepository
import com.secureattend.common.repository.CourseRepository
import com.secureattend.common.repository.UserRepository
import com.secureattend.config.SecureAttendProperties
import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Component

/**
 * Bootstrap default accounts and course on startup so development is seamless.
 */
@Component
class AdminBootstrap(
    private val props: SecureAttendProperties,
    private val userRepository: UserRepository,
    private val courseRepository: CourseRepository,
    private val courseEnrollmentRepository: CourseEnrollmentRepository,
    private val passwordEncoder: PasswordEncoder
) : ApplicationRunner {

    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments?) {
        // 1. Bootstrap Admin Users
        val adminEmails = listOf(
            props.admin.bootstrapEmail.takeIf { it.isNotBlank() } ?: "admin@secureattend.com",
            "rijuljain75@gmail.com"
        ).distinct()

        var primaryAdmin: User? = null
        for (email in adminEmails) {
            val existing = userRepository.findByEmail(email)
            if (existing == null) {
                val created = userRepository.save(
                    User(
                        email = email,
                        passwordHash = passwordEncoder.encode("Admin@1234"),
                        fullName = if (email.startsWith("rijul")) "Rijul Jain" else "System Admin",
                        role = UserRole.ADMIN
                    )
                )
                log.info("Bootstrap admin created: {} ({})", created.email, created.id)
                if (primaryAdmin == null) primaryAdmin = created
            } else {
                if (primaryAdmin == null) primaryAdmin = existing
            }
        }

        val adminId = primaryAdmin?.id ?: return

        // 2. Bootstrap Faculty Users
        val facultyUsers = listOf(
            "faculty@secureattend.com" to "Dr. Faculty",
            "bcgod@gmail.com" to "Faculty Instructor"
        )
        for ((email, name) in facultyUsers) {
            if (!userRepository.existsByEmail(email)) {
                val faculty = userRepository.save(
                    User(
                        email = email,
                        passwordHash = passwordEncoder.encode("Faculty@1234"),
                        fullName = name,
                        role = UserRole.FACULTY
                    )
                )
                log.info("Bootstrap faculty created: {} ({})", faculty.email, faculty.id)
            }
        }

        // 3. Bootstrap Course ADA (Code 100)
        val course = if (!courseRepository.existsByCode("100")) {
            val c = courseRepository.save(
                Course(
                    code = "100",
                    name = "ADA",
                    createdBy = adminId
                )
            )
            log.info("Bootstrap course created: {} - {} ({})", c.code, c.name, c.id)
            c
        } else {
            courseRepository.search("100", org.springframework.data.domain.PageRequest.of(0, 1)).content.firstOrNull()
        }

        // 4. Bootstrap Student & Enrollment
        val studentEmail = "student@secureattend.com"
        val student = userRepository.findByEmail(studentEmail) ?: userRepository.save(
            User(
                email = studentEmail,
                passwordHash = passwordEncoder.encode("Student@1234"),
                fullName = "Sample Student",
                role = UserRole.STUDENT
            )
        )

        if (course?.id != null && student.id != null) {
            val enrollmentId = CourseEnrollmentId(studentId = student.id, courseId = course.id)
            if (!courseEnrollmentRepository.existsById(enrollmentId)) {
                courseEnrollmentRepository.save(CourseEnrollment(id = enrollmentId))
                log.info("Student {} enrolled into course {}", student.email, course.code)
            }
        }
    }
}
