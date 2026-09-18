"""Anomaly scoring API endpoint."""

import logging

import numpy as np
from fastapi import APIRouter

from app.anomaly.service import anomaly_service
from app.models.schemas import AnomalyRequest, AnomalyResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/score", response_model=AnomalyResponse)
async def score_anomaly(request: AnomalyRequest):
    """
    Score a scan's behavioral features for anomalies using per-student
    Isolation Forest models.

    Cold start: Returns score=0.0 for students with fewer than 5 scans.
    """
    features = np.array([
        request.scan_features.time_of_day,
        request.scan_features.day_of_week,
        request.scan_features.location_lat,
        request.scan_features.location_lon,
        request.scan_features.face_similarity,
    ])

    anomaly_score, is_anomalous, reason = anomaly_service.score(
        student_id=request.student_id,
        features=features
    )

    logger.info(
        "Anomaly score for student %s: %.4f (anomalous=%s)",
        request.student_id, anomaly_score, is_anomalous
    )

    return AnomalyResponse(
        anomaly_score=anomaly_score,
        is_anomalous=is_anomalous,
        reason=reason
    )
