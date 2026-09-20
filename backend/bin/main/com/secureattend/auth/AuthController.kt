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
    @field:NotBlank @field:Size(min = 8) val password: String,
    @field:NotBlank val fullName: String,
    val role: UserRole = UserRole.STUDENT
)

data class LoginRequest(
    @field:Email @field:NotBlank val email: String,
    @field:NotBlank val password: String
)

data class RefreshRequest(
    @field:NotBlank val refreshToken: String
)

data class UserResponse(
    val id: UUID,
    val email: String,
    val fullName: String,
    val role: UserRole,
    val status: UserStatus,
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
        if (userRepository.existsByEmail(normalizedEmail)) {
            throw ResourceAlreadyExistsException("User", normalizedEmail)
        }

        // Admins cannot self-register
        if (request.role == UserRole.ADMIN) {
            throw com.secureattend.common.exception.ValidationException("role", "Admin accounts cannot be self-registered")
        }

        val user = userRepository.save(
            User(
                email = normalizedEmail,
                passwordHash = passwordEncoder.encode(request.password),
                fullName = request.fullName.trim(),
                role = request.role
            )
        )

        log.info("User registered: {} with role {}", user.email, user.role)
        return user.toResponse()
    }

    @PostMapping("/login")
    fun login(@Valid @RequestBody request: LoginRequest): LoginResponse {
        val normalizedEmail = request.email.trim().lowercase()
        val user = userRepository.findByEmail(normalizedEmail)
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
        fullName = fullName,
        role = role,
        status = status,
        createdAt = createdAt
    )
}
