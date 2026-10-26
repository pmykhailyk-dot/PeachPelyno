"""Lambda entry point for the agenda-parser (Lab 6, Part 4, Step 3).

Outside the VPC and stateless: text in, JSON out, no database. Reused from
the backend's image, a different handler - see infra/ai.yml
(``ImageConfig: Command: ["app.ai.agenda_lambda.handler"]``), the same split
Lab 5 used for the report mailer.

Auth is required because every call costs money: the bearer token is checked
against Cognito's JWKS (Lab 4) before anything reaches the model. One JSON
log line per parse carries the model, prompt version, token usage, latency
and an estimated cost - this is the fourth item of the lab's submission.
"""

import json
import logging
import os
import time
from datetime import date
from typing import Any

from anthropic import RateLimitError

from app.ai.agenda import PROMPT_VERSION, AgendaParseError, cost_usd, parse_agenda
from app.ai.auth import AuthError, verify_cognito_token
from app.config import get_settings

logger = logging.getLogger(__name__)
logging.getLogger().setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

# Rejected before it ever reaches the model - a cheap, synchronous guard
# against someone pasting a whole novel into the box (Part 4, Step 3).
MAX_TEXT_LENGTH = 10_000


def _response(status_code: int, body: dict[str, Any]) -> dict[str, Any]:
    # CORS headers come from the function URL's own Cors config (infra/ai.yml),
    # not from here - adding them twice would conflict.
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}

    try:
        user = verify_cognito_token(headers.get("authorization", ""))
    except AuthError as e:
        logger.info(json.dumps({"event": "agenda_parse_rejected", "reason": str(e)}))
        return _response(401, {"error": "unauthorized"})

    try:
        body = json.loads(event.get("body") or "{}")
    except json.JSONDecodeError:
        return _response(400, {"error": "invalid JSON body"})

    text = body.get("text")
    if not isinstance(text, str) or not text.strip():
        return _response(400, {"error": "text is required"})
    if len(text) > MAX_TEXT_LENGTH:
        return _response(413, {"error": f"text is too long (max {MAX_TEXT_LENGTH} characters)"})

    try:
        today = date.fromisoformat(body["today"])
    except KeyError, TypeError, ValueError:
        today = date.today()
    tz = body.get("tz") or "UTC"

    settings = get_settings()
    started = time.monotonic()

    try:
        agenda, usage = parse_agenda(text, today, tz)
    except RateLimitError:
        logger.warning(json.dumps({"event": "agenda_parse_throttled", "user": user.sub}))
        return _response(429, {"error": "the model is busy, try again shortly"})
    except AgendaParseError as e:
        logger.info(
            json.dumps(
                {
                    "event": "agenda_parse_failed",
                    "user": user.sub,
                    "model": settings.parser_model,
                    "prompt_version": PROMPT_VERSION,
                    "error": str(e),
                    **e.usage,
                    "latency_ms": int((time.monotonic() - started) * 1000),
                    "cost_usd": round(cost_usd(settings.parser_model, e.usage), 6),
                }
            )
        )
        return _response(422, {"error": str(e)})

    usage_log = {
        "event": "agenda_parsed",
        "user": user.sub,
        "model": settings.parser_model,
        "prompt_version": PROMPT_VERSION,
        **usage,
        "latency_ms": int((time.monotonic() - started) * 1000),
        "cost_usd": round(cost_usd(settings.parser_model, usage), 6),
    }
    logger.info(json.dumps(usage_log))

    return _response(
        200,
        {
            "agenda": agenda.model_dump(mode="json"),
            "model": settings.parser_model,
            "prompt_version": PROMPT_VERSION,
        },
    )
