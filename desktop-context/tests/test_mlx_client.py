"""MLX client unit tests — pure functions, no live server."""
from __future__ import annotations

import pytest

from stello_context import mlx_client


def test_extract_json_plain() -> None:
    assert mlx_client._extract_json('{"a": 1}') == '{"a": 1}'


def test_extract_json_with_preamble() -> None:
    out = mlx_client._extract_json('Here you go: {"x": 2} done.')
    assert out == '{"x": 2}'


def test_extract_json_fenced() -> None:
    raw = '```json\n{"k": 3}\n```'
    assert mlx_client._extract_json(raw).strip() == '{"k": 3}'


def test_extract_json_fenced_bare() -> None:
    raw = "```\n[1, 2, 3]\n```"
    assert mlx_client._extract_json(raw).strip() == "[1, 2, 3]"


def test_extract_json_empty() -> None:
    with pytest.raises(mlx_client.MLXError):
        mlx_client._extract_json("")


def test_extract_json_no_delim() -> None:
    with pytest.raises(mlx_client.MLXError):
        mlx_client._extract_json("hello world")


def test_extract_json_array() -> None:
    assert mlx_client._extract_json("[1, 2, 3]") == "[1, 2, 3]"
