"""
Behavioral anomaly detection using Isolation Forest.

Trains per-student models on historical scan features to detect
unusual attendance patterns (proxy scanning, location spoofing, etc.).

Cold start: Students with fewer than MIN_HISTORY_SIZE scans get a
neutral anomaly score of 0.0 (no penalty for new students).
"""

import logging
from collections import defaultdict
from typing import Dict, List, Tuple

import numpy as np
from sklearn.ensemble import IsolationForest

logger = logging.getLogger(__name__)

MIN_HISTORY_SIZE = 5  # Minimum scans before anomaly scoring kicks in


class AnomalyService:
    """
    Per-student Isolation Forest anomaly detector.

    Maintains an in-memory history of scan features per student.
    In production, this would be backed by the database; here we
    accumulate history from incoming requests.
    """

    def __init__(self):
        # student_id → list of feature vectors
        self._history: Dict[str, List[np.ndarray]] = defaultdict(list)
        # student_id → fitted IsolationForest model
        self._models: Dict[str, IsolationForest] = {}

    def add_to_history(self, student_id: str, features: np.ndarray):
        """Add a scan's features to the student's history."""
        self._history[student_id].append(features)

        # Re-train model when we have enough data
        history = self._history[student_id]
        if len(history) >= MIN_HISTORY_SIZE:
            self._train_model(student_id, history)

    def score(self, student_id: str, features: np.ndarray) -> Tuple[float, bool, str]:
        """
        Score a scan's behavioral features for anomalies.

        Returns:
            (anomaly_score, is_anomalous, reason)
            - anomaly_score: 0.0 (normal) to 1.0 (highly anomalous)
            - is_anomalous: True if score > threshold
            - reason: Human-readable explanation
        """
        history = self._history.get(student_id, [])

        # Cold start: not enough history to score
        if len(history) < MIN_HISTORY_SIZE:
            # Still add to history for future scoring
            self.add_to_history(student_id, features)
            return 0.0, False, f"Insufficient history ({len(history)+1}/{MIN_HISTORY_SIZE} scans) — defaulting to normal"

        model = self._models.get(student_id)
        if model is None:
            self._train_model(student_id, history)
            model = self._models.get(student_id)

        if model is None:
            return 0.0, False, "Model training failed — defaulting to normal"

        try:
            # Isolation Forest: decision_function returns negative for outliers
            # score_samples returns the anomaly score; more negative = more anomalous
            raw_score = model.decision_function(features.reshape(1, -1))[0]

            # Convert to 0-1 range: raw_score is typically in [-0.5, 0.5]
            # More negative = more anomalous → higher anomaly_score
            anomaly_score = max(0.0, min(1.0, 0.5 - raw_score))

            is_anomalous = anomaly_score > 0.7

            # Generate human-readable reason
            reason = self._explain_anomaly(features, history, anomaly_score)

            # Add this scan to history regardless
            self.add_to_history(student_id, features)

            return round(anomaly_score, 4), is_anomalous, reason

        except Exception as e:
            logger.error("Anomaly scoring error for student %s: %s", student_id, str(e))
            return 0.0, False, f"Scoring error: {str(e)} — defaulting to normal"

    def _train_model(self, student_id: str, history: List[np.ndarray]):
        """Train an Isolation Forest model on the student's scan history."""
        try:
            X = np.array(history)
            model = IsolationForest(
                n_estimators=100,
                contamination=0.1,  # Expect ~10% anomalies
                random_state=42
            )
            model.fit(X)
            self._models[student_id] = model
            logger.debug("Trained anomaly model for student %s (%d samples)", student_id, len(history))
        except Exception as e:
            logger.error("Model training failed for student %s: %s", student_id, str(e))

    def _explain_anomaly(
        self, features: np.ndarray, history: List[np.ndarray], score: float
    ) -> str:
        """Generate a human-readable explanation of why a scan is anomalous."""
        if score < 0.3:
            return "Normal behavior pattern"
        elif score < 0.5:
            return "Slightly unusual timing or location"
        elif score < 0.7:
            return "Moderately unusual — different from typical scan pattern"

        # For high scores, provide more specific reasons
        history_array = np.array(history)
        reasons = []

        # Check time deviation
        mean_time = history_array[:, 0].mean()
        time_diff = abs(features[0] - mean_time)
        if time_diff > 3.0:  # More than 3 hours from typical scan time
            reasons.append(f"unusual scan time (Δ{time_diff:.1f}h from average)")

        # Check location deviation
        mean_lat = history_array[:, 2].mean()
        mean_lon = history_array[:, 3].mean()
        lat_diff = abs(features[2] - mean_lat)
        lon_diff = abs(features[3] - mean_lon)
        if lat_diff > 0.01 or lon_diff > 0.01:  # Roughly > 1km deviation
            reasons.append("unusual scan location")

        # Check face similarity deviation
        if len(features) > 4:
            mean_sim = history_array[:, 4].mean()
            if features[4] < mean_sim - 0.15:
                reasons.append(f"lower-than-typical face similarity ({features[4]:.2f} vs avg {mean_sim:.2f})")

        if reasons:
            return f"Anomaly detected: {', '.join(reasons)}"
        else:
            return "Anomaly detected: behavioral pattern deviates from student history"


# Global singleton instance
anomaly_service = AnomalyService()
