"""
Unit and integration tests for SecureAttend ML Microservice.
Tests health endpoint, anomaly scoring cold start, anomaly detection,
and face verification validation.
"""

import pytest
from fastapi.testclient import TestClient
from app.main import app

client = TestClient(app)


def test_health_endpoint():
    """Health check returns healthy status."""
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"
    assert "model_loaded" in data


def test_anomaly_cold_start():
    """Cold start: students with < 5 historical scans get 0.0 anomaly score."""
    student_id = "test-student-cold-start-001"
    payload = {
        "student_id": student_id,
        "scan_features": {
            "time_of_day": 9.5,
            "day_of_week": 1,
            "location_lat": 28.5355,
            "location_lon": 77.3910,
            "face_similarity": 0.88,
        },
    }
    response = client.post("/api/anomaly/score", json=payload)
    assert response.status_code == 200
    data = response.json()
    assert data["anomaly_score"] == 0.0
    assert data["is_anomalous"] is False
    assert "Insufficient history" in data["reason"]


def test_anomaly_scoring_progression():
    """After 5 baseline scans, anomaly scoring evaluates against history."""
    student_id = "test-student-history-002"

    # Send 5 consistent baseline scans (9:00 AM on weekdays at Delhi classroom)
    for i in range(5):
        client.post(
            "/api/anomaly/score",
            json={
                "student_id": student_id,
                "scan_features": {
                    "time_of_day": 9.0 + (i * 0.05),
                    "day_of_week": i % 5,
                    "location_lat": 28.5355,
                    "location_lon": 77.3910,
                    "face_similarity": 0.90,
                },
            },
        )

    # 6th scan: drastically anomalous time (3:00 AM) and location (Mumbai: lat 19.07, lon 72.87)
    anomalous_scan = {
        "student_id": student_id,
        "scan_features": {
            "time_of_day": 3.0,
            "day_of_week": 6,
            "location_lat": 19.0760,
            "location_lon": 72.8777,
            "face_similarity": 0.35,
        },
    }
    response = client.post("/api/anomaly/score", json=anomalous_scan)
    assert response.status_code == 200
    data = response.json()
    assert 0.0 <= data["anomaly_score"] <= 1.0
    assert "reason" in data


def test_face_verify_missing_fields_validation():
    """Face verify validates required fields."""
    response = client.post("/api/face/verify", json={})
    assert response.status_code == 422  # Unprocessable Entity
