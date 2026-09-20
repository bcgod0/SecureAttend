package com.secureattend.auth

import com.secureattend.common.entity.UserRole
import com.secureattend.config.SecureAttendProperties
import io.jsonwebtoken.Claims
import io.jsonwebtoken.ExpiredJwtException
import io.jsonwebtoken.Jwts
import io.jsonwebtoken.security.Keys
import org.slf4j.LoggerFactory
import org.springframework.stereotype.Service
import java.util.*
import javax.crypto.SecretKey

@Service
class JwtService(private val props: SecureAttendProperties) {

    private val log = LoggerFactory.getLogger(javaClass)

    private val signingKey: SecretKey by lazy {
        Keys.hmacShaKeyFor(props.jwt.secret.toByteArray())
    }

    /**
     * Generate an access token with user claims.
     */
    fun generateAccessToken(userId: UUID, email: String, role: UserRole): String {
        val now = Date()
        val expiry = Date(now.time + props.jwt.accessTokenExpiryMinutes * 60 * 1000)

        return Jwts.builder()
            .subject(userId.toString())
            .claim("email", email)
            .claim("role", role.name)
            .issuedAt(now)
            .expiration(expiry)
            .signWith(signingKey)
            .compact()
    }

    /**
     * Generate a refresh token (longer-lived, minimal claims).
     */
    fun generateRefreshToken(userId: UUID): String {
        val now = Date()
        val expiry = Date(now.time + props.jwt.refreshTokenExpiryDays * 24 * 60 * 60 * 1000)

        return Jwts.builder()
            .subject(userId.toString())
            .claim("type", "refresh")
            .issuedAt(now)
            .expiration(expiry)
            .signWith(signingKey)
            .compact()
    }

    /**
     * Parse and validate a JWT token. Returns null if invalid or expired.
     */
    fun validateToken(token: String): Claims? {
        return try {
            Jwts.parser()
                .verifyWith(signingKey)
                .build()
                .parseSignedClaims(token)
                .payload
        } catch (ex: ExpiredJwtException) {
            log.debug("JWT expired for subject: {}", ex.claims?.subject)
            null
        } catch (ex: Exception) {
            log.debug("JWT validation failed: {}", ex.message)
            null
        }
    }

    fun getUserIdFromToken(token: String): UUID? {
        return validateToken(token)?.subject?.let { UUID.fromString(it) }
    }

    fun getRoleFromToken(token: String): UserRole? {
        return validateToken(token)?.get("role", String::class.java)?.let { UserRole.valueOf(it) }
    }

    fun isRefreshToken(claims: Claims): Boolean {
        return claims.get("type", String::class.java) == "refresh"
    }
}
