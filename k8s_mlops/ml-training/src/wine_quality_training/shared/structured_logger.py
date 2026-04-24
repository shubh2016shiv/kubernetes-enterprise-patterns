"""
Structured logging for the wine quality training pipeline.

Every log record emitted by this pipeline carries a `pipeline_phase` field
so that log aggregators (Loki, Elasticsearch, CloudWatch Logs Insights) can
filter by phase without parsing free-text messages.

ENTERPRISE EMPHASIS: In a Kubernetes-based MLOps platform, pod logs are the
primary observability surface for short-lived Jobs. Structured fields make
logs queryable from day one — no log parsing rules required.
"""

import logging
import sys
from typing import Optional


def get_pipeline_logger(name: str, phase: Optional[str] = None) -> logging.Logger:
    """
    Return a logger that prefixes every message with the pipeline phase.

    Args:
        name:  Python module name, typically __name__.
        phase: ML lifecycle phase label (e.g. "data_validation", "model_training").
               When supplied, every record includes it as a LoggerAdapter extra.
    """
    logger = logging.getLogger(name)

    if not logger.handlers:
        handler = logging.StreamHandler(sys.stdout)
        formatter = logging.Formatter(
            fmt="%(asctime)s | %(levelname)-8s | %(pipeline_phase)-22s | %(name)s | %(message)s",
            datefmt="%Y-%m-%dT%H:%M:%S",
        )
        handler.setFormatter(formatter)
        logger.addHandler(handler)
        logger.setLevel(logging.INFO)
        logger.propagate = False

    if phase:
        return logging.LoggerAdapter(logger, extra={"pipeline_phase": phase})

    return logging.LoggerAdapter(logger, extra={"pipeline_phase": "unset"})


def configure_root_logging(level: str = "INFO") -> None:
    """
    Configure root logger for the pipeline entrypoint.
    Called once from run_training_pipeline.py before any stage runs.
    """
    numeric_level = getattr(logging, level.upper(), logging.INFO)
    logging.basicConfig(
        stream=sys.stdout,
        level=numeric_level,
        format="%(asctime)s | %(levelname)-8s | %(name)s | %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )
