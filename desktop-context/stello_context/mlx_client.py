"""HTTP client for the local MLX server (default 127.0.0.1:8765).

Vendored from MLX Stack's `stello_mlx.py` — kept HTTP-identical so this
package has no cross-repo PYTHONPATH coupling. The surface area is
intentionally narrow (4 methods + 2 structured-output helpers); keep it
that way.

    cli = Client()
    cli.embed(["text"])                            -> EmbedResult
    cli.generate("prompt", max_tokens=64)          -> GenerateResult
    cli.vision("desc", path_or_bytes)              -> VisionResult
    cli.generate_structured(SchemaCls, prompt)     -> SchemaCls instance
    cli.vision_structured(SchemaCls, prompt, img)  -> SchemaCls instance

The structured-output helpers handle two real failure modes of the
local 4B-text model: (1) wrapping JSON in ```json fences, (2) echoing
back the JSON schema instead of populating it. The retry-on-validation
loop coaxes the model out of both.
"""
from __future__ import annotations

import base64
import json
import logging
import os
import re
import time
from pathlib import Path
from typing import TypeVar

import httpx
from pydantic import BaseModel, ValidationError

logger = logging.getLogger("stello-context.mlx")

T = TypeVar("T", bound=BaseModel)

DEFAULT_URL = os.environ.get("STELLO_MLX_URL", "http://127.0.0.1:8765")
DEFAULT_TIMEOUT_S = 30.0
DEFAULT_VISION_TIMEOUT_S = 60.0


class MLXError(RuntimeError):
    """Raised when the MLX server returns an error or unparseable output."""


class GenerateResult(BaseModel):
    text: str
    latency_s: float


class VisionResult(BaseModel):
    text: str
    latency_s: float
    image_size: list[int]


class EmbedResult(BaseModel):
    embeddings: list[list[float]]
    dim: int
    latency_s: float


def _extract_json(text: str) -> str:
    """Pull the first top-level JSON object/array out of model output.

    Strips ```json``` fences and leading/trailing prose. Raises MLXError
    when no JSON delimiter is present or delimiters are unbalanced.
    """
    fenced = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    if fenced:
        text = fenced.group(1)
    text = text.strip()
    if not text:
        raise MLXError("empty response")
    first = min(
        (i for i in (text.find("{"), text.find("[")) if i >= 0),
        default=-1,
    )
    if first < 0:
        raise MLXError(f"no JSON delimiter in: {text[:200]!r}")
    last = max(text.rfind("}"), text.rfind("]"))
    if last < first:
        raise MLXError(f"unbalanced JSON in: {text[:200]!r}")
    return text[first : last + 1]


class Client:
    """HTTP client. One per process — uses a persistent httpx.Client under the hood.

    Usage:
        with Client() as cli:
            r = cli.embed(["doc"])
    """

    def __init__(
        self,
        base_url: str = DEFAULT_URL,
        timeout_s: float = DEFAULT_TIMEOUT_S,
        vision_timeout_s: float = DEFAULT_VISION_TIMEOUT_S,
        max_retries: int = 2,
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self._client = httpx.Client(timeout=timeout_s)
        self._vision_timeout = vision_timeout_s
        self.max_retries = max_retries

    def close(self) -> None:
        self._client.close()

    def __enter__(self) -> "Client":
        return self

    def __exit__(self, *_: object) -> None:
        self.close()

    # -- raw endpoints ----------------------------------------------------

    def healthz(self) -> dict:
        r = self._client.get(f"{self.base_url}/healthz")
        r.raise_for_status()
        return r.json()

    def generate(
        self,
        prompt: str,
        *,
        system: str | None = None,
        max_tokens: int = 256,
        temperature: float = 0.0,
        json_mode: bool = False,
    ) -> GenerateResult:
        r = self._client.post(
            f"{self.base_url}/v1/generate",
            json={
                "prompt": prompt,
                "system": system,
                "max_tokens": max_tokens,
                "temperature": temperature,
                "json_mode": json_mode,
            },
        )
        r.raise_for_status()
        return GenerateResult(**r.json())

    def vision(
        self,
        prompt: str,
        image: str | Path | bytes,
        *,
        max_tokens: int = 256,
    ) -> VisionResult:
        """`image` may be a path, raw bytes, or a base64 data-URL string."""
        if isinstance(image, bytes):
            image_b64 = base64.b64encode(image).decode()
        elif isinstance(image, (str, Path)):
            p = Path(image)
            if p.exists():
                image_b64 = base64.b64encode(p.read_bytes()).decode()
            else:
                image_b64 = str(image)
        else:
            raise TypeError(f"image must be str/Path/bytes, got {type(image)!r}")
        r = self._client.post(
            f"{self.base_url}/v1/vision",
            json={"prompt": prompt, "image": image_b64, "max_tokens": max_tokens},
            timeout=self._vision_timeout,
        )
        r.raise_for_status()
        return VisionResult(**r.json())

    def embed(self, inputs: list[str]) -> EmbedResult:
        r = self._client.post(
            f"{self.base_url}/v1/embed",
            json={"inputs": inputs},
        )
        r.raise_for_status()
        return EmbedResult(**r.json())

    # -- structured-output wrappers --------------------------------------

    def generate_structured(
        self,
        schema: type[T],
        prompt: str,
        *,
        system: str | None = None,
        max_tokens: int = 512,
    ) -> T:
        """Generate, JSON-extract, Pydantic-validate, retry on failure."""
        schema_hint = json.dumps(schema.model_json_schema(), indent=2)
        augmented = (
            f"{prompt}\n\n"
            f"Respond with ONLY valid JSON matching this schema, no preamble:\n"
            f"{schema_hint}"
        )
        last_err: Exception | None = None
        for attempt in range(self.max_retries + 1):
            result = self.generate(
                augmented, system=system, max_tokens=max_tokens, json_mode=True
            )
            try:
                payload = _extract_json(result.text)
                obj = json.loads(payload)
                return schema.model_validate(obj)
            except (MLXError, json.JSONDecodeError, ValidationError) as e:
                last_err = e
                logger.warning(
                    "structured attempt %d/%d failed (%s): %s",
                    attempt + 1,
                    self.max_retries + 1,
                    type(e).__name__,
                    e,
                )
                augmented = (
                    f"{prompt}\n\nYour previous response was invalid: {e}\n"
                    f"Respond ONLY with valid JSON matching:\n{schema_hint}"
                )
                time.sleep(0.1)
        raise MLXError(
            f"structured output failed after {self.max_retries + 1} attempts: {last_err}"
        )

    def vision_structured(
        self,
        schema: type[T],
        prompt: str,
        image: str | Path | bytes,
        *,
        max_tokens: int = 512,
    ) -> T:
        """Same as generate_structured but for the vision endpoint."""
        schema_hint = json.dumps(schema.model_json_schema(), indent=2)
        augmented = (
            f"{prompt}\n\n"
            f"Respond with ONLY valid JSON matching this schema, no preamble:\n"
            f"{schema_hint}"
        )
        last_err: Exception | None = None
        for attempt in range(self.max_retries + 1):
            result = self.vision(augmented, image, max_tokens=max_tokens)
            try:
                payload = _extract_json(result.text)
                obj = json.loads(payload)
                return schema.model_validate(obj)
            except (MLXError, json.JSONDecodeError, ValidationError) as e:
                last_err = e
                logger.warning(
                    "vision_structured attempt %d/%d failed (%s): %s",
                    attempt + 1,
                    self.max_retries + 1,
                    type(e).__name__,
                    e,
                )
                augmented = (
                    f"{prompt}\n\nYour previous response was invalid: {e}\n"
                    f"Respond ONLY with valid JSON matching:\n{schema_hint}"
                )
        raise MLXError(
            f"vision_structured failed after {self.max_retries + 1} attempts: {last_err}"
        )
