package com.secureattend.session

import com.secureattend.common.entity.Session
import com.secureattend.common.entity.SessionStatus
import com.secureattend.common.repository.SessionRepository
import com.secureattend.config.SecureAttendProperties
import io.jsonwebtoken.Jwts
import io.jsonwebtoken.security.Keys
import org.slf4j.LoggerFactory
import org.springframework.messaging.simp.SimpMessagingTemplate
import org.springframework.scheduling.annotation.Scheduled
import org.springframework.stereotype.Service
import java.security.SecureRandom
import java.time.Instant
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.SecretKey

/**
 * FR-5: Generates cryptographically signed QR tokens on a fixed rotation interval.
 * FR-6: Broadcasts tokens via WebSocket/STOMP to Display Mode clients.
 * NFR-3: Tokens are HMAC-signed; reject if expired, replayed, or tampered.
 */
@Service
class QrTokenService(
    private val props: SecureAttendProperties,
    private val messagingTemplate: SimpMessagingTemplate,
    private val sessionRepository: SessionRepository
) {
    private val log = LoggerFactory.getLogger(javaClass)
    private val random = SecureRandom()

    private val hmacKey: SecretKey by lazy {
        Keys.hmacShaKeyFor(props.qr.hmacSecret.toByteArray())
    }

    // Active session rotations: sessionId → (rotation interval seconds, sequence counter, currentToken, tokenGeneratedAt)
    data class RotationState(
        val rotationSeconds: Int,
        var sequenceNumber: Long = 0,
        var currentToken: String = "",
        var tokenGeneratedAt: Long = 0
    )
    private val activeRotations = ConcurrentHashMap<UUID, RotationState>()

    // Consumed tokens for replay protection: sessionId → set of (nonce, studentId)
    val consumedTokens = ConcurrentHashMap<UUID, MutableSet<String>>()

    fun startRotation(session: Session) {
        val state = RotationState(session.qrRotationSeconds)
        activeRotations[session.id!!] = state
        consumedTokens[session.id] = ConcurrentHashMap.newKeySet()
        log.info("QR rotation started for session {} (every {}s)", session.id, session.qrRotationSeconds)
    }

    fun stopRotation(sessionId: UUID) {
        activeRotations.remove(sessionId)
        consumedTokens.remove(sessionId)
        log.info("QR rotation stopped for session {}", sessionId)
    }

    /**
     * Generate an HMAC-signed QR token for a specific session and caches it.
     */
    fun generateToken(sessionId: UUID): String {
        val nonce = ByteArray(8).also { random.nextBytes(it) }.joinToString("") { "%02x".format(it) }
        val now = Instant.now()
        val rotationState = activeRotations[sessionId] ?: return ""
        val expiresAt = now.plusSeconds(rotationState.rotationSeconds.toLong() + 5) // 5s grace

        val token = Jwts.builder()
            .claim("sid", sessionId.toString())
            .claim("nonce", nonce)
            .issuedAt(Date.from(now))
            .expiration(Date.from(expiresAt))
            .signWith(hmacKey)
            .compact()

        rotationState.currentToken = token
        rotationState.tokenGeneratedAt = System.currentTimeMillis()
        return token
    }

    /**
     * Return current cached token if still within rotation interval, or generate a fresh one.
     */
    fun getCurrentToken(sessionId: UUID): String {
        val state = activeRotations[sessionId] ?: return ""
        val now = System.currentTimeMillis()
        if (state.currentToken.isNotEmpty() && (now - state.tokenGeneratedAt < state.rotationSeconds * 1000L)) {
            return state.currentToken
        }
        return generateToken(sessionId)
    }

    /**
     * Validate a scanned QR token. Returns the session ID if valid, null otherwise.
     * Checks: signature integrity, expiry, replay.
     */
    fun validateToken(token: String, studentId: UUID): UUID? {
        return try {
            val claims = Jwts.parser()
                .verifyWith(hmacKey)
                .build()
                .parseSignedClaims(token)
                .payload

            val sessionId = UUID.fromString(claims.get("sid", String::class.java))
            val nonce = claims.get("nonce", String::class.java)

            // Check if session is active
            if (!activeRotations.containsKey(sessionId)) {
                log.debug("QR token rejected: session {} not active", sessionId)
                return null
            }

            // Replay protection: nonce + studentId pair must be unique
            val replayKey = "${nonce}:${studentId}"
            val tokenSet = consumedTokens[sessionId] ?: return null
            if (!tokenSet.add(replayKey)) {
                log.debug("QR token rejected: replay detected for {} in session {}", studentId, sessionId)
                return null
            }

            sessionId
        } catch (ex: Exception) {
            log.debug("QR token validation failed: {}", ex.message)
            null
        }
    }

    /**
     * Scheduled task: rotates QR tokens for all active sessions and broadcasts via WebSocket.
     * Runs every second, but only generates new tokens when each session's rotation interval has elapsed.
     */
    @Scheduled(fixedRate = 1000)
    fun rotateTokens() {
        val now = System.currentTimeMillis()
        activeRotations.forEach { (sessionId, state) ->
            val intervalMs = state.rotationSeconds * 1000L
            // Generate a new token when rotation interval has elapsed or sequenceNumber is 0
            if (state.tokenGeneratedAt == 0L || (now - state.tokenGeneratedAt >= intervalMs)) {
                state.sequenceNumber++
                val token = generateToken(sessionId)

                if (token.isNotEmpty()) {
                    val payload = mapOf(
                        "token" to token,
                        "rotationSeconds" to state.rotationSeconds,
                        "expiresAt" to (System.currentTimeMillis() / 1000 + state.rotationSeconds + 5),
                        "sequenceNumber" to state.sequenceNumber
                    )

                    messagingTemplate.convertAndSend("/topic/session/$sessionId/qr", payload)
                }
            }
        }
    }

    /**
     * On startup, re-activate rotations for any sessions that are still ACTIVE.
     */
    @jakarta.annotation.PostConstruct
    fun restoreActiveRotations() {
        sessionRepository.findByStatus(SessionStatus.ACTIVE).forEach { session ->
            startRotation(session)
            log.info("Restored QR rotation for active session {}", session.id)
        }
    }
}
