"""
Artifact version resolver: determine the next version string for a training run.

Version format: v_YYYY-MM-DD_NNN
  YYYY-MM-DD — date the run was executed
  NNN        — zero-padded sequence number, incremented per run on that date

Example progression on 2026-04-25:
  v_2026-04-25_001
  v_2026-04-25_002
  ...
  v_2026-04-25_010

This scheme is:
  - Human-readable (date is visible without parsing metadata)
  - Sortable lexicographically by recency
  - Collision-free across concurrent runs on the same date (sequence padding)
  - Compatible with S3/GCS/Azure Blob object key conventions

ENTERPRISE EMPHASIS: Without version isolation each training run would
overwrite the previous model artifact. In a Kubernetes Job that is retried
due to a transient node failure, the partially-written artifact from the
first attempt could corrupt the store. Versioned directories make every
run's output atomic and independently addressable.
"""

from __future__ import annotations

import re
from datetime import date
from pathlib import Path


VERSION_PATTERN = re.compile(r"^v_(\d{4}-\d{2}-\d{2})_(\d{3})$")


def resolve_next_artifact_version(
    artifact_store_root: Path,
    model_name: str,
    run_date: date | None = None,
) -> str:
    """
    Determine the next version string for a given model name and date.

    Scans existing version directories under artifact_store_root/model_name/
    to find the highest sequence number used on run_date, then increments it.

    Args:
        artifact_store_root: Root directory of the local artifact store.
        model_name:          Model name sub-directory (e.g. 'wine_quality_classifier').
        run_date:            Date for the version label. Defaults to today.

    Returns:
        Version string in the format 'v_YYYY-MM-DD_NNN'.
    """
    if run_date is None:
        run_date = date.today()

    date_str = run_date.strftime("%Y-%m-%d")
    model_dir = artifact_store_root / model_name

    if not model_dir.exists():
        return f"v_{date_str}_001"

    existing_versions = [
        d.name for d in model_dir.iterdir()
        if d.is_dir() and VERSION_PATTERN.match(d.name)
    ]

    same_date_sequences = []
    for v in existing_versions:
        match = VERSION_PATTERN.match(v)
        if match and match.group(1) == date_str:
            same_date_sequences.append(int(match.group(2)))

    next_seq = (max(same_date_sequences) + 1) if same_date_sequences else 1
    return f"v_{date_str}_{next_seq:03d}"


def list_artifact_versions(
    artifact_store_root: Path,
    model_name: str,
) -> list[str]:
    """
    Return all version strings for a model, sorted oldest-to-newest.

    Useful for rollback tooling and lineage reporting.
    """
    model_dir = artifact_store_root / model_name
    if not model_dir.exists():
        return []

    versions = [
        d.name for d in model_dir.iterdir()
        if d.is_dir() and VERSION_PATTERN.match(d.name)
    ]
    return sorted(versions)


def get_latest_artifact_version(
    artifact_store_root: Path,
    model_name: str,
) -> str | None:
    """Return the most recent version string, or None if no versions exist."""
    versions = list_artifact_versions(artifact_store_root, model_name)
    return versions[-1] if versions else None
