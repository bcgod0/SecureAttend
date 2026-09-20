-- ============================================================
-- SecureAttend — V1 Initial Schema
-- Database: PostgreSQL
-- All PKs are UUIDs; timestamps use TIMESTAMPTZ (UTC)
-- ============================================================

-- -------------------------------------------------------
-- ENUM types
-- -------------------------------------------------------
CREATE TYPE user_role AS ENUM ('STUDENT', 'FACULTY', 'ADMIN');
CREATE TYPE session_status AS ENUM ('ACTIVE', 'CLOSED');
CREATE TYPE scan_status AS ENUM ('PRESENT', 'FLAGGED', 'REJECTED');
CREATE TYPE review_decision AS ENUM ('APPROVED', 'REJECTED');

-- -------------------------------------------------------
-- 1. users
-- -------------------------------------------------------
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email           VARCHAR(255)    NOT NULL UNIQUE,
    password_hash   VARCHAR(255)    NOT NULL,
    full_name       VARCHAR(255)    NOT NULL,
    role            user_role       NOT NULL,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE INDEX idx_users_email ON users (email);
CREATE INDEX idx_users_role  ON users (role);

-- -------------------------------------------------------
-- 2. courses
-- -------------------------------------------------------
CREATE TABLE courses (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    code            VARCHAR(50)     NOT NULL UNIQUE,
    name            VARCHAR(255)    NOT NULL,
    created_by      UUID            NOT NULL REFERENCES users(id),
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE INDEX idx_courses_code ON courses (code);

-- -------------------------------------------------------
-- 3. course_enrollments (student ↔ course)
-- -------------------------------------------------------
CREATE TABLE course_enrollments (
    student_id      UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    course_id       UUID            NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
    enrolled_at     TIMESTAMPTZ     NOT NULL DEFAULT now(),
    PRIMARY KEY (student_id, course_id)
);

CREATE INDEX idx_course_enrollments_course ON course_enrollments (course_id);

-- -------------------------------------------------------
-- 4. device_registrations
-- One active device per student (UNIQUE on student_id
-- enforced via partial unique index on is_active = true)
-- -------------------------------------------------------
CREATE TABLE device_registrations (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id          UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    fingerprint_hash    VARCHAR(64)     NOT NULL,  -- SHA-256 hex
    device_info         JSONB,                      -- { platform, model, os_version, ... }
    is_active           BOOLEAN         NOT NULL DEFAULT true,
    registered_at       TIMESTAMPTZ     NOT NULL DEFAULT now(),
    deactivated_at      TIMESTAMPTZ
);

-- Only one active device per student at a time (FR-3)
CREATE UNIQUE INDEX idx_device_registrations_active
    ON device_registrations (student_id)
    WHERE is_active = true;

CREATE INDEX idx_device_registrations_student ON device_registrations (student_id);

-- -------------------------------------------------------
-- 5. face_embeddings
-- Stores the 512-float vector as binary; raw image is
-- NEVER persisted (NFR-2)
-- -------------------------------------------------------
CREATE TABLE face_embeddings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    student_id      UUID            NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    embedding       BYTEA           NOT NULL,  -- 512 x float32 = 2048 bytes
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

-- One embedding per student (FR-2)
CREATE UNIQUE INDEX idx_face_embeddings_student
    ON face_embeddings (student_id);

-- -------------------------------------------------------
-- 6. sessions
-- -------------------------------------------------------
CREATE TABLE sessions (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    course_id               UUID            NOT NULL REFERENCES courses(id),
    faculty_id              UUID            NOT NULL REFERENCES users(id),
    geofence_lat            DOUBLE PRECISION NOT NULL,
    geofence_lon            DOUBLE PRECISION NOT NULL,
    geofence_radius_meters  INTEGER         NOT NULL DEFAULT 100,
    qr_rotation_seconds     INTEGER         NOT NULL DEFAULT 10,
    status                  session_status  NOT NULL DEFAULT 'ACTIVE',
    started_at              TIMESTAMPTZ     NOT NULL DEFAULT now(),
    closed_at               TIMESTAMPTZ
);

CREATE INDEX idx_sessions_course   ON sessions (course_id);
CREATE INDEX idx_sessions_faculty  ON sessions (faculty_id);
CREATE INDEX idx_sessions_status   ON sessions (status);

-- -------------------------------------------------------
-- 7. scans (one row per attendance attempt)
-- -------------------------------------------------------
CREATE TABLE scans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    session_id      UUID            NOT NULL REFERENCES sessions(id),
    student_id      UUID            NOT NULL REFERENCES users(id),
    final_status    scan_status     NOT NULL,
    submitted_at    TIMESTAMPTZ     NOT NULL DEFAULT now(),
    -- Device / location metadata captured at scan time
    device_fingerprint  VARCHAR(64),
    location_lat    DOUBLE PRECISION,
    location_lon    DOUBLE PRECISION
);

CREATE INDEX idx_scans_session  ON scans (session_id);
CREATE INDEX idx_scans_student  ON scans (student_id);
CREATE INDEX idx_scans_status   ON scans (final_status);

-- Prevent duplicate attendance: one scan per student per session
-- (student can retry if REJECTED, but only one PRESENT/FLAGGED allowed)
CREATE UNIQUE INDEX idx_scans_unique_attendance
    ON scans (session_id, student_id)
    WHERE final_status IN ('PRESENT', 'FLAGGED');

-- -------------------------------------------------------
-- 8. scan_layer_results (per-layer audit trail — NFR-6)
-- Every scan produces exactly one row per verification layer
-- -------------------------------------------------------
CREATE TABLE scan_layer_results (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id         UUID            NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    layer_name      VARCHAR(50)     NOT NULL,  -- QR_VALIDATION, DEVICE_MATCH, GEOFENCE, FACE_VERIFICATION, ANOMALY
    passed          BOOLEAN         NOT NULL,
    score           DOUBLE PRECISION,           -- nullable; used by face/anomaly layers
    detail          TEXT,                        -- human-readable explanation
    evaluated_at    TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE INDEX idx_scan_layer_results_scan ON scan_layer_results (scan_id);

-- -------------------------------------------------------
-- 9. review_queue (faculty review of FLAGGED scans — FR-14, FR-15)
-- -------------------------------------------------------
CREATE TABLE review_queue (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id             UUID            NOT NULL UNIQUE REFERENCES scans(id) ON DELETE CASCADE,
    flagged_reason      TEXT            NOT NULL,  -- human-readable reason
    reviewed_by         UUID            REFERENCES users(id),
    review_decision     review_decision,
    review_notes        TEXT,
    flagged_at          TIMESTAMPTZ     NOT NULL DEFAULT now(),
    reviewed_at         TIMESTAMPTZ
);

CREATE INDEX idx_review_queue_pending
    ON review_queue (scan_id)
    WHERE review_decision IS NULL;

-- -------------------------------------------------------
-- 10. anomaly_scan_features (historical features for
-- per-student Isolation Forest training)
-- -------------------------------------------------------
CREATE TABLE anomaly_scan_features (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id         UUID            NOT NULL REFERENCES scans(id) ON DELETE CASCADE,
    student_id      UUID            NOT NULL REFERENCES users(id),
    time_of_day     DOUBLE PRECISION NOT NULL,  -- fractional hour (0.0–24.0)
    day_of_week     INTEGER         NOT NULL,   -- 0=Monday..6=Sunday
    location_lat    DOUBLE PRECISION NOT NULL,
    location_lon    DOUBLE PRECISION NOT NULL,
    face_similarity DOUBLE PRECISION,
    anomaly_score   DOUBLE PRECISION,
    created_at      TIMESTAMPTZ     NOT NULL DEFAULT now()
);

CREATE INDEX idx_anomaly_features_student ON anomaly_scan_features (student_id);
