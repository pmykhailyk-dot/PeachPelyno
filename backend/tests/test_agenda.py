from httpx import AsyncClient

MEETING = {
    "title": "Pricing sync",
    "starts_at": "2026-10-19T10:00:00+03:00",
    "ends_at": "2026-10-19T10:45:00+03:00",
    "attendee_count": 5,
}


async def _create_meeting(client: AsyncClient) -> str:
    created = await client.post("/api/meetings", json=MEETING)
    return created.json()["id"]


async def test_get_agenda_404_for_unknown_meeting(client: AsyncClient) -> None:
    response = await client.get("/api/meetings/00000000-0000-4000-8000-000000000000/agenda")
    assert response.status_code == 404


async def test_get_agenda_returns_null_when_none_saved(client: AsyncClient) -> None:
    meeting_id = await _create_meeting(client)
    response = await client.get(f"/api/meetings/{meeting_id}/agenda")
    assert response.status_code == 200
    assert response.json() is None


async def test_save_then_get_agenda(client: AsyncClient) -> None:
    meeting_id = await _create_meeting(client)
    payload = {
        "items": [{"topic": "New Pro tariffs", "owner": "Olena", "minutes": 15}],
        "action_items": [{"task": "Collect competitor comparison", "owner": "Taras", "due": None}],
    }
    saved = await client.put(f"/api/meetings/{meeting_id}/agenda", json=payload)
    assert saved.status_code == 200
    body = saved.json()
    assert body["meeting_id"] == meeting_id
    assert body["items"] == payload["items"]
    assert body["action_items"][0]["task"] == "Collect competitor comparison"
    assert body["ai_suggestion"] is None

    fetched = await client.get(f"/api/meetings/{meeting_id}/agenda")
    assert fetched.status_code == 200
    assert fetched.json()["items"] == payload["items"]


async def test_save_keeps_the_ai_suggestion_next_to_the_correction(client: AsyncClient) -> None:
    meeting_id = await _create_meeting(client)
    ai_suggestion = {
        "title": None,
        "starts_at": None,
        "duration_minutes": 45,
        "items": [{"topic": "New Pro tariffs", "owner": "Olena", "minutes": 15}],
        "action_items": [],
        "language": "uk",
    }
    payload = {
        # The user corrected the owner before saving.
        "items": [{"topic": "New Pro tariffs", "owner": "Olena K.", "minutes": 15}],
        "action_items": [],
        "ai_suggestion": ai_suggestion,
        "ai_model": "us.anthropic.claude-opus-4-5-20251101-v1:0",
        "ai_prompt_version": "agenda-v1",
    }
    saved = await client.put(f"/api/meetings/{meeting_id}/agenda", json=payload)
    assert saved.status_code == 200
    body = saved.json()
    assert body["ai_suggestion"] == ai_suggestion
    assert body["ai_model"] == "us.anthropic.claude-opus-4-5-20251101-v1:0"
    assert body["items"][0]["owner"] == "Olena K."


async def test_save_is_an_upsert(client: AsyncClient) -> None:
    meeting_id = await _create_meeting(client)
    first = {"items": [{"topic": "First draft"}], "action_items": []}
    second = {"items": [{"topic": "Final version"}], "action_items": []}

    await client.put(f"/api/meetings/{meeting_id}/agenda", json=first)
    replaced = await client.put(f"/api/meetings/{meeting_id}/agenda", json=second)

    assert replaced.status_code == 200
    assert replaced.json()["items"][0]["topic"] == "Final version"
    assert len(replaced.json()["items"]) == 1

    fetched = await client.get(f"/api/meetings/{meeting_id}/agenda")
    assert fetched.json()["items"][0]["topic"] == "Final version"


async def test_rejects_empty_topic(client: AsyncClient) -> None:
    meeting_id = await _create_meeting(client)
    bad = {"items": [{"topic": ""}], "action_items": []}
    assert (await client.put(f"/api/meetings/{meeting_id}/agenda", json=bad)).status_code == 422
