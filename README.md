# SecureAttend

> Multi-signal, anti-proxy attendance verification system for classroom settings.

SecureAttend replaces single-factor QR attendance with **four layered, deterministic checks** (QR rotation, device binding, geofencing, face verification + liveness) plus a **behavioral anomaly-detection layer**, giving faculty a review queue for anything the system can't confidently decide on its own.

## Architecture

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────┐
│  Flutter App  │────▶│  Spring Boot API  │────▶│  FastAPI ML   │
│  (Android/    │◀────│  (Auth, Fusion    │◀────│  (Face, Live- │
│   iOS/Web)    │     │   Pipeline, WS)   │     │   ness, Anom.)│
└──────────────┘     └────────┬─────────┘     └──────────────┘
                              │
                     ┌────────▼─────────┐
                     │   PostgreSQL DB   │
                     │   (Flyway mgd.)   │
                     └──────────────────┘
```

## Quick Start

### Prerequisites
- **JDK 17+** (for backend)
- **Python 3.11+** (for ML service)
- **Flutter 3.16+** (for client)
- **PostgreSQL 15+** (or use H2 for dev)

### 1. Backend (Spring Boot)

```bash
cd backend

# Set environment variables (or use dev defaults)
export JWT_SECRET="your-jwt-secret-min-32-characters!!"
export QR_HMAC_SECRET="your-qr-hmac-secret-min-32-chars!!"
export ADMIN_EMAIL="admin@secureattend.com"
export ADMIN_PASSWORD="AdminPass123!"

# Run with Gradle wrapper
./gradlew bootRun
# Server starts on http://localhost:8080
```

For PostgreSQL:
```bash
export DB_URL="jdbc:postgresql://localhost:5432/secureattend"
export DB_USERNAME="postgres"
export DB_PASSWORD="your-db-password"
export DB_DRIVER="org.postgresql.Driver"
```

### 2. ML Service (FastAPI)

```bash
cd ml-service

# Create virtual environment
python -m venv venv
source venv/bin/activate  # or venv\Scripts\activate on Windows

# Install dependencies
pip install -r requirements.txt

# Run
uvicorn app.main:app --host 0.0.0.0 --port 8000
# ML service starts on http://localhost:8000
# The InsightFace model downloads automatically on first run (~30MB)
```

Or with Docker:
```bash
docker build -t secureattend-ml .
docker run -p 8000:8000 secureattend-ml
```

### 3. Flutter Client

```bash
cd client

# Install dependencies
flutter pub get

# Run on web (Display Mode)
flutter run -d chrome

# Run on Android
flutter run -d android

# Run on iOS
flutter run -d ios
```

## Project Structure

```
SecureAttend/
├── backend/                    Spring Boot (Kotlin) — REST API + WebSocket
├── ml-service/                 FastAPI (Python) — Face + Anomaly ML
├── client/                     Flutter — Android/iOS/Web client
└── docs/
    ├── API_Contract.md         Full API specification
    └── Coding_Standards.md     Development conventions
```

## Verification Pipeline

At scan time, the system runs five layers in sequence:

| # | Layer | Method | Failure = |
|---|---|---|---|
| 1 | QR Validation | HMAC signature + expiry + replay check | REJECTED |
| 2 | Device Match | SHA-256 fingerprint comparison | REJECTED |
| 3 | Geofence | Haversine distance ≤ radius | REJECTED |
| 4 | Face Verification | Cosine similarity + liveness | FLAGGED |
| 5 | Anomaly Score | Isolation Forest on behavioral features | FLAGGED |

Each layer's result is independently logged for full auditability.

## Key Technologies

| Component | Stack |
|---|---|
| Backend | Spring Boot 3.3, Kotlin, JPA, Flyway, jjwt, WebSocket/STOMP |
| ML Service | FastAPI, InsightFace (buffalo_s), scikit-learn, ONNX Runtime |
| Client | Flutter 3.16+, Riverpod, GoRouter, Dio, mobile_scanner, qr_flutter |
| Database | PostgreSQL (prod) / H2 (dev) |

## License

Academic project — not licensed for commercial use.
