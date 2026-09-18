"""Face verification API endpoints."""

import logging

from fastapi import APIRouter, File, HTTPException, UploadFile

from app.face.service import FaceService
from app.models.schemas import EmbeddingResponse, FaceVerifyRequest, FaceVerifyResponse

logger = logging.getLogger(__name__)
router = APIRouter()


@router.post("/embed", response_model=EmbeddingResponse)
async def extract_embedding(face_frame: UploadFile = File(...)):
    """
    Extract a 512-d face embedding from an uploaded image.

    Used during student enrollment. The raw image is processed in-memory
    and never persisted (NFR-2).
    """
    if not FaceService.is_loaded():
        raise HTTPException(status_code=503, detail="Face model not loaded")

    image_bytes = await face_frame.read()
    image = FaceService.decode_image(image_bytes)

    if image is None:
        raise HTTPException(status_code=400, detail="Could not decode image")

    embedding = FaceService.extract_embedding(image)

    if embedding is None:
        raise HTTPException(
            status_code=400,
            detail="No face detected in the image. Ensure a clear, well-lit face photo."
        )

    logger.info("Embedding extracted successfully (dim: %d)", len(embedding))
    return EmbeddingResponse(embedding=FaceService.embedding_to_list(embedding))


@router.post("/verify", response_model=FaceVerifyResponse)
async def verify_face(request: FaceVerifyRequest):
    """
    Compare a face frame against a stored embedding and run liveness check.

    Called by the backend's fusion pipeline during scan verification.
    The face frame is base64-encoded in the JSON request body.
    """
    if not FaceService.is_loaded():
        raise HTTPException(status_code=503, detail="Face model not loaded")

    # Decode the base64 face frame
    image = FaceService.decode_base64_image(request.face_frame_base64)
    if image is None:
        raise HTTPException(status_code=400, detail="Could not decode face frame image")

    # Extract embedding from the scan-time frame
    scan_embedding = FaceService.extract_embedding(image)
    if scan_embedding is None:
        return FaceVerifyResponse(
            match=False,
            similarity=0.0,
            liveness_passed=False,
            liveness_detail="No face detected in scan frame"
        )

    # Compare with stored embedding
    stored_embedding = FaceService.list_to_embedding(request.stored_embedding)
    similarity = FaceService.compute_similarity(scan_embedding, stored_embedding)
    match = similarity >= request.similarity_threshold

    # Run liveness check
    liveness_passed, liveness_detail = FaceService.check_liveness(image)

    logger.info(
        "Face verification: match=%s (sim=%.3f, threshold=%.2f), liveness=%s",
        match, similarity, request.similarity_threshold, liveness_passed
    )

    return FaceVerifyResponse(
        match=match,
        similarity=round(similarity, 4),
        liveness_passed=liveness_passed,
        liveness_detail=liveness_detail
    )
