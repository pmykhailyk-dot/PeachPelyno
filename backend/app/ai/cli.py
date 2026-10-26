"""Run from the laptop, against real Bedrock credentials (Lab 6, Part 1 + Part 4, Step 2).

    make llm-hello             # the first snippet from Part 1
    make parse TEXT="..."      # app.ai.agenda.parse_agenda on pasted text

Needs model access granted in Bedrock -> Model catalog (us-east-1) and usable
AWS credentials - the same AWS_PROFILE / AWS_* keys scripts/deploy-*.sh reads
from .env.
"""

import json
import sys
from datetime import date

from anthropic import AnthropicBedrock

from app.ai.agenda import AgendaParseError, cost_usd, parse_agenda
from app.config import get_settings


def hello() -> None:
    client = AnthropicBedrock(aws_region="us-east-1")
    msg = client.messages.create(
        model=get_settings().parser_model,
        max_tokens=1024,
        messages=[{"role": "user", "content": "In one sentence: what is an ISO week?"}],
    )
    text = next(b.text for b in msg.content if b.type == "text")
    print(text)
    print(
        f"stop_reason={msg.stop_reason} "
        f"input_tokens={msg.usage.input_tokens} output_tokens={msg.usage.output_tokens}"
    )


def parse(text: str) -> None:
    today = date.today()
    tz = "Europe/Kyiv"
    try:
        agenda, usage = parse_agenda(text, today, tz)
    except AgendaParseError as e:
        print(f"error: {e}", file=sys.stderr)
        sys.exit(1)

    print(json.dumps(agenda.model_dump(mode="json"), indent=2, ensure_ascii=False))
    settings = get_settings()
    print(
        f"\nmodel={settings.parser_model} input_tokens={usage['input_tokens']} "
        f"output_tokens={usage['output_tokens']} "
        f"cost_usd={cost_usd(settings.parser_model, usage):.6f}"
    )


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] not in {"hello", "parse"}:
        print("usage: python -m app.ai.cli hello|parse [TEXT]", file=sys.stderr)
        sys.exit(2)
    if sys.argv[1] == "hello":
        hello()
        return
    if len(sys.argv) < 3 or not sys.argv[2].strip():
        print("usage: python -m app.ai.cli parse TEXT", file=sys.stderr)
        sys.exit(2)
    parse(sys.argv[2])


if __name__ == "__main__":
    main()
