import asyncio
import base64
import json
import logging
import os
from pathlib import Path
from typing import Any, AsyncIterator, Dict, List, Optional, Union

import httpx
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, StreamingResponse
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token
from pydantic import BaseModel, Field


A2A_JSONRPC = "2.0"
TASK_TIMEOUT_SECONDS = 55 * 60  # 55 min for Cloud Run max window
DEFAULT_GATEWAY_URL = "http://localhost:3000"
CARD_PATH = Path(__file__).with_name("agent_card.json")

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
logger = logging.getLogger("agentbox.a2a")
_AGENT_CARD_CACHE: dict = json.loads(CARD_PATH.read_text(encoding="utf-8"))
_tasks: dict = {}


class Part(BaseModel):
    type: str
    text: Optional[str] = None


class Message(BaseModel):
    role: str
    parts: List[Part]


class SendParams(BaseModel):
    id: str
    message: Message
    stream: bool = False


class GetParams(BaseModel):
    id: str


class JsonRpcRequest(BaseModel):
    jsonrpc: str = Field(default=A2A_JSONRPC)
    id: Optional[Union[str, int]] = None
    method: str
    params: Dict[str, Any]


app = FastAPI(title="AgentBox A2A Wrapper", version="1.0.0")


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


def _a2a_result(
    rpc_id: Optional[Union[str, int]],
    task_id: str,
    text: Optional[str] = None,
    state: str = "completed",
) -> Dict[str, Any]:
    result: Dict[str, Any] = {
        "jsonrpc": A2A_JSONRPC,
        "id": rpc_id,
        "result": {
            "id": task_id,
            "status": {"state": state},
        },
    }
    if text is not None:
        result["result"]["artifacts"] = [
            {
                "name": "result",
                "parts": [{"type": "text", "text": text}],
            }
        ]
    return result


def _extract_user_text(message: Message) -> str:
    chunks = [p.text for p in message.parts if p.type == "text" and p.text]
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


def _validate_google_token(authz_header: Optional[str]) -> Optional[str]:
    if not authz_header or not authz_header.startswith("Bearer "):
        return "Missing or invalid Authorization header"

    raw_token = authz_header.split(" ", 1)[1].strip()
    expected_audience = os.getenv("EXPECTED_AUDIENCE") or os.getenv("SERVICE_URL")
    expected_callers = {
        item.strip()
        for item in os.getenv("EXPECTED_CALLER_SA", "").split(",")
        if item.strip()
    }

    if not expected_audience:
        return "Server is missing EXPECTED_AUDIENCE or SERVICE_URL configuration"
    if not expected_callers:
        return "Server is missing EXPECTED_CALLER_SA configuration"

    try:
        req = google_requests.Request()
        claims = id_token.verify_oauth2_token(raw_token, req, audience=expected_audience)
    except Exception as exc:  # noqa: BLE001
        return f"Token verification failed: {exc}"

    issuer = claims.get("iss")
    if issuer not in {"https://accounts.google.com", "accounts.google.com"}:
        return "Token issuer is not Google"

    email = claims.get("email")
    email_verified = claims.get("email_verified")
    if not email or not email_verified:
        return "Token does not include a verified caller email"

    if email not in expected_callers:
        return f"Caller {email} is not in EXPECTED_CALLER_SA allowlist"

    return None


async def _invoke_openclaw(task_text: str) -> str:
    backend = os.getenv("AGENTBOX_BACKEND", "cli").strip().lower()
    gateway_url = os.getenv("AGENTBOX_GATEWAY_URL", DEFAULT_GATEWAY_URL).rstrip("/")

    if backend == "gateway":
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

    cmd = ["openclaw", "system", "event", "--text", task_text, "--mode", "now"]
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

    return out or err or "Task accepted by OpenClaw"


async def _stream_a2a_response(rpc_id: Optional[Union[str, int]], task_id: str) -> AsyncIterator[bytes]:
    started = _a2a_result(rpc_id=rpc_id, task_id=task_id, text="Task is running", state="working")
    yield f"data: {json.dumps(started)}\n\n".encode("utf-8")

    while True:
        task = _tasks.get(task_id)
        if task is None:
            unknown = _a2a_result(rpc_id=rpc_id, task_id=task_id, state="unknown")
            yield f"data: {json.dumps(unknown)}\n\n".encode("utf-8")
            return

        if task.done():
            try:
                output = task.result()
                finished = _a2a_result(rpc_id=rpc_id, task_id=task_id, text=output, state="completed")
                yield f"data: {json.dumps(finished)}\n\n".encode("utf-8")
                logger.info("task completed task_id=%s mode=stream", task_id)
            except Exception as exc:  # noqa: BLE001
                logger.error("task failed task_id=%s mode=stream error=%s", task_id, exc)
                err = {
                    "jsonrpc": A2A_JSONRPC,
                    "id": rpc_id,
                    "error": {"code": -32001, "message": f"Task execution failed: {exc}"},
                }
                yield f"data: {json.dumps(err)}\n\n".encode("utf-8")
            return

        await asyncio.sleep(2)


@app.get("/.well-known/agent.json")
async def agent_card(request: Request) -> JSONResponse:
    card = dict(_AGENT_CARD_CACHE)
    service_url = os.getenv("SERVICE_URL") or os.getenv("EXPECTED_AUDIENCE") or str(request.base_url).rstrip("/")
    card["url"] = service_url
    return JSONResponse(content=card)


@app.get("/health")
async def health() -> JSONResponse:
    issues = []
    if not (os.getenv("EXPECTED_AUDIENCE") or os.getenv("SERVICE_URL")):
        issues.append("EXPECTED_AUDIENCE not configured")
    if not os.getenv("EXPECTED_CALLER_SA"):
        issues.append("EXPECTED_CALLER_SA not configured")
    ok = not issues
    return JSONResponse({"status": "ok" if ok else "misconfigured", "issues": issues}, status_code=200 if ok else 500)


@app.post("/")
async def a2a_root(request: Request) -> JSONResponse | StreamingResponse:
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

    try:
        rpc = JsonRpcRequest.model_validate(payload)
    except Exception as exc:  # noqa: BLE001
        return _a2a_error(code=-32600, message=f"Invalid request: {exc}", http_status=400)

    if rpc.jsonrpc != A2A_JSONRPC:
        return _a2a_error(code=-32600, message="jsonrpc must be '2.0'", rpc_id=rpc.id)

    if rpc.method == "tasks/send":
        try:
            params = SendParams.model_validate(rpc.params)
        except Exception as exc:  # noqa: BLE001
            return _a2a_error(code=-32602, message=f"Invalid params: {exc}", rpc_id=rpc.id)

        task_text = _extract_user_text(params.message)
        if not task_text:
            return _a2a_error(code=-32602, message="User text is required in message.parts", rpc_id=rpc.id)

        task = _tasks.get(params.id)
        if task is None or task.done():
            task = asyncio.create_task(_invoke_openclaw(task_text))
            _tasks[params.id] = task
            logger.info("task started task_id=%s mode=%s", params.id, "stream" if params.stream else "poll")

            def _done_callback(done_task: asyncio.Task, task_id: str = params.id) -> None:
                try:
                    done_task.result()
                    logger.info("task completed task_id=%s", task_id)
                except Exception as exc:  # noqa: BLE001
                    logger.error("task failed task_id=%s error=%s", task_id, exc)

            task.add_done_callback(_done_callback)

        if params.stream:
            return StreamingResponse(
                _stream_a2a_response(rpc.id, params.id),
                media_type="text/event-stream",
                headers={"Cache-Control": "no-cache", "Connection": "keep-alive"},
            )

        return JSONResponse(content=_a2a_result(rpc.id, params.id, state="working"))

    if rpc.method == "tasks/get":
        try:
            params = GetParams.model_validate(rpc.params)
        except Exception as exc:  # noqa: BLE001
            return _a2a_error(code=-32602, message=f"Invalid params: {exc}", rpc_id=rpc.id)

        task = _tasks.get(params.id)
        if task is None:
            return JSONResponse(content=_a2a_result(rpc.id, params.id, state="unknown"))

        if not task.done():
            return JSONResponse(content=_a2a_result(rpc.id, params.id, state="working"))

        try:
            output = task.result()
            return JSONResponse(content=_a2a_result(rpc.id, params.id, text=output, state="completed"))
        except Exception as exc:  # noqa: BLE001
            logger.error("task failed while polling task_id=%s error=%s", params.id, exc)
            return _a2a_error(code=-32001, message=f"Task execution failed: {exc}", rpc_id=rpc.id)

    return _a2a_error(code=-32601, message=f"Method not found: {rpc.method}", rpc_id=rpc.id)
