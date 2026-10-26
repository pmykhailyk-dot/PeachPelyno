import uuid

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import select

from app.db import SessionDep
from app.models import Meeting
from app.schemas import AgendaRead, AgendaSave
from app.services import agenda as agenda_service

router = APIRouter(prefix="/meetings/{meeting_id}/agenda", tags=["agenda"])


async def _require_meeting(session: SessionDep, meeting_id: uuid.UUID) -> None:
    exists = await session.execute(select(Meeting.id).where(Meeting.id == meeting_id))
    if exists.scalar_one_or_none() is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Meeting not found")


@router.get("", response_model=AgendaRead | None, summary="Get a meeting's agenda")
async def get_agenda(meeting_id: uuid.UUID, session: SessionDep) -> AgendaRead | None:
    await _require_meeting(session, meeting_id)
    agenda = await agenda_service.get_agenda(session, meeting_id)
    return AgendaRead.model_validate(agenda) if agenda else None


@router.put("", response_model=AgendaRead, summary="Save (create or replace) a meeting's agenda")
async def save_agenda(
    meeting_id: uuid.UUID, payload: AgendaSave, session: SessionDep
) -> AgendaRead:
    await _require_meeting(session, meeting_id)
    agenda = await agenda_service.save_agenda(session, meeting_id, payload)
    return AgendaRead.model_validate(agenda)
