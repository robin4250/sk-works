"""Integration-owner reviewed binding; deliberately unavailable in this candidate.

This trust anchor is code-reviewed separately, avoiding a self-referential manifest
digest. No environment/argument/manifest can install or change this binding.
"""
from __future__ import annotations
from pathlib import Path
APPROVED_DURABLE_ROOT: Path | None = None
APPROVED_MANIFEST_SHA256: str | None = None
