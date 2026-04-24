"""
Unit tests for the artifact version resolver.

Validates that version strings are formatted correctly, increment properly,
and are collision-free across multiple runs on the same date.
"""

import re
from datetime import date
from pathlib import Path

import pytest

from wine_quality_training.model_registry.artifact_version_resolver import (
    get_latest_artifact_version,
    list_artifact_versions,
    resolve_next_artifact_version,
)

VERSION_RE = re.compile(r"^v_\d{4}-\d{2}-\d{2}_\d{3}$")
MODEL_NAME = "wine_quality_classifier"


def test_first_version_on_empty_store(tmp_path):
    version = resolve_next_artifact_version(tmp_path, MODEL_NAME, run_date=date(2026, 4, 25))
    assert version == "v_2026-04-25_001"


def test_version_format_matches_pattern(tmp_path):
    version = resolve_next_artifact_version(tmp_path, MODEL_NAME, run_date=date(2026, 4, 25))
    assert VERSION_RE.match(version), f"Version '{version}' does not match expected format"


def test_second_run_same_day_increments_sequence(tmp_path):
    model_dir = tmp_path / MODEL_NAME
    (model_dir / "v_2026-04-25_001").mkdir(parents=True)
    version = resolve_next_artifact_version(tmp_path, MODEL_NAME, run_date=date(2026, 4, 25))
    assert version == "v_2026-04-25_002"


def test_new_day_resets_sequence(tmp_path):
    model_dir = tmp_path / MODEL_NAME
    (model_dir / "v_2026-04-25_001").mkdir(parents=True)
    (model_dir / "v_2026-04-25_002").mkdir(parents=True)
    version = resolve_next_artifact_version(tmp_path, MODEL_NAME, run_date=date(2026, 4, 26))
    assert version == "v_2026-04-26_001"


def test_list_versions_returns_sorted_list(tmp_path):
    model_dir = tmp_path / MODEL_NAME
    for v in ["v_2026-04-25_002", "v_2026-04-24_001", "v_2026-04-25_001"]:
        (model_dir / v).mkdir(parents=True)
    versions = list_artifact_versions(tmp_path, MODEL_NAME)
    assert versions == ["v_2026-04-24_001", "v_2026-04-25_001", "v_2026-04-25_002"]


def test_get_latest_returns_most_recent(tmp_path):
    model_dir = tmp_path / MODEL_NAME
    for v in ["v_2026-04-25_001", "v_2026-04-25_002", "v_2026-04-26_001"]:
        (model_dir / v).mkdir(parents=True)
    latest = get_latest_artifact_version(tmp_path, MODEL_NAME)
    assert latest == "v_2026-04-26_001"


def test_get_latest_returns_none_on_empty_store(tmp_path):
    assert get_latest_artifact_version(tmp_path, MODEL_NAME) is None


def test_list_versions_ignores_non_version_directories(tmp_path):
    model_dir = tmp_path / MODEL_NAME
    (model_dir / "v_2026-04-25_001").mkdir(parents=True)
    (model_dir / "temp_debug_run").mkdir(parents=True)
    (model_dir / "latest").mkdir(parents=True)
    versions = list_artifact_versions(tmp_path, MODEL_NAME)
    assert versions == ["v_2026-04-25_001"]
