from httpx import AsyncClient

MEETING = {
    "title": "Weekly sync",
    "starts_at": "2026-10-01T10:00:00+03:00",
    "ends_at": "2026-10-01T10:30:00+03:00",
    "attendee_count": 5,
}


async def test_list_starts_empty(client: AsyncClient) -> None:
    response = await client.get("/api/meetings")
    assert response.status_code == 200
    assert response.json() == []


async def test_create_then_list(client: AsyncClient) -> None:
    created = await client.post("/api/meetings", json=MEETING)
    assert created.status_code == 201
    body = created.json()
    assert body["title"] == "Weekly sync"
    assert body["attendee_count"] == 5
    assert set(body) == {"id", "title", "starts_at", "ends_at", "attendee_count", "created_at"}

    listed = (await client.get("/api/meetings")).json()
    assert [m["id"] for m in listed] == [body["id"]]


async def test_list_is_ordered_by_start(client: AsyncClient) -> None:
    later = {
        **MEETING,
        "title": "Later",
        "starts_at": "2026-10-02T09:00:00Z",
        "ends_at": "2026-10-02T10:00:00Z",
    }
    earlier = {
        **MEETING,
        "title": "Earlier",
        "starts_at": "2026-09-30T09:00:00Z",
        "ends_at": "2026-09-30T10:00:00Z",
    }
    await client.post("/api/meetings", json=later)
    await client.post("/api/meetings", json=earlier)
    titles = [m["title"] for m in (await client.get("/api/meetings")).json()]
    assert titles == ["Earlier", "Later"]


async def test_rejects_end_before_start(client: AsyncClient) -> None:
    bad = {**MEETING, "ends_at": "2026-10-01T09:00:00+03:00"}
    assert (await client.post("/api/meetings", json=bad)).status_code == 422


async def test_rejects_naive_datetime(client: AsyncClient) -> None:
    bad = {**MEETING, "starts_at": "2026-10-01T10:00:00"}
    assert (await client.post("/api/meetings", json=bad)).status_code == 422


async def test_rejects_negative_attendees_and_empty_title(client: AsyncClient) -> None:
    assert (
        await client.post("/api/meetings", json={**MEETING, "attendee_count": -1})
    ).status_code == 422
    assert (await client.post("/api/meetings", json={**MEETING, "title": ""})).status_code == 422
