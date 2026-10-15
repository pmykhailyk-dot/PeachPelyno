"""The weekly meetings report - no AWS in here, on purpose (Lab 5, Step 1).

``build_weekly_report`` never asks what "now" is: the week is a parameter, so
the same call always produces the same bytes, and the caller - a Lambda
handler, a test, a REPL - decides which week. That is what makes
``report_key`` stable and the whole pipeline idempotent: building the report
for one week twice overwrites one S3 object instead of creating two.
"""

import asyncio
import csv
import io
import re
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import select

from app.db import SessionFactory
from app.models import Meeting

_WEEK_RE = re.compile(r"^(?P<year>\d{4})-W(?P<week>\d{2})$")


def previous_iso_week(today: date | None = None) -> str:
    """The ISO week (e.g. "2026-W39") that ended before the current one."""
    today = today or datetime.now(UTC).date()
    monday_this_week = today - timedelta(days=today.weekday())
    monday_last_week = monday_this_week - timedelta(days=7)
    iso_year, iso_week, _ = monday_last_week.isocalendar()
    return f"{iso_year}-W{iso_week:02d}"


def report_key(week: str) -> str:
    """The S3 key a report for this week always lands at."""
    return f"reports/{week}.csv"


def _week_bounds(week: str) -> tuple[datetime, datetime]:
    """[start, end) of the ISO week, as UTC instants - Monday 00:00 to the next Monday."""
    match = _WEEK_RE.match(week)
    if not match:
        raise ValueError(f"not an ISO week, expected e.g. '2026-W40': {week!r}")
    monday = date.fromisocalendar(int(match["year"]), int(match["week"]), 1)
    start = datetime(monday.year, monday.month, monday.day, tzinfo=UTC)
    return start, start + timedelta(days=7)


@dataclass
class _Totals:
    meeting_count: int
    total_hours: float


def _hours(meeting: Meeting) -> float:
    return (meeting.ends_at - meeting.starts_at).total_seconds() / 3600


async def _meetings_between(session, start: datetime, end: datetime) -> list[Meeting]:
    result = await session.execute(
        select(Meeting).where(Meeting.starts_at >= start, Meeting.starts_at < end)
    )
    return list(result.scalars())


def _totals(meetings: list[Meeting]) -> _Totals:
    return _Totals(
        meeting_count=len(meetings),
        total_hours=round(sum(_hours(m) for m in meetings), 2),
    )


def _render_csv(week: str, this_week: _Totals, last_week: _Totals, longest: list[Meeting]) -> bytes:
    buffer = io.StringIO()
    writer = csv.writer(buffer)

    writer.writerow(["week", week])
    writer.writerow([])
    writer.writerow(["metric", "this_week", "last_week", "change"])
    writer.writerow(
        [
            "meetings",
            this_week.meeting_count,
            last_week.meeting_count,
            this_week.meeting_count - last_week.meeting_count,
        ]
    )
    writer.writerow(
        [
            "hours",
            this_week.total_hours,
            last_week.total_hours,
            round(this_week.total_hours - last_week.total_hours, 2),
        ]
    )
    writer.writerow([])
    writer.writerow(["top 5 longest meetings this week"])
    writer.writerow(["title", "starts_at", "duration_hours", "attendees"])
    for meeting in longest:
        writer.writerow(
            [
                meeting.title,
                meeting.starts_at.isoformat(),
                round(_hours(meeting), 2),
                meeting.attendee_count,
            ]
        )

    return buffer.getvalue().encode("utf-8")


async def _collect(week: str) -> bytes:
    start, end = _week_bounds(week)
    previous_start, previous_end = start - timedelta(days=7), start

    async with SessionFactory() as session:
        this_week_meetings = await _meetings_between(session, start, end)
        last_week_meetings = await _meetings_between(session, previous_start, previous_end)

    longest = sorted(this_week_meetings, key=_hours, reverse=True)[:5]
    return _render_csv(week, _totals(this_week_meetings), _totals(last_week_meetings), longest)


def build_weekly_report(week: str) -> bytes:
    """Query the meetings of one ISO week (e.g. "2026-W40") and return the CSV."""
    return asyncio.run(_collect(week))
