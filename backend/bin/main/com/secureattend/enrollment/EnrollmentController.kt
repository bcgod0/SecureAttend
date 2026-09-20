package com.secureattend.enrollment

import com.secureattend.common.entity.DeviceRegistration
import com.secureattend.common.entity.FaceEmbedding
import com.secureattend.common.exception.MlServiceUnavailableException
import com.secureattend.common.exception.ResourceAlreadyExistsException
import com.secureattend.common.exception.ValidationException
import com.secureattend.common.repository.DeviceRegistrationRepository
import com.secureattend.common.repository.FaceEmbeddingRepository
import com.secureattend.config.SecureAttendProperties
import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.web.bind.annotation.*
import org.springframework.web.multipart.MultipartFile
import org.springframework.web.reactive.function.BodyInserters
import org.springframework.web.reactive.function.client.WebClient
import org.springframework.web.reactive.function.client.WebClientResponseException
import java.time.Duration
import java.time.Instant
import java.util.UUID

// ---- DTOs ----

data class DeviceRegisterRequest(
    val fingerprintHash: String,
    val deviceInfo: Map<String, String>? = null
)

data class EnrollmentStatusResponse(
    val faceEnrolled: Boolean,
    val deviceRegistered: Boolean,
    val enrollmentComplete: Boolean
)

data class MlEmbeddingResponse(
    val embedding: List<Double>
)

// ---- Controller ----

@RestController
@RequestMapping("/api/enrollment")
class EnrollmentController(
    private val faceEmbeddingRepository: FaceEmbeddingRepository,
    private val deviceRegistrationRepository: DeviceRegistrationRepository,
    private val mlServiceWebClient: WebClient,
    private val props: SecureAttendProperties
) {
    private val log = LoggerFactory.getLogger(javaClass)

    private fun currentUserId(): UUID =
        UUID.fromString(SecurityContextHolder.getContext().authentication.principal as String)

    /**
     * FR-2: Enroll face embedding. Raw image is never persisted.
     */
    @PostMapping("/face", consumes = [MediaType.MULTIPART_FORM_DATA_VALUE])
    @ResponseStatus(HttpStatus.CREATED)
    fun enrollFace(@RequestParam("faceImage") faceImage: MultipartFile): Map<String, Any> {
        val studentId = currentUserId()

        if (faceEmbeddingRepository.existsByStudentId(studentId)) {
            throw ResourceAlreadyExistsException("Face embedding", studentId.toString())
        }

        if (faceImage.isEmpty) {
            throw ValidationException("faceImage", "Face image is required")
        }

        // Call ML service to extract embedding — raw image bytes only in memory
        val embeddingFloats = try {
            mlServiceWebClient.post()
                .uri("/api/face/embed")
                .contentType(MediaType.MULTIPART_FORM_DATA)
                .body(BodyInserters.fromMultipartData("face_frame", faceImage.resource))
                .retrieve()
                .bodyToMono(MlEmbeddingResponse::class.java)
                .timeout(Duration.ofSeconds(props.mlService.timeoutSeconds))
                .block()
                ?.embedding
                ?: throw MlServiceUnavailableException()
        } catch (ex: WebClientResponseException) {
            log.error("ML service error during face enrollment: {}", ex.message)
            throw if (ex.statusCode.value() == 400) {
                ValidationException("faceImage", "No face detected in the image")
            } else {
                MlServiceUnavailableException()
            }
        } catch (ex: MlServiceUnavailableException) {
            throw ex
        } catch (ex: Exception) {
            log.error("ML service unreachable during face enrollment", ex)
            throw MlServiceUnavailableException()
        }

        // Convert floats to byte array (512 x 4 bytes = 2048 bytes)
        val embeddingBytes = embeddingFloats.flatMap { value ->
            val bits = java.lang.Float.floatToIntBits(value.toFloat())
            listOf(
                (bits shr 24 and 0xFF).toByte(),
                (bits shr 16 and 0xFF).toByte(),
                (bits shr 8 and 0xFF).toByte(),
                (bits and 0xFF).toByte()
            )
        }.toByteArray()

        faceEmbeddingRepository.save(
            FaceEmbedding(
                studentId = studentId,
                embedding = embeddingBytes
            )
        )

        log.info("Face embedding enrolled for student {}", studentId)
        // NFR-2: raw image bytes are garbage collected — never written to disk
        return mapOf("message" to "Face embedding enrolled successfully", "enrolledAt" to Instant.now())
    }

    /**
     * FR-3: Register device fingerprint.
     */
    @PostMapping("/device")
    @ResponseStatus(HttpStatus.CREATED)
    fun registerDevice(@RequestBody request: DeviceRegisterRequest): Map<String, Any> {
        val studentId = currentUserId()

        if (deviceRegistrationRepository.existsByStudentIdAndIsActiveTrue(studentId)) {
            throw ResourceAlreadyExistsException("Device", studentId.toString())
        }

        val deviceInfoJson = request.deviceInfo?.let {
            com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(it)
        }

        deviceRegistrationRepository.save(
            DeviceRegistration(
                studentId = studentId,
                fingerprintHash = request.fingerprintHash,
                deviceInfo = deviceInfoJson
            )
        )

        log.info("Device registered for student {}", studentId)
        return mapOf("message" to "Device registered successfully", "registeredAt" to Instant.now())
    }

    /**
     * FR-3: Replace device (controlled re-registration).
     */
    @PutMapping("/device")
    fun replaceDevice(@RequestBody request: DeviceRegisterRequest): Map<String, Any> {
        val studentId = currentUserId()

        // Deactivate current device
        deviceRegistrationRepository.findByStudentIdAndIsActiveTrue(studentId)?.let { current ->
            current.isActive = false
            current.deactivatedAt = Instant.now()
            deviceRegistrationRepository.save(current)
            log.info("Deactivated device {} for student {}", current.id, studentId)
        }

        val deviceInfoJson = request.deviceInfo?.let {
            com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(it)
        }

        deviceRegistrationRepository.save(
            DeviceRegistration(
                studentId = studentId,
                fingerprintHash = request.fingerprintHash,
                deviceInfo = deviceInfoJson
            )
        )

        log.info("Device replaced for student {}", studentId)
        return mapOf("message" to "Device replaced successfully", "registeredAt" to Instant.now())
    }

    /**
     * Check enrollment completeness.
     */
    @GetMapping("/status")
    fun getStatus(): EnrollmentStatusResponse {
        val studentId = currentUserId()
        val faceEnrolled = faceEmbeddingRepository.existsByStudentId(studentId)
        val deviceRegistered = deviceRegistrationRepository.existsByStudentIdAndIsActiveTrue(studentId)

        return EnrollmentStatusResponse(
            faceEnrolled = faceEnrolled,
            deviceRegistered = deviceRegistered,
            enrollmentComplete = faceEnrolled && deviceRegistered
        )
    }
}
