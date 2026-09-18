"""Pydantic schemas for ML service request/response models."""

from pydantic import BaseModel, Field
from typing import List, Optional


class EmbeddingResponse(BaseModel):
    """Response from the face embedding extraction endpoint."""
    embedding: List[float] = Field(..., description="512-dimensional face embedding vector")


class FaceVerifyRequest(BaseModel):
    """Request for face verification (JSON mode with base64 image)."""
    face_frame_base64: str = Field(..., description="Base64-encoded face image")
    stored_embedding: List[float] = Field(..., description="Previously stored 512-d embedding")
    similarity_threshold: float = Field(default=0.55, description="Cosine similarity threshold")


class FaceVerifyResponse(BaseModel):
    """Response from face verification endpoint."""
    match: bool = Field(..., description="Whether face matches stored embedding")
    similarity: float = Field(..., description="Cosine similarity score (0.0-1.0)")
    liveness_passed: bool = Field(..., description="Whether liveness check passed")
    liveness_detail: str = Field(..., description="Human-readable liveness result")


class ScanFeatures(BaseModel):
    """Behavioral features for anomaly scoring."""
    time_of_day: float = Field(..., description="Fractional hour (0.0-24.0)")
    day_of_week: int = Field(..., ge=0, le=6, description="0=Monday..6=Sunday")
    location_lat: float
    location_lon: float
    face_similarity: float = Field(default=0.0)


class AnomalyRequest(BaseModel):
    """Request for anomaly scoring."""
    student_id: str
    scan_features: ScanFeatures


class AnomalyResponse(BaseModel):
    """Response from anomaly scoring endpoint."""
    anomaly_score: float = Field(..., description="0.0 (normal) to 1.0 (highly anomalous)")
    is_anomalous: bool
    reason: str = Field(..., description="Human-readable anomaly explanation")
