package com.secureattend.common.exception

import org.slf4j.LoggerFactory
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.MethodArgumentNotValidException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.context.request.WebRequest
import java.time.Instant

@RestControllerAdvice
class GlobalExceptionHandler {

    private val log = LoggerFactory.getLogger(javaClass)

    data class ErrorResponse(
        val error: String,
        val message: String,
        val status: Int,
        val timestamp: Instant = Instant.now(),
        val path: String? = null,
        val details: Map<String, Any?>? = null
    )

    @ExceptionHandler(SecureAttendException::class)
    fun handleSecureAttendException(
        ex: SecureAttendException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        log.warn("Business error: [{}] {}", ex.errorCode, ex.message)
        return ResponseEntity
            .status(ex.httpStatus)
            .body(
                ErrorResponse(
                    error = ex.errorCode,
                    message = ex.message,
                    status = ex.httpStatus.value(),
                    path = request.getDescription(false).removePrefix("uri="),
                    details = ex.details
                )
            )
    }

    @ExceptionHandler(MethodArgumentNotValidException::class)
    fun handleValidation(
        ex: MethodArgumentNotValidException,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        val errors = ex.bindingResult.fieldErrors.associate { it.field to it.defaultMessage }
        return ResponseEntity
            .status(HttpStatus.BAD_REQUEST)
            .body(
                ErrorResponse(
                    error = "VALIDATION_ERROR",
                    message = "Request validation failed",
                    status = 400,
                    path = request.getDescription(false).removePrefix("uri="),
                    details = errors
                )
            )
    }

    @ExceptionHandler(Exception::class)
    fun handleGeneric(
        ex: Exception,
        request: WebRequest
    ): ResponseEntity<ErrorResponse> {
        log.error("Unhandled exception", ex)
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(
                ErrorResponse(
                    error = "INTERNAL_ERROR",
                    message = "An unexpected error occurred",
                    status = 500,
                    path = request.getDescription(false).removePrefix("uri=")
                )
            )
    }
}
