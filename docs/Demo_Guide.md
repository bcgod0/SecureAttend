# SecureAttend — Demo Guide

> **Anti-Proxy Attendance Verification System**  
> 4-layer verification: QR rotation · Device binding · Geofencing · Face + Liveness  
> Plus behavioral anomaly detection and a faculty review queue.

---

## Architecture Overview

```
┌─────────────────┐     HTTP/WS      ┌──────────────────┐
│  Flutter Client │ ◄──────────────► │  Spring Boot API  │
│  (Mobile/Web)   │                  │  :8080            │
└─────────────────┘                  └────────┬─────────┘
                                              │ HTTP
                                     ┌────────▼─────────┐
                                     │  FastAPI ML       │
                                     │  :8000            │
                                     │  (Face + Anomaly) │
                                     └──────────────────┘
```

## Prerequisites

| Tool | Version | Check |
|------|---------|-------|
| Java | 17+ | `java -version` |
| Python | 3.10+ | `python --version` |
| Flutter | 3.x (in `C:\flutter`) | `C:\flutter\bin\flutter.bat --version` |

---

## 1. Start the Backend

```powershell
cd "c:\Users\rijul\Desktop\sem3\Major Project\SecureAttend\backend"
.\gradlew bootRun
```

**Wait for:** `Started SecureAttendApplicationKt in X.XXX seconds`

The backend starts with a **bootstrap admin account** from env vars:
- `ADMIN_EMAIL` (default: `admin@secureattend.com`)
- `ADMIN_PASSWORD` (default: `Admin@1234`)

H2 Console: http://localhost:8080/h2-console  
JDBC URL: `jdbc:h2:mem:secureattend`

---

## 2. Start the ML Microservice

```powershell
cd "c:\Users\rijul\Desktop\sem3\Major Project\SecureAttend\ml-service"
.\venv\Scripts\python.exe -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

**Wait for:** `Application startup complete`

Swagger UI: http://127.0.0.1:8000/docs

---

## 3. Run the Flutter Client (Web)

```powershell
cd "c:\Users\rijul\Desktop\sem3\Major Project\SecureAttend\client"
C:\flutter\bin\flutter.bat run -d chrome
```

The app opens at `localhost:XXXX` and shows the **Login** screen.

### For Android (physical device or emulator):
```powershell
C:\flutter\bin\flutter.bat run -d android
```
> **Note:** The backend URL defaults to `http://localhost:8080`. On Android emulator use `http://10.0.2.2:8080`.

---

## 4. Demo Flow (Evaluator Script)

### Step 1 — Admin Setup

1. Login with admin credentials
2. Go to **Admin Dashboard** → Create a course (e.g., `CS501 — Machine Learning`)
3. Register a **Faculty** account via `/register`
4. Register a **Student** account via `/register`
5. In Admin Dashboard → enroll the student in the course

### Step 2 — Student Enrollment

1. Login as the student
2. Navigate to **Enrollment** (`/student/enrollment`)
3. **Face Enrollment** → capture selfie photo → submitted to ML service for embedding storage
4. **Device Registration** → device fingerprint is bound to this student account

### Step 3 — Faculty Creates Session

1. Login as faculty
2. **Sessions** → **Create Session**
3. Fill in: course, GPS coordinates, geofence radius (e.g., 100m), QR rotation interval (10s)
4. Tap **Create** → session starts, QR rotation begins

### Step 4 — Display Mode (Classroom Projector)

1. Faculty taps the session → **Display Mode**
2. Full-screen rotating QR code appears (updates every N seconds via WebSocket)
3. Attendance count updates in real-time as students scan

### Step 5 — Student Scans Attendance

1. Login as student → **Attendance** screen
2. Tap **Scan QR Code** → camera opens
3. Scan the rotating QR code from the projector
4. App captures: QR token + device fingerprint + GPS + face selfie
5. All 4 signals sent to backend → ML service verifies face
6. Result: ✅ **PRESENT** or ⚠️ **FLAGGED** (for review) or ❌ **REJECTED**

### Step 6 — Student Views Attendance History

1. Student taps **My Attendance History** (from the Attendance screen or the history icon in the AppBar)
2. View total attendance rate %, scan status badges (PRESENT / FLAGGED / REJECTED)
3. Expand any scan tile to inspect the full 4-layer telemetry audit trail (QR status, Geofence distance, Device match, Face similarity score)

### Step 7 — Faculty Reviews Flagged Scans & Exports Roster

1. Faculty → **Review Queue** (bell icon in Sessions screen)
2. See all FLAGGED scans with face photos and signal breakdowns
3. **Approve** or **Reject** each one manually
4. In Session Dashboard → tap **Roster** on any session card
5. View real-time attendee list, filter by status, and click **Export CSV** to copy roster directly to clipboard

---

## 5. API Quick Reference

### Auth
```bash
# Login
curl -X POST http://localhost:8080/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@secureattend.com","password":"Admin@1234"}'
```

### Sessions
```bash
# Create session (faculty JWT required)
curl -X POST http://localhost:8080/api/sessions \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"courseId":"<uuid>","geofenceLat":28.6139,"geofenceLon":77.2090,"geofenceRadiusMeters":100,"qrRotationSeconds":10}'
```

### Current QR Token (Display Mode bootstrap)
```bash
curl http://localhost:8080/api/sessions/<session-id>/qr-token \
  -H "Authorization: Bearer $TOKEN"
```

---

## 6. Security Layers Explained

| Layer | Check | Fail Action |
|-------|-------|-------------|
| **QR Token** | HMAC-signed JWT, 15s expiry, replay protection | REJECTED |
| **Device Binding** | Fingerprint hash vs enrolled device | REJECTED |
| **Geofence** | Haversine distance vs session radius | REJECTED |
| **Face + Liveness** | InsightFace cosine similarity ≥ 0.4 | FLAGGED |
| **Anomaly** | Multi-factor behavioral score | FLAGGED if score > 0.7 |

> Layers 1–3 are hard gates (REJECTED on failure).  
> Layers 4–5 produce FLAGGED status → sent to faculty review queue.

---

## 8. Automated Test Suite

### Backend Unit & Integration Tests (13 tests):
```powershell
cd "c:\Users\rijul\Desktop\sem3\Major Project\SecureAttend\backend"
.\gradlew.bat test
```
- Tests `QrTokenServiceTest`: HMAC generation, rotating intervals, replay protection, tampering rejection.
- Tests `FusionPipelineTest`: All 4 verification layers (QR, geofence, device fingerprint, face similarity), anomaly scoring, and ML service failover degradation.

### ML Microservice Tests:
```powershell
cd "c:\Users\rijul\Desktop\sem3\Major Project\SecureAttend\ml-service"
.\venv\Scripts\python.exe -m pytest tests/test_api.py
```
- Tests `/health` status and InsightFace loading.
- Tests behavioral anomaly scoring (cold start vs multi-scan progression).
- Tests face verify payload validation.

---

## 9. Troubleshooting

| Issue | Fix |
|-------|-----|
| Backend won't start | Check Java 17: `java -version` |
| `sky_engine` error with `dart pub get` | Use `C:\flutter\bin\flutter.bat pub get` (not `dart pub get`) |
| ML service can't find model | First run downloads `buffalo_s` to `~/.insightface` — wait for download |
| Android camera permission denied | Accept permissions on first launch |
| QR scan returns "session not active" | Session may have been closed; ask faculty to create a new one |
| Face enrollment fails | Ensure good lighting; face must be clearly visible |
