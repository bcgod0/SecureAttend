"""
SecureAttend ML Microservice

Provides face embedding extraction, face verification + liveness detection,
and behavioral anomaly scoring endpoints.

This service is stateless — persistence is owned by the Spring Boot backend.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.face.router import router as face_router
from app.anomaly.router import router as anomaly_router
from app.face.service import FaceService

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize ML models on startup."""
    logger.info("Loading face analysis model (buffalo_s)...")
    FaceService.initialize()
    logger.info("Face analysis model loaded successfully")
    yield
    logger.info("ML service shutting down")


app = FastAPI(
    title="SecureAttend ML Service",
    description="Face verification, liveness detection, and anomaly scoring",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(face_router, prefix="/api/face", tags=["Face Verification"])
app.include_router(anomaly_router, prefix="/api/anomaly", tags=["Anomaly Detection"])


@app.get("/health")
async def health():
    return {"status": "healthy", "model_loaded": FaceService.is_loaded()}
