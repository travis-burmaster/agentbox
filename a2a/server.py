import asyncio
import base64
import json
import logging
import os
import sys
import uuid
from collections.abc import AsyncGenerator
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from pydantic import BaseModel, Field
from sse_starlette.sse import EventSourceResponse


A2A_JSONRPC = "2.0"
TASK_TIMEOUT_SECONDS = 55 * 60  # 55 min for Cloud Run max window
DEFAULT_GATEWAY_URL = "http://localhost:3000"
CARD_PATH = Path(__file__).with_name("agent_card.json")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s", stream=sys.stdout)
logger = logging.getLogger("agentbox.a2a")
_AGENT_CARD_CACHE: dict = json.loads(CARD_PATH.read_text(encoding="utf-8"))
_tasks: dict = {}  # task_id -> asyncio.Task


# ── Pydantic models ─────────────────────────────────────────────────────────


class Part(BaseModel):
    type: str = "text"
    text: Optional[str] = None


class Message(BaseModel):
    role: str = "user"
    parts: List[Part] = []


class JsonRpcRequest(BaseModel):
    jsonrpc: str = Field(default=A2A_JSONRPC)
    id: Optional[Union[str, int]] = None
    method: str
    params: Dict[str, Any] = {}


app = FastAPI(title="AgentBox A2A Wrapper", version="1.0.0")


# ── Helpers ──────────────────────────────────────────────────────────────────


def _a2a_error(
    code: int,
    message: str,
    rpc_id: Optional[Union[str, int]] = None,
    http_status: int = 200,
) -> JSONResponse:
    return JSONResponse(
        status_code=http_status,
        content={
            "jsonrpc": A2A_JSONRPC,
            "id": rpc_id,
            "error": {
                "code": code,
                "message": message,
            },
        },
    )


def _make_task_obj(
    task_id: str,
    context_id: str,
    state: str,
    text: Optional[str] = None,
) -> Dict[str, Any]:
    """Build an A2A Task object."""
    task: Dict[str, Any] = {
        "id": task_id,
        "contextId": context_id,
        "status": {"state": state},
    }
    if text is not None:
        task["artifacts"] = [
            {
                "parts": [{"type": "text", "text": text}],
            }
        ]
    return task


def _jsonrpc_response(rpc_id: Optional[Union[str, int]], result: Any) -> str:
    """Serialize a JSON-RPC success response to JSON string."""
    return json.dumps(
        {"jsonrpc": A2A_JSONRPC, "id": rpc_id, "result": result},
        ensure_ascii=False,
    )


def _extract_text_from_parts(parts: List[Any]) -> str:
    """Extract text from message parts (handles both typed and untyped)."""
    chunks = []
    for p in parts:
        if isinstance(p, dict):
            t = p.get("text")
            if t:
                chunks.append(t)
        elif hasattr(p, "text") and p.text:
            chunks.append(p.text)
    return "\n".join(chunks).strip()


def _extract_caller_email_from_bearer(authz_header: Optional[str]) -> Optional[str]:
    if not authz_header or not authz_header.startswith("Bearer "):
        return None

    token_parts = authz_header.split(" ", 1)[1].strip().split(".")
    if len(token_parts) < 2:
        return None

    payload = token_parts[1]
    padding = "=" * (-len(payload) % 4)
    try:
        decoded = base64.urlsafe_b64decode(payload + padding)
        claims = json.loads(decoded.decode("utf-8"))
    except Exception:  # noqa: BLE001
        return None

    email = claims.get("email")
    return str(email) if email else None


def _sanitize_email_for_path(email: str) -> str:
    """Convert email to a filesystem-safe directory name.

    e.g. 'user@domain.com' -> 'user-at-domain-com'
    """
    return email.lower().replace("@", "-at-").replace(".", "-")


def _validate_google_token(authz_header: Optional[str]) -> Optional[str]:
    if not authz_header or not authz_header.startswith("Bearer "):
        return "Missing or invalid Authorization header"

    raw_token = authz_header.split(" ", 1)[1].strip()
    audience_env = os.getenv("EXPECTED_AUDIENCE") or os.getenv("SERVICE_URL") or ""
    expected_audiences = [a.strip() for a in audience_env.split(",") if a.strip()]
    expected_callers = {
        item.strip()
        for item in os.getenv("EXPECTED_CALLER_SA", "").split(",")
        if item.strip()
    }

    if not expected_audiences:
        return "Server is missing EXPECTED_AUDIENCE or SERVICE_URL configuration"
    if not expected_callers:
        return "Server is missing EXPECTED_CALLER_SA configuration"

    claims = None
    last_exc = None
    req = google_requests.Request()
    for aud in expected_audiences:
        try:
            claims = id_token.verify_oauth2_token(raw_token, req, audience=aud)
            break
        except Exception as exc:  # noqa: BLE001
            last_exc = exc
            continue

    if claims is None:
        return f"Token verification failed: {last_exc}"

    issuer = claims.get("iss")
    if issuer not in {"https://accounts.google.com", "accounts.google.com"}:
        return "Token issuer is not Google"

    email = claims.get("email")
    email_verified = claims.get("email_verified")
    if not email:
        sub = claims.get("sub", "")
        logger.info("token claims (no email): iss=%s sub=%s azp=%s", claims.get("iss"), sub, claims.get("azp"))
        return "Token does not include a caller email"
    if email_verified is False:
        return "Token email is explicitly not verified"

    if email not in expected_callers:
        return f"Caller {email} is not in EXPECTED_CALLER_SA allowlist"

    return None


# ── OpenClaw invocation ──────────────────────────────────────────────────────


async def _invoke_openclaw(task_text: str) -> str:
    backend = os.getenv("AGENTBOX_BACKEND", "cli").strip().lower()

    if backend == "gateway":
        gateway_url = os.getenv("AGENTBOX_GATEWAY_URL", DEFAULT_GATEWAY_URL).rstrip("/")
        payload = {
            "event": "external_task",
            "text": task_text,
            "source": "a2a-wrapper",
        }
        async with httpx.AsyncClient(timeout=TASK_TIMEOUT_SECONDS) as client:
            resp = await client.post(f"{gateway_url}/system/event", json=payload)
            resp.raise_for_status()
            data = resp.json() if resp.headers.get("content-type", "").startswith("application/json") else {}
            if isinstance(data, dict):
                return str(data.get("text") or data.get("message") or data)
            return str(data)

    agent_name = os.getenv("OPENCLAW_AGENT", "main")
    cmd = ["openclaw", "agent", "--agent", agent_name, "--message", task_text]
    logger.info("invoking openclaw cli: %s", " ".join(cmd[:4] + ["..."]))
    proc = await asyncio.create_subprocess_exec(
        *cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    try:
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=TASK_TIMEOUT_SECONDS)
    except TimeoutError:
        proc.kill()
        await proc.communicate()
        raise RuntimeError("OpenClaw task timed out at 55 minutes")

    out = (stdout or b"").decode("utf-8", errors="replace").strip()
    err = (stderr or b"").decode("utf-8", errors="replace").strip()

    if proc.returncode != 0:
        raise RuntimeError(f"OpenClaw CLI failed ({proc.returncode}): {err or out or 'unknown error'}")

    return out or err or "Task completed"


# ── SSE streaming (A2A v0.2 message/stream) ─────────────────────────────────


async def _stream_message_events(
    rpc_id: Optional[Union[str, int]],
    task_id: str,
    context_id: str,
) -> AsyncGenerator[dict[str, str], None]:
    """Yield SSE events as dicts for EventSourceResponse (matches a2a-sdk pattern)."""
    task = _tasks.get(task_id)
    if task is None:
        yield {"data": _jsonrpc_response(rpc_id, _make_task_obj(task_id, context_id, "failed"))}
        return

    # Wait for the task to complete, then send the completed Task as a single event
    try:
        output = await asyncio.wait_for(asyncio.shield(task), timeout=TASK_TIMEOUT_SECONDS)
        # Send completed Task with artifacts
        yield {"data": _jsonrpc_response(rpc_id, _make_task_obj(task_id, context_id, "completed", text=output))}
        logger.info("task completed task_id=%s mode=stream", task_id)
    except Exception as exc:  # noqa: BLE001
        logger.error("task failed task_id=%s mode=stream error=%s", task_id, exc)
        yield {"data": _jsonrpc_response(rpc_id, _make_task_obj(task_id, context_id, "failed"))}


# ── Routes ───────────────────────────────────────────────────────────────────


@app.get("/.well-known/agent.json")
async def agent_card(request: Request) -> JSONResponse:
    card = dict(_AGENT_CARD_CACHE)
    audience_env = os.getenv("SERVICE_URL") or os.getenv("EXPECTED_AUDIENCE") or ""
    service_url = audience_env.split(",")[0].strip() or str(request.base_url).rstrip("/")
    card["url"] = service_url
    return JSONResponse(content=card)


@app.get("/health")
async def health() -> JSONResponse:
    warnings = []
    errors = []
    if not (os.getenv("EXPECTED_AUDIENCE") or os.getenv("SERVICE_URL")):
        warnings.append("EXPECTED_AUDIENCE not configured (auth disabled)")
    if not os.getenv("EXPECTED_CALLER_SA"):
        warnings.append("EXPECTED_CALLER_SA not configured (auth disabled)")

    backend = os.getenv("AGENTBOX_BACKEND", "cli").strip().lower()
    if backend == "gateway":
        import socket
        from urllib.parse import urlparse
        gateway_url = os.getenv("AGENTBOX_GATEWAY_URL", DEFAULT_GATEWAY_URL).rstrip("/")
        parsed = urlparse(gateway_url)
        gw_host = parsed.hostname or "localhost"
        gw_port = parsed.port or 3000
        try:
            sock = socket.create_connection((gw_host, gw_port), timeout=3)
            sock.close()
        except OSError:
            errors.append(f"OpenClaw gateway not reachable at {gw_host}:{gw_port}")

    ok = not errors
    body: dict = {"status": "ok" if ok else "unhealthy"}
    if errors:
        body["errors"] = errors
    if warnings:
        body["warnings"] = warnings
    return JSONResponse(body, status_code=200 if ok else 503)


@app.post("/", response_model=None)
async def a2a_root(request: Request):
    logger.info("POST / from %s", request.client.host if request.client else "unknown")
    authz_header = request.headers.get("Authorization")
    auth_err = await asyncio.to_thread(_validate_google_token, authz_header)
    if auth_err:
        caller_email = _extract_caller_email_from_bearer(authz_header)
        logger.warning("auth failure caller_email=%s reason=%s", caller_email or "unknown", auth_err)
        return _a2a_error(code=-32000, message=f"Unauthorized: {auth_err}", http_status=401)

    try:
        payload = await request.json()
    except Exception:  # noqa: BLE001
        return _a2a_error(code=-32700, message="Invalid JSON", http_status=400)

    # Log full request for debugging
    logger.info("request body: %s", json.dumps(payload, default=str)[:2000])

    try:
        rpc = JsonRpcRequest.model_validate(payload)
    except Exception as exc:  # noqa: BLE001
        return _a2a_error(code=-32600, message=f"Invalid request: {exc}", http_status=400)

    logger.info("rpc method=%s id=%s params_keys=%s", rpc.method, rpc.id, list(rpc.params.keys()))

    if rpc.jsonrpc != A2A_JSONRPC:
        return _a2a_error(code=-32600, message="jsonrpc must be '2.0'", rpc_id=rpc.id)

    # ── A2A v0.2: message/send and message/stream ───────────────────────
    if rpc.method in ("message/send", "message/stream"):
        msg_data = rpc.params.get("message", {})
        parts = msg_data.get("parts", [])
        task_text = _extract_text_from_parts(parts)
        if not task_text:
            return _a2a_error(code=-32602, message="No text found in message.parts", rpc_id=rpc.id)

        # Inject caller identity so the agent can resolve per-user memory
        caller_email = _extract_caller_email_from_bearer(authz_header)
        if caller_email:
            caller_id = _sanitize_email_for_path(caller_email)
            memory_path = f"memory/a2a/{caller_id}/A2A_MEMORY.md"
            task_text = f"[A2A caller: {caller_email} | user memory: {memory_path}]\n{task_text}"

        task_id = str(uuid.uuid4())
        context_id = rpc.params.get("configuration", {}).get("contextId") or task_id

        task = asyncio.create_task(_invoke_openclaw(task_text))
        _tasks[task_id] = task
        logger.info("task started task_id=%s context_id=%s method=%s text=%s",
                     task_id, context_id, rpc.method, task_text[:100])

        # ── message/stream → SSE (text/event-stream) ─────────────────
        if rpc.method == "message/stream":
            async def _sse_events() -> AsyncGenerator[dict[str, str], None]:
                # 1. Send "working" status-update
                yield {"data": json.dumps({
                    "jsonrpc": A2A_JSONRPC,
                    "id": rpc.id,
                    "result": {
                        "kind": "status-update",
                        "taskId": task_id,
                        "contextId": context_id,
                        "status": {"state": "working"},
                        "final": False,
                    },
                }, ensure_ascii=False)}

                # 2. Wait for completion
                try:
                    output = await asyncio.wait_for(
                        asyncio.shield(task), timeout=TASK_TIMEOUT_SECONDS
                    )
                    logger.info("task completed task_id=%s method=message/stream", task_id)

                    # 3. Send "completed" status-update with agent message
                    yield {"data": json.dumps({
                        "jsonrpc": A2A_JSONRPC,
                        "id": rpc.id,
                        "result": {
                            "kind": "status-update",
                            "taskId": task_id,
                            "contextId": context_id,
                            "status": {
                                "state": "completed",
                                "message": {
                                    "kind": "message",
                                    "role": "agent",
                                    "parts": [{"kind": "text", "text": output}],
                                    "messageId": str(uuid.uuid4()),
                                },
                            },
                            "final": True,
                        },
                    }, ensure_ascii=False)}
                except Exception as exc:  # noqa: BLE001
                    logger.error("task failed task_id=%s error=%s", task_id, exc)
                    yield {"data": json.dumps({
                        "jsonrpc": A2A_JSONRPC,
                        "id": rpc.id,
                        "result": {
                            "kind": "status-update",
                            "taskId": task_id,
                            "contextId": context_id,
                            "status": {"state": "failed"},
                            "final": True,
                        },
                    }, ensure_ascii=False)}

            return EventSourceResponse(_sse_events())

        # ── message/send → plain JSON ────────────────────────────────
        try:
            output = await asyncio.wait_for(task, timeout=TASK_TIMEOUT_SECONDS)
            logger.info("task completed task_id=%s method=message/send", task_id)
            response = {
                "jsonrpc": A2A_JSONRPC,
                "id": rpc.id,
                "result": {
                    "kind": "message",
                    "role": "agent",
                    "parts": [{"kind": "text", "text": output}],
                    "messageId": str(uuid.uuid4()),
                },
            }
            logger.info("response: %s", json.dumps(response, default=str)[:2000])
            return JSONResponse(content=response)
        except Exception as exc:  # noqa: BLE001
            logger.error("task failed task_id=%s error=%s", task_id, exc)
            return _a2a_error(code=-32001, message=f"Task execution failed: {exc}", rpc_id=rpc.id)

    # ── A2A v0.1: tasks/send ────────────────────────────────────────────
    if rpc.method == "tasks/send":
        msg_data = rpc.params.get("message", {})
        parts = msg_data.get("parts", [])
        task_text = _extract_text_from_parts(parts)
        task_id = rpc.params.get("id", str(uuid.uuid4()))
        stream = rpc.params.get("stream", False)

        # Inject caller identity so the agent can resolve per-user memory
        caller_email = _extract_caller_email_from_bearer(authz_header)
        if caller_email:
            caller_id = _sanitize_email_for_path(caller_email)
            memory_path = f"memory/a2a/{caller_id}/A2A_MEMORY.md"
            task_text = f"[A2A caller: {caller_email} | user memory: {memory_path}]\n{task_text}" if task_text else task_text

        if not task_text:
            return _a2a_error(code=-32602, message="User text is required in message.parts", rpc_id=rpc.id)

        existing = _tasks.get(task_id)
        if existing is None or existing.done():
            task = asyncio.create_task(_invoke_openclaw(task_text))
            _tasks[task_id] = task
            logger.info("task started task_id=%s mode=%s", task_id, "stream" if stream else "poll")

        if stream:
            async def legacy_events() -> AsyncGenerator[dict[str, str], None]:
                yield {"data": _jsonrpc_response(rpc.id, _make_task_obj(task_id, task_id, "working"))}
                while True:
                    t = _tasks.get(task_id)
                    if t is None:
                        break
                    if t.done():
                        try:
                            out = t.result()
                            yield {"data": _jsonrpc_response(rpc.id, _make_task_obj(task_id, task_id, "completed", text=out))}
                        except Exception as e:  # noqa: BLE001
                            yield {"data": json.dumps({"jsonrpc": A2A_JSONRPC, "id": rpc.id, "error": {"code": -32001, "message": str(e)}})}
                        return
                    await asyncio.sleep(2)

            return EventSourceResponse(legacy_events())

        return JSONResponse(content={
            "jsonrpc": A2A_JSONRPC,
            "id": rpc.id,
            "result": _make_task_obj(task_id, task_id, "working"),
        })

    # ── A2A v0.1: tasks/get ─────────────────────────────────────────────
    if rpc.method == "tasks/get":
        task_id = rpc.params.get("id", "")
        task = _tasks.get(task_id)
        if task is None:
            return JSONResponse(content={
                "jsonrpc": A2A_JSONRPC,
                "id": rpc.id,
                "result": _make_task_obj(task_id, task_id, "unknown"),
            })

        if not task.done():
            return JSONResponse(content={
                "jsonrpc": A2A_JSONRPC,
                "id": rpc.id,
                "result": _make_task_obj(task_id, task_id, "working"),
            })

        try:
            output = task.result()
            return JSONResponse(content={
                "jsonrpc": A2A_JSONRPC,
                "id": rpc.id,
                "result": _make_task_obj(task_id, task_id, "completed", text=output),
            })
        except Exception as exc:  # noqa: BLE001
            logger.error("task failed while polling task_id=%s error=%s", task_id, exc)
            return _a2a_error(code=-32001, message=f"Task execution failed: {exc}", rpc_id=rpc.id)

    return _a2a_error(code=-32601, message=f"Method not found: {rpc.method}", rpc_id=rpc.id)
