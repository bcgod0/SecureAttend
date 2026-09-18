package com.secureattend.common.exception

import org.springframework.http.HttpStatus

/**
 * Base exception for all SecureAttend business logic errors.
 * Provides structured error responses via the global exception handler.
 */
open class SecureAttendException(
    val errorCode: String,
    override val message: String,
    val httpStatus: HttpStatus,
    val details: Map<String, Any?>? = null
) : RuntimeException(message)

class ResourceNotFoundException(
    resource: String,
    identifier: String
) : SecureAttendException(
    errorCode = "NOT_FOUND",
    message = "$resource not found: $identifier",
    httpStatus = HttpStatus.NOT_FOUND
)

class ResourceAlreadyExistsException(
    resource: String,
    identifier: String
) : SecureAttendException(
    errorCode = "CONFLICT",
    message = "$resource already exists: $identifier",
    httpStatus = HttpStatus.CONFLICT
)

class InvalidCredentialsException : SecureAttendException(
    errorCode = "UNAUTHORIZED",
    message = "Invalid email or password",
    httpStatus = HttpStatus.UNAUTHORIZED
)

class SessionClosedException(sessionId: String) : SecureAttendException(
    errorCode = "GONE",
    message = "Session $sessionId is closed and no longer accepting scans",
    httpStatus = HttpStatus.GONE
)

class AlreadyAttendedException(sessionId: String) : SecureAttendException(
    errorCode = "CONFLICT",
    message = "Already marked as present/flagged for session $sessionId",
    httpStatus = HttpStatus.CONFLICT
)

class MlServiceUnavailableException : SecureAttendException(
    errorCode = "SERVICE_UNAVAILABLE",
    message = "ML verification service is currently unavailable",
    httpStatus = HttpStatus.SERVICE_UNAVAILABLE
)

class ValidationException(
    field: String,
    reason: String
) : SecureAttendException(
    errorCode = "VALIDATION_ERROR",
    message = "$field: $reason",
    httpStatus = HttpStatus.BAD_REQUEST,
    details = mapOf("field" to field, "reason" to reason)
)
