import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Agenda
from app.schemas import AgendaSave


async def get_agenda(session: AsyncSession, meeting_id: uuid.UUID) -> Agenda | None:
    result = await session.execute(select(Agenda).where(Agenda.meeting_id == meeting_id))
    return result.scalar_one_or_none()


async def save_agenda(session: AsyncSession, meeting_id: uuid.UUID, payload: AgendaSave) -> Agenda:
    """Create or overwrite the one agenda a meeting can have.

    This is the only endpoint allowed to write an agenda - the parser Lambda
    never does (Lab 6, Part 4, Step 4: "the model never writes anything").
    """
    agenda = await get_agenda(session, meeting_id)
    values = {
        "items": [item.model_dump(mode="json") for item in payload.items],
        "action_items": [item.model_dump(mode="json") for item in payload.action_items],
        "ai_suggestion": payload.ai_suggestion,
        "ai_model": payload.ai_model,
        "ai_prompt_version": payload.ai_prompt_version,
    }
    if agenda is None:
        agenda = Agenda(meeting_id=meeting_id, **values)
        session.add(agenda)
    else:
        for key, value in values.items():
            setattr(agenda, key, value)
    await session.flush()
    await session.refresh(agenda)
    return agenda
