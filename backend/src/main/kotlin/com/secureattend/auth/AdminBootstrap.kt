package com.secureattend.auth

import com.secureattend.common.entity.User
import com.secureattend.common.entity.UserRole
import com.secureattend.common.repository.UserRepository
import com.secureattend.config.SecureAttendProperties
import org.slf4j.LoggerFactory
import org.springframework.boot.ApplicationArguments
import org.springframework.boot.ApplicationRunner
import org.springframework.security.crypto.password.PasswordEncoder
import org.springframework.stereotype.Component

/**
 * Bootstrap admin account from environment variables on startup.
 * Only creates if ADMIN_EMAIL and ADMIN_PASSWORD are set and no admin exists.
 */
@Component
class AdminBootstrap(
    private val props: SecureAttendProperties,
    private val userRepository: UserRepository,
    private val passwordEncoder: PasswordEncoder
) : ApplicationRunner {

    private val log = LoggerFactory.getLogger(javaClass)

    override fun run(args: ApplicationArguments?) {
        val email = props.admin.bootstrapEmail
        val password = props.admin.bootstrapPassword

        if (email.isBlank() || password.isBlank()) {
            log.debug("Admin bootstrap skipped: ADMIN_EMAIL or ADMIN_PASSWORD not set")
            return
        }

        if (userRepository.existsByEmail(email)) {
            log.debug("Admin bootstrap skipped: user {} already exists", email)
            return
        }

        val admin = userRepository.save(
            User(
                email = email,
                passwordHash = passwordEncoder.encode(password),
                fullName = "System Admin",
                role = UserRole.ADMIN
            )
        )

        log.info("Bootstrap admin created: {} (ID: {})", admin.email, admin.id)
    }
}
