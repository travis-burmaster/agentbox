#!/usr/bin/env python3
"""Ollama-compatible HTTP facade for llm-proxy. Presents Claude Max as a local Ollama server."""

from __future__ import annotations

import sys
import json
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import AsyncGenerator

# Add parent directory so proxy_core is importable regardless of working directory.
sys.path.insert(0, str(Path(__file__).parent.parent))

import proxy_core
from fastapi import FastAPI, Request
from fastapi.responses import StreamingResponse, JSONResponse

app = FastAPI(title="LLM Proxy Ollama Facade")

from fastapi import Request
from fastapi.responses import JSONResponse
import ipaddress

ALLOWED_NETWORK = ipaddress.IPv4Network("10.0.0.0/24")

@app.middleware("http")
async def restrict_to_subnet(request: Request, call_next):
    client_ip = request.client.host
    try:
        ip = ipaddress.IPv4Address(client_ip)
        if ip not in ALLOWED_NETWORK and str(ip) != "127.0.0.1":
            return JSONResponse({"error": "Access denied"}, status_code=403)
    except Exception:
        return JSONResponse({"error": "Invalid client IP"}, status_code=403)
    return await call_next(request)


_OLLAMA_MODELS: list[dict] = proxy_core.CFG.get(
    "ollama_models",
    [{"name": proxy_core.DEFAULT_MODEL, "context_window": 200000, "max_tokens": 8192}],
)
_DEFAULT_MODEL: str = _OLLAMA_MODELS[0]["name"] if _OLLAMA_MODELS else proxy_core.DEFAULT_MODEL



def _normalize_model(name: str) -> str:
    """Strip :latest tags and normalize common aliases to exact Anthropic model IDs."""
    # Strip :tag suffix (e.g. "claude-sonnet-4-6:latest" -> "claude-sonnet-4-6")
    name = name.split(":")[0].strip()
    # Alias map for common variants
    # All common aliases → actual CLIProxyAPI model IDs
    aliases = {
        "claude-sonnet": "claude-sonnet-4-6",
        "sonnet": "claude-sonnet-4-6",
        "claude-3-5-sonnet": "claude-sonnet-4-6",
        "claude-3-5-sonnet-20241022": "claude-sonnet-4-6",
        "claude-3-7-sonnet-20250219": "claude-sonnet-4-6",
        "claude-sonnet-4-5": "claude-sonnet-4-6",
        "claude-sonnet-4-5-20250929": "claude-sonnet-4-6",
        "claude-sonnet-4-20250514": "claude-sonnet-4-6",
        "claude-haiku": "claude-haiku-4-5-20251001",
        "claude-haiku-4-5": "claude-haiku-4-5-20251001",
        "claude-3-haiku-20240307": "claude-haiku-4-5-20251001",
        "claude-3-5-haiku": "claude-haiku-4-5-20251001",
        "haiku": "claude-haiku-4-5-20251001",
        "claude-opus": "claude-opus-4-6",
        "opus": "claude-opus-4-6",
    }
    return aliases.get(name, name)


def _model_info(name: str) -> dict | None:
    name = _normalize_model(name)
    return next((m for m in _OLLAMA_MODELS if m["name"] == name), None)


@app.get("/")
async def root():
    return "Ollama is running"


@app.get("/api/version")
async def version():
    return {"version": "0.5.0"}


@app.get("/api/tags")
async def tags():
    now = datetime.now(timezone.utc).isoformat()
    models = [
        {
            "name": m["name"],
            "model": m["name"],
            "modified_at": now,
            "size": 0,
            "digest": "sha256:" + "0" * 64,
            "details": {
                "parent_model": "",
                "format": "gguf",
                "family": "claude",
                "families": ["claude"],
                "parameter_size": "unknown",
                "quantization_level": "unknown",
            },
        }
        for m in _OLLAMA_MODELS
    ]
    return {"models": models}


@app.get("/api/ps")
async def ps():
    now = datetime.now(timezone.utc).isoformat()
    return {
        "models": [
            {
                "name": _DEFAULT_MODEL,
                "model": _DEFAULT_MODEL,
                "size": 0,
                "digest": "sha256:" + "0" * 64,
                "details": {},
                "expires_at": "2099-01-01T00:00:00Z",
                "size_vram": 0,
            }
        ]
    }


async def _ollama_chat_stream(
    messages: list[dict], model: str, max_tokens: int
) -> AsyncGenerator[bytes, None]:
    """Convert proxy_core streaming chunks to Ollama NDJSON format."""
    t0 = time.time()
    now = datetime.now(timezone.utc).isoformat()

    async for chunk in proxy_core._call_with_failover_streaming(messages, model, max_tokens):
        if chunk.get("error"):
            line = json.dumps({
                "model": model,
                "created_at": now,
                "message": {"role": "assistant", "content": ""},
                "done": True,
                "done_reason": "error",
                "error": chunk["error"],
            })
            yield (line + "\n").encode()
            return

        text = chunk.get("text", "")
        # Skip empty keepalive chunks — don't emit blank tokens to the client
        if not text:
            continue
        line = json.dumps({
            "model": model,
            "created_at": now,
            "message": {"role": "assistant", "content": text},
            "done": False,
        })
        yield (line + "\n").encode()

    total_ns = int((time.time() - t0) * 1_000_000_000)
    done_line = json.dumps({
        "model": model,
        "created_at": now,
        "message": {"role": "assistant", "content": ""},
        "done": True,
        "done_reason": "stop",
        "total_duration": total_ns,
        "load_duration": 0,
        "prompt_eval_count": 0,
        "prompt_eval_duration": 0,
        "eval_count": 0,
        "eval_duration": total_ns,
    })
    yield (done_line + "\n").encode()


@app.post("/api/chat")
async def chat(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON body"}, status_code=400)

    model = _normalize_model(body.get("model", _DEFAULT_MODEL))
    info = _model_info(model)
    if info is None:
        return JSONResponse({"error": f"model '{model}' not found"}, status_code=404)

    messages = body.get("messages")
    if not messages:
        return JSONResponse({"error": "messages field required"}, status_code=400)

    max_tokens = body.get("options", {}).get("num_predict", info.get("max_tokens", 8192))
    stream = body.get("stream", True)


    if not stream:
        full_text = ""
        async for chunk in proxy_core._call_with_failover_streaming(messages, model, max_tokens):
            if chunk.get("error"):
                return JSONResponse({"error": chunk["error"]}, status_code=500)
            full_text += chunk.get("text", "")
        now = datetime.now(timezone.utc).isoformat()
        return {
            "model": model,
            "created_at": now,
            "message": {"role": "assistant", "content": full_text},
            "done": True,
            "done_reason": "stop",
        }

    async def _logged_stream():
        import logging
        _log = logging.getLogger("facade.debug")
        chunks = 0
        full = ""
        async for data in _ollama_chat_stream(messages, model, max_tokens):
            chunks += 1
            try:
                d = __import__('json').loads(data.decode().strip())
                c = d.get("message", {}).get("content", "")
                if c: full += c
                if d.get("done"):
                    _log.warning(f"DONE | chunks={chunks} len={len(full)} preview={full[:80]!r}")
            except: pass
            yield data

    return StreamingResponse(
        _logged_stream(),
        media_type="application/x-ndjson",
    )


@app.post("/api/generate")
async def generate(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON body"}, status_code=400)

    model = _normalize_model(body.get("model", _DEFAULT_MODEL))
    info = _model_info(model)
    if info is None:
        return JSONResponse({"error": f"model '{model}' not found"}, status_code=404)

    prompt = body.get("prompt", "")
    if not prompt:
        return JSONResponse({"error": "prompt field required"}, status_code=400)

    max_tokens = body.get("options", {}).get("num_predict", info.get("max_tokens", 8192))
    stream = body.get("stream", True)

    messages: list[dict] = []
    if body.get("system"):
        messages.append({"role": "system", "content": body["system"]})
    messages.append({"role": "user", "content": prompt})

    async def _generate_stream() -> AsyncGenerator[bytes, None]:
        t0 = time.time()
        now = datetime.now(timezone.utc).isoformat()
        async for chunk in proxy_core._call_with_failover_streaming(messages, model, max_tokens):
            if chunk.get("error"):
                yield (json.dumps({
                    "model": model, "created_at": now,
                    "response": "", "done": True, "error": chunk["error"],
                }) + "\n").encode()
                return
            yield (json.dumps({
                "model": model, "created_at": now,
                "response": chunk.get("text", ""), "done": False,
            }) + "\n").encode()
        total_ns = int((time.time() - t0) * 1_000_000_000)
        yield (json.dumps({
            "model": model, "created_at": now,
            "response": "", "done": True, "done_reason": "stop",
            "total_duration": total_ns,
        }) + "\n").encode()

    if not stream:
        full_text = ""
        async for chunk in proxy_core._call_with_failover_streaming(messages, model, max_tokens):
            if chunk.get("error"):
                return JSONResponse({"error": chunk["error"]}, status_code=500)
            full_text += chunk.get("text", "")
        now = datetime.now(timezone.utc).isoformat()
        return {"model": model, "created_at": now, "response": full_text, "done": True, "done_reason": "stop"}

    return StreamingResponse(_generate_stream(), media_type="application/x-ndjson")


@app.post("/api/show")
async def show(request: Request):
    try:
        body = await request.json()
    except Exception:
        return JSONResponse({"error": "Invalid JSON"}, status_code=400)
    name = body.get("name", body.get("model", _DEFAULT_MODEL))
    info = _model_info(name)
    if info is None:
        # Try stripping tag suffix e.g. "claude-haiku-4-5:latest"
        base = name.split(":")[0]
        info = _model_info(base)
    if info is None:
        return JSONResponse({"error": f"model '{name}' not found"}, status_code=404)
    return {
        "modelfile": f"FROM {info['name']}",
        "parameters": "",
        "template": "{{ .Prompt }}",
        "details": {
            "parent_model": "",
            "format": "gguf",
            "family": "claude",
            "families": ["claude"],
            "parameter_size": "unknown",
            "quantization_level": "unknown",
        },
        "model_info": {
            "general.architecture": "claude",
            "llama.context_length": info.get("context_window", 200000),
        },
    }


if __name__ == "__main__":
    import uvicorn
    port = proxy_core.CFG.get("ollama_port", 11434)
    uvicorn.run(app, host="0.0.0.0", port=port)
