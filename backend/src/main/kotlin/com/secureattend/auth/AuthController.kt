package com.secureattend.auth

import com.secureattend.common.entity.User
import com.secureattend.common.entity.UserRole
import com.secureattend.common.entity.UserStatus
import com.secureattend.common.exception.AccountPendingException
import com.secureattend.common.exception.InvalidCredentialsException
import com.secureattend.common.exception.ResourceAlreadyExistsException
import com.secureattend.common.exception.ResourceNotFoundException
import com.secureattend.common.repository.UserRepository
import jakarta.validation.Valid
import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.web.bind.annotation.*
import java.time.Instant
import java.util.UUID

// ---- DTOs ----

data class RegisterRequest(
    @field:Email @field:NotBlank val email: String,
    @field:NotBlank @field:Size(min = 3, max = 30) val username: String,
    @field:NotBlank @field:Size(min = 8) val password: String,
    @field:NotBlank val fullName: String,
    val role: UserRole = UserRole.STUDENT,
    val branch: String? = null,
    val section: String? = null,
    val rollNo: String? = null,
    val fatherName: String? = null
)

data class LoginRequest(
    @field:NotBlank val email: String, // Accepts email OR username
    @field:NotBlank val password: String
)

data class RefreshRequest(
    @field:NotBlank val refreshToken: String
)

data class UserResponse(
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
    val createdAt: Instant
)

data class LoginResponse(
    val accessToken: String,
    val refreshToken: String,
    val tokenType: String = "Bearer",
    val expiresIn: Long,
    val user: UserResponse
)

data class RefreshResponse(
    val accessToken: String,
    val expiresIn: Long
)

// ---- Controller ----

@RestController
@RequestMapping("/api/auth")
class AuthController(
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder,
    private val jwtService: JwtService
) {
    private val log = LoggerFactory.getLogger(javaClass)

    @PostMapping("/register")
    @ResponseStatus(HttpStatus.CREATED)
    fun register(@Valid @RequestBody request: RegisterRequest): UserResponse {
        val normalizedEmail = request.email.trim().lowercase()
        val normalizedUsername = request.username.trim().lowercase()

        // Email domain validation: must end with @kiet.edu
        if (!normalizedEmail.endsWith("@kiet.edu")) {
            throw com.secureattend.common.exception.ValidationException("email", "Email must end with @kiet.edu")
        }

        // Email uniqueness
        if (userRepository.existsByEmail(normalizedEmail)) {
            throw ResourceAlreadyExistsException("User", normalizedEmail)
        }

        // Username format and uniqueness
        if (!normalizedUsername.matches(Regex("^[a-zA-Z0-9_]{3,30}$"))) {
            throw com.secureattend.common.exception.ValidationException(
                "username",
                "Username must be 3-30 characters long and contain only letters, numbers, and underscores"
            )
        }
        if (userRepository.existsByUsername(normalizedUsername)) {
            throw ResourceAlreadyExistsException("Username", normalizedUsername)
        }

        // Admins cannot self-register
        if (request.role == UserRole.ADMIN) {
            throw com.secureattend.common.exception.ValidationException("role", "Admin accounts cannot be self-registered")
        }

        // Role-specific field validation
        if (request.fatherName.isNullOrBlank()) {
            throw com.secureattend.common.exception.ValidationException("fatherName", "Father's name is required")
        }
        if (request.branch.isNullOrBlank()) {
            throw com.secureattend.common.exception.ValidationException("branch", "Branch is required")
        }
        if (request.role == UserRole.STUDENT) {
            if (request.section.isNullOrBlank()) {
                throw com.secureattend.common.exception.ValidationException("section", "Section is required for students")
            }
            if (request.rollNo.isNullOrBlank()) {
                throw com.secureattend.common.exception.ValidationException("rollNo", "Roll number is required for students")
            }
            if (!request.rollNo.trim().matches(Regex("^[0-9]+$"))) {
                throw com.secureattend.common.exception.ValidationException("rollNo", "Roll number must be numerical only")
            }
        }

        val user = userRepository.save(
            User(
                email = normalizedEmail,
                username = normalizedUsername,
                passwordHash = passwordEncoder.encode(request.password),
                fullName = request.fullName.trim(),
                role = request.role,
                branch = request.branch?.trim(),
                section = request.section?.trim(),
                rollNo = request.rollNo?.trim(),
                fatherName = request.fatherName?.trim()
            )
        )

        log.info("User registered: {} (username: {}) with role {}", user.email, user.username, user.role)
        return user.toResponse()
    }

    @PostMapping("/login")
    fun login(@Valid @RequestBody request: LoginRequest): LoginResponse {
        val identifier = request.email.trim().lowercase()
        val user = (if (identifier.contains("@")) {
            userRepository.findByEmail(identifier)
        } else {
            userRepository.findByUsername(identifier)
        }) ?: userRepository.findByEmail(identifier)
           ?: userRepository.findByUsername(identifier)
           ?: throw InvalidCredentialsException()

        if (!passwordEncoder.matches(request.password, user.passwordHash)) {
            throw InvalidCredentialsException()
        }

        // Block login for pending accounts
        if (user.status == UserStatus.PENDING) {
            throw AccountPendingException()
        }

        val accessToken = jwtService.generateAccessToken(user.id!!, user.email, user.role)
        val refreshToken = jwtService.generateRefreshToken(user.id)

        log.info("User logged in: {} ({})", user.email, user.role)
        return LoginResponse(
            accessToken = accessToken,
            refreshToken = refreshToken,
            expiresIn = 900, // 15 min in seconds
            user = user.toResponse()
        )
    }

    @PostMapping("/refresh")
    fun refresh(@Valid @RequestBody request: RefreshRequest): RefreshResponse {
        val claims = jwtService.validateToken(request.refreshToken)
            ?: throw InvalidCredentialsException()

        if (!jwtService.isRefreshToken(claims)) {
            throw InvalidCredentialsException()
        }

        val userId = UUID.fromString(claims.subject)
        val user = userRepository.findById(userId)
            .orElseThrow { ResourceNotFoundException("User", userId.toString()) }

        val newAccessToken = jwtService.generateAccessToken(user.id!!, user.email, user.role)

        return RefreshResponse(
            accessToken = newAccessToken,
            expiresIn = 900
        )
    }

    private fun User.toResponse() = UserResponse(
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
        createdAt = createdAt
    )
}
