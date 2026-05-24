"""Live smoke test against the local MLX server.

Skipped automatically when the server isn't reachable on the default URL.
Covers embed + generate; vision intentionally omitted (would cold-load
the VLM, slow). Vision is exercised end-to-end at step 5 / step 11.
"""
from __future__ import annotations

import httpx
import pytest

from stello_context import mlx_client


def _server_reachable() -> bool:
    try:
        r = httpx.get(f"{mlx_client.DEFAULT_URL}/healthz", timeout=2.0)
        return r.status_code == 200
    except Exception:
        return False


pytestmark = pytest.mark.skipif(
    not _server_reachable(),
    reason=f"MLX server not reachable at {mlx_client.DEFAULT_URL}",
)


def test_healthz_round_trip() -> None:
    with mlx_client.Client() as cli:
        h = cli.healthz()
        assert h["ok"] is True
        assert "loaded" in h
        assert "config" in h


def test_embed_dim_and_count() -> None:
    """BGE-M3 returns 1024-dim vectors. Batch shape preserved."""
    with mlx_client.Client() as cli:
        r = cli.embed(["hello world", "another doc", "third one"])
        assert r.dim == 1024
        assert len(r.embeddings) == 3
        assert all(len(v) == 1024 for v in r.embeddings)
        # Embeddings should be plausible (not all zero).
        assert any(abs(x) > 1e-6 for x in r.embeddings[0])


def test_generate_text_smoke() -> None:
    """Smallest possible generate — just confirm the round-trip works.
    Loads the text model on first call (~1-3s).
    """
    with mlx_client.Client() as cli:
        r = cli.generate("Reply with the single word: pong", max_tokens=8)
        assert isinstance(r.text, str)
        assert len(r.text) > 0
