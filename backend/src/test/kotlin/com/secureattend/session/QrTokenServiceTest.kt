package com.secureattend.session

import com.secureattend.common.entity.Course
import com.secureattend.common.entity.Session
import com.secureattend.common.entity.SessionStatus
import com.secureattend.common.repository.SessionRepository
import com.secureattend.config.QrProperties
import com.secureattend.config.SecureAttendProperties
import io.mockk.every
import io.mockk.mockk
import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.springframework.messaging.simp.SimpMessagingTemplate
import java.util.UUID

class QrTokenServiceTest {

    private val props = SecureAttendProperties(
        qr = QrProperties(
            hmacSecret = "test-qr-hmac-secret-change-in-prod-min-32-chars!!",
            defaultRotationSeconds = 15
        )
    )
    private val messagingTemplate = mockk<SimpMessagingTemplate>(relaxed = true)
    private val sessionRepository = mockk<SessionRepository>(relaxed = true)
    private lateinit var qrTokenService: QrTokenService

    private val sessionId = UUID.randomUUID()
    private val facultyId = UUID.randomUUID()
    private val courseId = UUID.randomUUID()
    private val student1Id = UUID.randomUUID()
    private val student2Id = UUID.randomUUID()

    private lateinit var activeSession: Session

    @BeforeEach
    fun setUp() {
        qrTokenService = QrTokenService(props, messagingTemplate, sessionRepository)

        activeSession = Session(
            id = sessionId,
            courseId = courseId,
            facultyId = facultyId,
            geofenceLat = 28.5355,
            geofenceLon = 77.3910,
            geofenceRadiusMeters = 50,
            qrRotationSeconds = 15,
            status = SessionStatus.ACTIVE
        )
        qrTokenService.startRotation(activeSession)
    }

    @Test
    fun `generateToken and validateToken succeed for fresh token`() {
        val token = qrTokenService.generateToken(sessionId)
        assertNotNull(token)
        assertTrue(token.isNotEmpty())

        val validatedSessionId = qrTokenService.validateToken(token, student1Id)
        assertEquals(sessionId, validatedSessionId)
    }

    @Test
    fun `replay protection blocks second scan by same student on same token`() {
        val token = qrTokenService.generateToken(sessionId)

        // First scan succeeds
        val firstResult = qrTokenService.validateToken(token, student1Id)
        assertEquals(sessionId, firstResult)

        // Replay scan by same student with same token is rejected
        val secondResult = qrTokenService.validateToken(token, student1Id)
        assertNull(secondResult, "Replay scan by same student should be rejected")
    }

    @Test
    fun `different students can scan the same token nonce once each`() {
        val token = qrTokenService.generateToken(sessionId)

        val student1Result = qrTokenService.validateToken(token, student1Id)
        assertEquals(sessionId, student1Result)

        val student2Result = qrTokenService.validateToken(token, student2Id)
        assertEquals(sessionId, student2Result)
    }

    @Test
    fun `validateToken returns null when session rotation has stopped`() {
        val token = qrTokenService.generateToken(sessionId)
        qrTokenService.stopRotation(sessionId)

        val result = qrTokenService.validateToken(token, student1Id)
        assertNull(result, "Token should be invalid once session rotation is stopped")
    }

    @Test
    fun `validateToken returns null for tampered token`() {
        val token = qrTokenService.generateToken(sessionId)
        val tamperedToken = token.dropLast(4) + "abcd"

        val result = qrTokenService.validateToken(tamperedToken, student1Id)
        assertNull(result, "Tampered token signature should fail validation")
    }

    @Test
    fun `getCurrentToken caches token within rotation interval`() {
        val token1 = qrTokenService.getCurrentToken(sessionId)
        val token2 = qrTokenService.getCurrentToken(sessionId)

        assertEquals(token1, token2, "Token should be cached during rotation interval")
    }
}
