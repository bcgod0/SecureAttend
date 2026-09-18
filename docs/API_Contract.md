# SecureAttend — API Contract

> Version 1.0 · Base URL: `http://{host}:8080/api`
> WebSocket: `ws://{host}:8080/ws` (STOMP)

All endpoints return JSON. Authenticated endpoints require `Authorization: Bearer <accessToken>`.

---

## Table of Contents

1. [Authentication](#1-authentication)
2. [Enrollment](#2-enrollment)
3. [Sessions](#3-sessions)
4. [Scan (Fusion Pipeline)](#4-scan-fusion-pipeline)
5. [Faculty Review](#5-faculty-review)
6. [Admin](#6-admin)
7. [WebSocket Channels](#7-websocket-channels)
8. [Error Response Format](#8-error-response-format)
9. [Enumerations](#9-enumerations)

---

## 1. Authentication

### `POST /api/auth/register`

Create a new user account.

**Request Body:**
```json
{
  "email": "student@university.edu",
  "password": "SecureP@ss1",
  "fullName": "Rijul Sharma",
  "role": "STUDENT"
}
```

**Validation:**
- `email`: valid email, unique
- `password`: min 8 chars, at least 1 uppercase, 1 digit, 1 special char
- `role`: one of `STUDENT`, `FACULTY` (admin accounts are bootstrapped, not self-registered)

**Response `201 Created`:**
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "student@university.edu",
  "fullName": "Rijul Sharma",
  "role": "STUDENT",
  "createdAt": "2026-09-18T10:15:30Z"
}
```

**Errors:** `409` if email already exists; `400` for validation failures.

---

### `POST /api/auth/login`

Authenticate and receive JWT tokens.

**Request Body:**
```json
{
  "email": "student@university.edu",
  "password": "SecureP@ss1"
}
```

**Response `200 OK`:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs...",
  "refreshToken": "eyJhbGciOiJIUzI1NiIs...",
  "tokenType": "Bearer",
  "expiresIn": 900,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "student@university.edu",
    "fullName": "Rijul Sharma",
    "role": "STUDENT"
  }
}
```

**Errors:** `401` invalid credentials.

---

### `POST /api/auth/refresh`

Refresh an expired access token.

**Request Body:**
```json
{
  "refreshToken": "eyJhbGciOiJIUzI1NiIs..."
}
```

**Response `200 OK`:**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiIs...",
  "expiresIn": 900
}
```

**Errors:** `401` if refresh token is invalid or expired.

---

## 2. Enrollment

All endpoints require `Authorization: Bearer <accessToken>` with role `STUDENT`.

### `POST /api/enrollment/face`

Enroll a face embedding. Accepts a face image, extracts the embedding via the ML service, stores the embedding, and **discards the raw image** (NFR-2).

**Request:** `multipart/form-data`
| Field | Type | Description |
|---|---|---|
| `faceImage` | `file` | JPEG/PNG face image |

**Response `201 Created`:**
```json
{
  "message": "Face embedding enrolled successfully",
  "enrolledAt": "2026-09-18T10:20:00Z"
}
```

**Errors:** `400` no face detected; `409` embedding already exists (re-enroll not allowed without admin reset); `503` ML service unavailable.

---

### `POST /api/enrollment/device`

Register the student's device fingerprint.

**Request Body:**
```json
{
  "fingerprintHash": "a1b2c3d4e5f6...",
  "deviceInfo": {
    "platform": "android",
    "model": "Pixel 8",
    "osVersion": "Android 15"
  }
}
```

**Response `201 Created`:**
```json
{
  "message": "Device registered successfully",
  "registeredAt": "2026-09-18T10:22:00Z"
}
```

**Errors:** `409` active device already exists (use `PUT` to replace).

---

### `PUT /api/enrollment/device`

Replace the currently registered device (controlled re-registration — FR-3). Deactivates the old device and registers the new one.

**Request Body:** Same as `POST`.

**Response `200 OK`:**
```json
{
  "message": "Device replaced successfully",
  "registeredAt": "2026-09-18T11:00:00Z"
}
```

---

### `GET /api/enrollment/status`

Check whether the student has completed all enrollment steps.

**Response `200 OK`:**
```json
{
  "faceEnrolled": true,
  "deviceRegistered": true,
  "enrollmentComplete": true
}
```

---

## 3. Sessions

### `POST /api/sessions`

Create a new attendance session. Requires `FACULTY` role.

**Request Body:**
```json
{
  "courseId": "course-uuid-here",
  "geofenceLat": 28.6139,
  "geofenceLon": 77.2090,
  "geofenceRadiusMeters": 100,
  "qrRotationSeconds": 10
}
```

**Validation:**
- `geofenceRadiusMeters`: 10–1000
- `qrRotationSeconds`: 5–60

**Response `201 Created`:**
```json
{
  "id": "session-uuid-here",
  "courseId": "course-uuid-here",
  "facultyId": "faculty-uuid-here",
  "geofenceLat": 28.6139,
  "geofenceLon": 77.2090,
  "geofenceRadiusMeters": 100,
  "qrRotationSeconds": 10,
  "status": "ACTIVE",
  "startedAt": "2026-09-18T10:30:00Z"
}
```

**Errors:** `400` validation; `404` course not found; `409` session already active for this course.

---

### `PATCH /api/sessions/{sessionId}/close`

Close an active session. No scans accepted after closure (FR-7). Requires `FACULTY` role and ownership of the session.

**Response `200 OK`:**
```json
{
  "id": "session-uuid-here",
  "status": "CLOSED",
  "closedAt": "2026-09-18T11:30:00Z"
}
```

**Errors:** `404` session not found; `409` session already closed.

---

### `GET /api/sessions/{sessionId}`

Get session details including live attendance count. Requires `FACULTY` role.

**Response `200 OK`:**
```json
{
  "id": "session-uuid-here",
  "courseId": "course-uuid-here",
  "courseName": "Data Structures",
  "courseCode": "CS201",
  "facultyId": "faculty-uuid-here",
  "geofenceLat": 28.6139,
  "geofenceLon": 77.2090,
  "geofenceRadiusMeters": 100,
  "qrRotationSeconds": 10,
  "status": "ACTIVE",
  "startedAt": "2026-09-18T10:30:00Z",
  "closedAt": null,
  "attendanceSummary": {
    "present": 32,
    "flagged": 3,
    "rejected": 1,
    "total": 36
  }
}
```

---

### `GET /api/sessions/{sessionId}/attendance`

List all scans for a session. Requires `FACULTY` role.

**Query Parameters:**
- `status` (optional): filter by `PRESENT`, `FLAGGED`, `REJECTED`
- `page` (default 0), `size` (default 50)

**Response `200 OK`:**
```json
{
  "content": [
    {
      "scanId": "scan-uuid",
      "studentId": "student-uuid",
      "studentName": "Rijul Sharma",
      "studentEmail": "student@university.edu",
      "finalStatus": "PRESENT",
      "submittedAt": "2026-09-18T10:35:12Z",
      "layerResults": [
        { "layer": "QR_VALIDATION", "passed": true, "detail": "Token valid" },
        { "layer": "DEVICE_MATCH", "passed": true, "detail": "Device matched" },
        { "layer": "GEOFENCE", "passed": true, "score": 45.2, "detail": "Within 45m of center (limit: 100m)" },
        { "layer": "FACE_VERIFICATION", "passed": true, "score": 0.82, "detail": "Similarity 0.82 (threshold: 0.55)" },
        { "layer": "ANOMALY", "passed": true, "score": 0.12, "detail": "Normal behavior" }
      ]
    }
  ],
  "totalElements": 36,
  "page": 0,
  "size": 50
}
```

---

### `GET /api/sessions`

List sessions for the authenticated faculty. Supports pagination and filtering.

**Query Parameters:**
- `courseId` (optional)
- `status` (optional): `ACTIVE` or `CLOSED`
- `page` (default 0), `size` (default 20)

**Response `200 OK`:**
```json
{
  "content": [
    {
      "id": "session-uuid",
      "courseCode": "CS201",
      "courseName": "Data Structures",
      "status": "ACTIVE",
      "startedAt": "2026-09-18T10:30:00Z",
      "attendanceCount": 36
    }
  ],
  "totalElements": 5,
  "page": 0,
  "size": 20
}
```

---

## 4. Scan (Fusion Pipeline)

### `POST /api/scan/verify`

The core attendance verification endpoint. Submits all four signals in a single request. Requires `STUDENT` role.

**Request:** `multipart/form-data`
| Field | Type | Description |
|---|---|---|
| `qrToken` | `string` | The scanned QR token string |
| `deviceFingerprint` | `string` | SHA-256 device fingerprint hash |
| `latitude` | `double` | GPS latitude |
| `longitude` | `double` | GPS longitude |
| `faceFrame` | `file` | JPEG face image captured at scan time |

**Response `200 OK`:**
```json
{
  "scanId": "scan-uuid",
  "sessionId": "session-uuid",
  "finalStatus": "PRESENT",
  "layerResults": [
    { "layer": "QR_VALIDATION", "passed": true, "detail": "Token valid, session CS201 active" },
    { "layer": "DEVICE_MATCH", "passed": true, "detail": "Device matched" },
    { "layer": "GEOFENCE", "passed": true, "score": 45.2, "detail": "Within 45m (limit: 100m)" },
    { "layer": "FACE_VERIFICATION", "passed": true, "score": 0.82, "detail": "Match confirmed (0.82 ≥ 0.55)" },
    { "layer": "ANOMALY", "passed": true, "score": 0.12, "detail": "Normal pattern" }
  ],
  "submittedAt": "2026-09-18T10:35:12Z"
}
```

**Status determination logic:**
- Any deterministic layer (QR, device, geofence) fails → `REJECTED`
- Face layer fails or ML unavailable → `FLAGGED` (NFR-7)
- Anomaly score > 0.7 → `FLAGGED`
- All pass → `PRESENT`

**Errors:**
- `400` missing/malformed fields
- `401` unauthenticated
- `403` not a student
- `409` already marked present for this session
- `410` session is closed (FR-7)

---

## 5. Faculty Review

### `GET /api/review/queue`

List flagged scans pending review. Requires `FACULTY` role.

**Query Parameters:**
- `sessionId` (optional): filter by session
- `page` (default 0), `size` (default 20)

**Response `200 OK`:**
```json
{
  "content": [
    {
      "reviewId": "review-uuid",
      "scanId": "scan-uuid",
      "sessionId": "session-uuid",
      "courseCode": "CS201",
      "studentId": "student-uuid",
      "studentName": "Test Student",
      "studentEmail": "test@university.edu",
      "flaggedReason": "Face similarity below threshold (0.42 < 0.55)",
      "flaggedAt": "2026-09-18T10:36:00Z",
      "layerResults": [
        { "layer": "QR_VALIDATION", "passed": true, "detail": "Token valid" },
        { "layer": "DEVICE_MATCH", "passed": true, "detail": "Device matched" },
        { "layer": "GEOFENCE", "passed": true, "score": 30.0, "detail": "Within 30m (limit: 100m)" },
        { "layer": "FACE_VERIFICATION", "passed": false, "score": 0.42, "detail": "Similarity 0.42 < threshold 0.55" },
        { "layer": "ANOMALY", "passed": true, "score": 0.15, "detail": "Normal pattern" }
      ]
    }
  ],
  "totalElements": 3,
  "page": 0,
  "size": 20
}
```

---

### `PATCH /api/review/{scanId}`

Approve or reject a flagged scan. Updates `scans.final_status` accordingly (FR-15). Requires `FACULTY` role.

**Request Body:**
```json
{
  "decision": "APPROVED",
  "notes": "Recognized the student — low similarity due to poor lighting"
}
```

**Response `200 OK`:**
```json
{
  "scanId": "scan-uuid",
  "previousStatus": "FLAGGED",
  "newStatus": "PRESENT",
  "reviewedBy": "faculty-uuid",
  "reviewedAt": "2026-09-18T11:00:00Z"
}
```

**Status mapping:** `APPROVED` → sets `scans.final_status = PRESENT`; `REJECTED` → sets `scans.final_status = REJECTED`.

**Errors:** `404` scan not found; `409` already reviewed.

---

## 6. Admin

All endpoints require `ADMIN` role.

### Courses

#### `POST /api/admin/courses`

**Request Body:**
```json
{
  "code": "CS201",
  "name": "Data Structures"
}
```

**Response `201 Created`:**
```json
{
  "id": "course-uuid",
  "code": "CS201",
  "name": "Data Structures",
  "createdAt": "2026-09-18T09:00:00Z"
}
```

#### `GET /api/admin/courses`

**Query Parameters:** `page`, `size`, `search` (optional, searches code + name)

**Response `200 OK`:** Paginated list of courses.

#### `PUT /api/admin/courses/{courseId}`

Update course details.

#### `DELETE /api/admin/courses/{courseId}`

Delete a course (cascade deletes enrollments and sessions).

---

### Course Enrollment (Students → Courses)

#### `POST /api/admin/courses/{courseId}/enroll`

Enroll students into a course.

**Request Body:**
```json
{
  "studentIds": ["student-uuid-1", "student-uuid-2"]
}
```

**Response `200 OK`:**
```json
{
  "enrolled": 2,
  "alreadyEnrolled": 0
}
```

#### `DELETE /api/admin/courses/{courseId}/enroll/{studentId}`

Remove a student from a course.

---

### Users

#### `GET /api/admin/users`

**Query Parameters:** `role` (optional), `search` (optional), `page`, `size`

**Response `200 OK`:** Paginated list of users (id, email, fullName, role, createdAt).

#### `GET /api/admin/users/{userId}`

User details including enrollment status (face/device).

#### `DELETE /api/admin/users/{userId}`

Deactivate a user account.

---

## 7. WebSocket Channels

### Connection

**Endpoint:** `ws://{host}:8080/ws`
**Protocol:** STOMP over WebSocket
**Authentication:** Connect with header `Authorization: Bearer <accessToken>`

### QR Token Broadcast

**Subscribe:** `/topic/session/{sessionId}/qr`

Faculty (Display Mode) subscribes to receive rotating QR tokens.

**Message payload (sent every `qrRotationSeconds`):**
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "expiresAt": 1726654230,
  "sequenceNumber": 42
}
```

### Live Attendance Feed

**Subscribe:** `/topic/session/{sessionId}/attendance`

Faculty subscribes to receive real-time scan results.

**Message payload (sent on each scan):**
```json
{
  "scanId": "scan-uuid",
  "studentName": "Rijul Sharma",
  "finalStatus": "PRESENT",
  "submittedAt": "2026-09-18T10:35:12Z"
}
```

---

## 8. Error Response Format

All errors follow a consistent structure:

```json
{
  "error": "VALIDATION_ERROR",
  "message": "Email is already registered",
  "status": 409,
  "timestamp": "2026-09-18T10:15:30Z",
  "path": "/api/auth/register",
  "details": {
    "field": "email",
    "rejected": "student@university.edu"
  }
}
```

### Standard Error Codes

| HTTP Status | Error Code | Description |
|---|---|---|
| 400 | `VALIDATION_ERROR` | Invalid request body or parameters |
| 401 | `UNAUTHORIZED` | Missing or invalid JWT |
| 403 | `FORBIDDEN` | Insufficient role |
| 404 | `NOT_FOUND` | Resource not found |
| 409 | `CONFLICT` | Resource already exists or state conflict |
| 410 | `GONE` | Session closed, no longer accepting scans |
| 503 | `SERVICE_UNAVAILABLE` | ML service unreachable |

---

## 9. Enumerations

| Enum | Values | Used In |
|---|---|---|
| `UserRole` | `STUDENT`, `FACULTY`, `ADMIN` | Registration, JWT claims |
| `SessionStatus` | `ACTIVE`, `CLOSED` | Session lifecycle |
| `ScanStatus` | `PRESENT`, `FLAGGED`, `REJECTED` | Scan results |
| `ReviewDecision` | `APPROVED`, `REJECTED` | Faculty review |
| `LayerName` | `QR_VALIDATION`, `DEVICE_MATCH`, `GEOFENCE`, `FACE_VERIFICATION`, `ANOMALY` | Scan layer audit |
