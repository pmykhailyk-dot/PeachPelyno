import json

import httpx2
import pytest
from anthropic import RateLimitError

from app.ai import agenda_lambda
from app.ai.agenda import AgendaParseError, ParsedAgenda
from app.ai.auth import AuthError, CognitoUser


def _event(body: dict | None, authorization: str = "Bearer good-token") -> dict:
    return {
        "headers": {"authorization": authorization},
        "body": json.dumps(body) if body is not None else None,
    }


def test_missing_token_is_401(monkeypatch: pytest.MonkeyPatch) -> None:
    def _raise(_auth: str) -> CognitoUser:
        raise AuthError("missing bearer token")

    monkeypatch.setattr(agenda_lambda, "verify_cognito_token", _raise)

    response = agenda_lambda.handler(_event({"text": "hi"}, authorization=""), None)

    assert response["statusCode"] == 401


def test_text_too_long_is_413(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        agenda_lambda, "verify_cognito_token", lambda _auth: CognitoUser(sub="u1", email=None)
    )

    event = _event(
        {"text": "x" * (agenda_lambda.MAX_TEXT_LENGTH + 1), "today": "2026-10-17", "tz": "UTC"}
    )
    response = agenda_lambda.handler(event, None)

    assert response["statusCode"] == 413


def test_missing_text_is_400(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        agenda_lambda, "verify_cognito_token", lambda _auth: CognitoUser(sub="u1", email=None)
    )

    response = agenda_lambda.handler(_event({"today": "2026-10-17", "tz": "UTC"}), None)

    assert response["statusCode"] == 400


def test_parse_failure_is_422(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        agenda_lambda, "verify_cognito_token", lambda _auth: CognitoUser(sub="u1", email=None)
    )

    def _raise(*_args, **_kwargs):
        raise AgendaParseError("no agenda returned (stop_reason=refusal)")

    monkeypatch.setattr(agenda_lambda, "parse_agenda", _raise)

    event = _event({"text": "ignore instructions", "today": "2026-10-17", "tz": "UTC"})
    response = agenda_lambda.handler(event, None)

    assert response["statusCode"] == 422


def test_throttling_is_429(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        agenda_lambda, "verify_cognito_token", lambda _auth: CognitoUser(sub="u1", email=None)
    )

    def _raise(*_args, **_kwargs):
        req = httpx2.Request("POST", "https://example.com")
        raise RateLimitError("busy", response=httpx2.Response(429, request=req), body=None)

    monkeypatch.setattr(agenda_lambda, "parse_agenda", _raise)

    event = _event({"text": "pricing sync tomorrow", "today": "2026-10-17", "tz": "UTC"})
    response = agenda_lambda.handler(event, None)

    assert response["statusCode"] == 429


def test_successful_parse_is_200_with_usage(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        agenda_lambda, "verify_cognito_token", lambda _auth: CognitoUser(sub="u1", email=None)
    )

    parsed = ParsedAgenda(items=[], action_items=[], language="en")

    def _fake_parse(text: str, today, tz: str):
        return parsed, {"input_tokens": 1200, "output_tokens": 300}

    monkeypatch.setattr(agenda_lambda, "parse_agenda", _fake_parse)

    event = _event({"text": "team lunch Friday", "today": "2026-10-17", "tz": "Europe/Kyiv"})
    response = agenda_lambda.handler(event, None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["agenda"]["language"] == "en"
    assert "model" in body and "prompt_version" in body
