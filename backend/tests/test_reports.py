import asyncio
from collections.abc import AsyncIterator
from datetime import UTC, date, datetime, timedelta

import pytest
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker

from app.models import Meeting
from app.reports.weekly import build_weekly_report, previous_iso_week, report_key


@pytest.fixture
async def ready(engine: AsyncEngine) -> AsyncIterator[AsyncEngine]:
    """Just the schema, created - build_weekly_report calls asyncio.run() itself,
    so the tests that use it have to be plain sync functions with no event loop
    of their own already running, which rules out an async fixture that hands
    them a session.
    """
    yield engine
    async with engine.begin() as conn:
        await conn.execute(Meeting.__table__.delete())


def _meeting(title: str, starts_at: datetime, hours: float, attendees: int = 3) -> Meeting:
    return Meeting(
        title=title,
        starts_at=starts_at,
        ends_at=starts_at + timedelta(hours=hours),
        attendee_count=attendees,
    )


def _seed(engine: AsyncEngine, meetings: list[Meeting]) -> None:
    """Commits for real, through the test's own engine - a different connection
    pool than app.db.SessionFactory, but the same database, so build_weekly_report
    sees the rows once they are actually committed."""

    async def _insert() -> None:
        factory = async_sessionmaker(bind=engine, expire_on_commit=False, class_=AsyncSession)
        async with factory() as session:
            session.add_all(meetings)
            await session.commit()

    asyncio.run(_insert())


def test_build_weekly_report_counts_and_ranks(ready: AsyncEngine) -> None:
    # 2026-W40 runs Mon 2026-09-28 00:00 UTC .. Mon 2026-10-05 00:00 UTC.
    _seed(
        ready,
        [
            _meeting("Standup", datetime(2026, 9, 28, 9, tzinfo=UTC), 0.5),
            _meeting("Planning", datetime(2026, 9, 29, 10, tzinfo=UTC), 2),
            _meeting("Deep dive", datetime(2026, 9, 30, 14, tzinfo=UTC), 3),
            _meeting("Retro", datetime(2026, 9, 21, 9, tzinfo=UTC), 1),  # last week
        ],
    )

    text = build_weekly_report("2026-W40").decode("utf-8")

    assert "meetings,3,1,2" in text
    assert "hours,5.5,1.0,4.5" in text
    assert text.index("Deep dive") < text.index("Planning") < text.index("Standup")


def test_build_weekly_report_is_idempotent(ready: AsyncEngine) -> None:
    _seed(ready, [_meeting("Standup", datetime(2026, 9, 28, 9, tzinfo=UTC), 0.5)])

    assert build_weekly_report("2026-W40") == build_weekly_report("2026-W40")


def test_report_key_is_stable() -> None:
    assert report_key("2026-W40") == "reports/2026-W40.csv"
    assert report_key("2026-W40") == report_key("2026-W40")


def test_previous_iso_week() -> None:
    assert previous_iso_week(date(2026, 10, 8)) == "2026-W40"  # Thu, in W41
    assert previous_iso_week(date(2026, 10, 12)) == "2026-W41"  # Mon, in W42


def test_build_weekly_report_rejects_a_malformed_week() -> None:
    with pytest.raises(ValueError, match="ISO week"):
        build_weekly_report("not-a-week")
