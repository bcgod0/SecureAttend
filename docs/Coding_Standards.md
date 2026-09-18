# SecureAttend — Coding Standards

## 1. Naming Conventions

| Context | Convention | Example |
|---|---|---|
| **Kotlin** classes | PascalCase | `FusionPipeline`, `QrTokenService` |
| **Kotlin** functions/properties | camelCase | `validateToken()`, `geofenceLat` |
| **Kotlin** constants | UPPER_SNAKE | `EARTH_RADIUS_METERS`, `LAYER_QR_VALIDATION` |
| **Python** modules | snake_case | `face_service.py`, `anomaly_router.py` |
| **Python** classes | PascalCase | `FaceService`, `AnomalyService` |
| **Python** functions/variables | snake_case | `extract_embedding()`, `anomaly_score` |
| **Dart** classes | PascalCase | `ScanScreen`, `ApiClient` |
| **Dart** functions/variables | camelCase | `handleLogin()`, `isLoading` |
| **Dart** constants | camelCase or UPPER_SNAKE | `primaryColor`, `baseUrl` |
| **SQL** tables | snake_case, plural | `scan_layer_results`, `course_enrollments` |
| **SQL** columns | snake_case | `student_id`, `fingerprint_hash` |
| **REST endpoints** | kebab-case nouns | `/api/scan/verify`, `/api/enrollment/face` |

## 2. Error Handling

### Backend (Kotlin/Spring Boot)
- Use the `SecureAttendException` hierarchy (defined in `common/exception/Exceptions.kt`)
- All business exceptions are caught by `GlobalExceptionHandler` and returned as structured JSON:
  ```json
  { "error": "ERROR_CODE", "message": "...", "status": 400, "timestamp": "...", "path": "..." }
  ```
- **Never** let raw stack traces reach the client
- Log all exceptions at appropriate levels: `WARN` for business errors, `ERROR` for unexpected failures

### ML Service (Python/FastAPI)
- Use FastAPI's `HTTPException` for client errors (400, 404)
- Use try/except blocks around model inference with fallback to safe defaults
- Log all errors with `logging.error()` including the student context

### Client (Flutter/Dart)
- Wrap all API calls in try/catch
- Surface user-friendly error messages via `SnackBar`
- Never expose raw error details or stack traces in the UI

## 3. Logging Conventions

### Scan Pipeline Audit Logging (Critical — NFR-6)

Every layer in the fusion pipeline MUST log with this format:
```
[SCAN:{scanId}] [LAYER:{layerName}] result={PASS|FAIL} detail={...} student={studentId}
```

Example:
```
[SCAN:abc-123] [LAYER:QR_VALIDATION] result=PASS detail="Token valid, session CS201" student=def-456
[SCAN:abc-123] [LAYER:GEOFENCE] result=FAIL detail="Outside geofence: 250m (limit: 100m)" student=def-456
```

### General Logging
- **Backend**: SLF4J via Logback. Levels: `DEBUG` for development, `INFO` for production
- **ML Service**: Python `logging` module. Format: `%(asctime)s [%(levelname)s] %(name)s: %(message)s`
- **Client**: Use `debugPrint()` during development, never `print()` (lint rule enforced)

### What to Log
- ✅ Authentication events (login, register, token refresh)
- ✅ Enrollment events (face enrolled, device registered/replaced)
- ✅ Session lifecycle (created, closed)
- ✅ Every scan attempt with full pipeline results
- ✅ Review decisions (approve/reject)
- ❌ Raw tokens, passwords, face image data, embeddings

## 4. Secrets Management

### Secrets & Keys
| Secret | Variable | Where Used |
|---|---|---|
| JWT signing key | `JWT_SECRET` | Backend — JwtService |
| QR HMAC signing key | `QR_HMAC_SECRET` | Backend — QrTokenService |
| Database credentials | `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` | Backend — datasource |
| ML service URL | `ML_SERVICE_URL` | Backend — WebClient |
| Admin bootstrap | `ADMIN_EMAIL`, `ADMIN_PASSWORD` | Backend — AdminBootstrap |

### Rules
1. **Never commit secrets to source control.** All secrets are injected via environment variables.
2. `application.yml` uses `${ENV_VAR:default}` syntax with **dev-only defaults** that are clearly marked as insecure.
3. For production deployment, use a secrets manager (Vault, AWS Secrets Manager) or Kubernetes secrets.
4. JWT and QR HMAC keys must be **different** — compromising one should not compromise the other.
5. Minimum key length: **32 characters** for both JWT and HMAC secrets.

## 5. Code Organization

### Backend Package Structure
```
com.secureattend/
├── config/          # @Configuration beans, properties
├── auth/            # JWT, login/register, security filter
├── enrollment/      # Face + device enrollment
├── session/         # Session lifecycle, QR rotation
├── scan/            # Fusion pipeline, scan endpoint
├── review/          # Faculty review queue
├── admin/           # Course/user management
└── common/
    ├── entity/      # JPA entities
    ├── repository/  # Spring Data repositories
    └── exception/   # Exception classes + global handler
```

### ML Service Structure
```
app/
├── main.py          # FastAPI app, lifespan, routers
├── face/            # Face service + router
├── anomaly/         # Anomaly service + router
└── models/          # Pydantic schemas
```

### Flutter Feature Structure
Each feature module follows:
```
features/{name}/
├── presentation/    # Screens (widgets)
├── providers/       # Riverpod state management
└── models/          # Data models
```

## 6. Database Conventions

- All primary keys are **UUIDs** (not auto-increment) to prevent enumeration
- All timestamps use **TIMESTAMPTZ** (UTC timezone-aware)
- Use **Flyway versioned migrations** (`V{N}__{description}.sql`) — never modify applied migrations
- Soft deletion is preferred where audit trails matter (e.g., device deactivation uses `is_active` flag)

## 7. API Design Conventions

- REST resource naming: plural nouns (`/sessions`, `/courses`)
- Use HTTP verbs correctly: `POST` create, `GET` read, `PUT` full update, `PATCH` partial update, `DELETE` remove
- Paginated responses use `{ content: [], totalElements, page, size }` format
- All dates in API responses are ISO 8601 UTC (`2026-09-18T10:30:00Z`)
