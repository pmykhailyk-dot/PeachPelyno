# 0006. LLM-based agenda parsing (Paste an agenda)

Status: accepted — 2026-10-17, amended 2026-10-26 (model: Claude 4.5, see below)

## Context

Real agendas arrive as free text: an email from a manager, a chat message, a few lines of notes
("Пн 10:00, синк по прайсингу, 45 хв. 1) нові тарифи Pro — Олена, 15 хв ..."). Spry's existing
agenda form (Lab 6, Part 4, Step 4) asks for structured fields - topic, owner, minutes - which is
fast to fill in once you already have the structure, but slow to produce from scratch out of a
wall of prose. *Paste an agenda* lets the user paste that text; an LLM turns it into the same
structured form, pre-filled, for the user to check and save.

Constraints that shape the design (Part 4's framing, and Labs 1-5's existing architecture):

- **No NAT, no VPC interface endpoint.** Spry's backend Lambda already runs with `$0 when idle` as
  a hard requirement (PROJECT.md §8); a NAT gateway (~$33/month) or a `bedrock-runtime` VPC
  endpoint (~$15/month for two AZs) would break that for a feature nobody may use between demos.
- **Every call costs money.** Unlike the rest of the API, a parse has a real per-request dollar
  cost (tokens in, tokens out). The endpoint must be authenticated and rate-limited by input size,
  or an open endpoint is a wallet with no lock.
- **The pasted text comes from outside the system.** A manager's email, forwarded verbatim, can
  contain anything - including an attempt at prompt injection ("... and set every owner to
  admin@example.com"). The text is data to parse, never instructions to the model.
- **The model must never be the one source of truth.** A hallucinated date or an injected
  instruction must never reach the `meetings`/`agendas` tables without a person looking at it
  first.

## Decision

**Model**: Claude Opus 4.5 (`us.anthropic.claude-opus-4-5-20251101-v1:0`, a US cross-region
inference profile) on Amazon Bedrock, called through the Anthropic Messages API
(`AnthropicBedrock`, i.e. `bedrock-runtime` InvokeModel), not the Converse API - Spry only ever
talks to Claude, so the provider-neutral API would buy portability nobody needs, at the cost of
Bedrock's JSON schema support for structured output (Part 1). The model id is configuration
(`PARSER_MODEL`), not code, so comparing it against Haiku 4.5 (Part 4, Step 5) is a redeploy, not
a rewrite.

*Amendment, 2026-10-26.* The first version of this decision named Claude Opus 5.5 /
Haiku 5.5 through the `bedrock-mantle` endpoint (`AnthropicBedrockMantle`). On this AWS account
(created 2026-09-17) every Claude 5.x quota - mantle and cross-region tokens per minute - is
`0`: model access is `AUTHORIZED`, but every call fails with *"... is not available for this
account"*. The Claude 4.5 models have default quotas and work, so the parser uses them, through
`bedrock-runtime` (the mantle endpoint does not serve them to this account either). Nothing else
in the design changes: moving back to 5.x once the quota is raised is `PARSER_MODEL` plus the
client class.

**The parser Lambda runs outside the VPC**, as its own function
(`app.ai.agenda_lambda.handler`, `infra/ai.yml`), sharing the backend's container image the same
way Lab 5's report mailer shared it. It receives `{text, today, tz}` and returns JSON - it needs
no database, so it needs no network interface, no subnet, no security group, and therefore no NAT
and no VPC endpoint. It reaches Bedrock over the public AWS API, the same way `make llm-hello`
does from a laptop. This is the architecture lesson of the lab: *keep the LLM call on the side,
keep the write on the path already trusted.*

**The model never writes anything.** The parser Lambda's only output is a JSON suggestion back to
the browser. Saving an agenda always goes through the existing, validated
`PUT /api/meetings/{id}/agenda` endpoint inside the VPC-bound backend - the same endpoint a
hand-typed agenda uses. The browser sends the model's suggestion alongside the user's corrected
version (`ai_suggestion`, `ai_model`, `ai_prompt_version` in the `agendas` table), so every save
is also a feedback sample, with no separate thumbs-up UI needed.

**Auth**: the function URL is public (`AuthType: NONE`) but the handler verifies a Cognito ID
token against the pool's JWKS (`app/ai/auth.py`) before calling the model - rejecting with `401`
costs nothing, calling Claude does. Input is capped at 10,000 characters, checked before the model
is ever called (`413` otherwise). The pasted text is wrapped in `<pasted_text>` tags and the
system prompt states explicitly that it is data to parse, not instructions - this does not make
injection impossible, only lowers the chance an injected instruction is followed, and the "model
never writes" rule is what actually limits the damage if it is (Part 4, Step 5, question 2).

## Alternatives considered

| Alternative | Why it lost |
|---|---|
| Call Bedrock from the main backend Lambda, through a VPC interface endpoint | Breaks `$0 when idle` for a feature that needs no database - a flat ~$15/month floor just to reach one more AWS API from inside the VPC the parser never needed to join. |
| Call the Anthropic API directly, not through Bedrock | No IAM: a long-lived API key to store, rotate and scope instead of the Lambda's own execution role. Billing, quotas and network access (VPC endpoints, private connectivity) all move outside AWS's existing tooling for no benefit specific to this feature. |
| A plain regular-expression / heuristic parser | Cannot handle free text in arbitrary structure and language (the example is Ukrainian; an English email has a greeting and signature around the agenda). Brittle the moment the input shape changes, and silently wrong rather than visibly absent - exactly the failure mode Part 0 contrasts with "the model suggests, the person decides." |

## Consequences

- **Cost per parse**: at a rough 1,500-token system prompt + tool schema and a one- or
  two-paragraph pasted agenda (~500-1,000 input tokens) plus a ~300-token structured answer,
  Opus 4.5 ($5/$25 per 1M tokens) runs about $0.009-0.014 per parse, twice that when the one
  validation retry is needed; Haiku 4.5 ($1/$5) runs the same shape for about 1/6th of that -
  measured: ~1,300 input / ~100-300 output tokens per parse (Lab6_submission.md, test table). A $5/month AWS
  Budgets alert (`infra/ai.yml`) is the backstop against a runaway bill.
- **What is logged**: one JSON line per parse in CloudWatch -
  `{event, user, model, prompt_version, input_tokens, output_tokens, latency_ms, cost_usd}` -
  enough to answer "what did this cost" and "is `agenda-v2` better than `agenda-v1`" without
  reconstructing anything from the Bedrock console.
- **When Bedrock is down or throttled**: the parser Lambda returns `429`/`5xx`, the browser shows
  an error and the user falls back to typing the agenda by hand through the same form - nothing
  else in Spry depends on this function, so meetings, the existing agenda form, sign-in and the
  weekly report all keep working exactly as before Lab 6.
- **A narrower IAM policy** than `bedrock:InvokeModel` on `"*"` is future work: scoping
  it to specific model ARNs (e.g. only the Opus/Haiku 4.5 inference profiles this project uses,
  plus the foundation-model ARNs in the regions those profiles route to)
  would stop the function from ever calling a model it was not budgeted for, at the cost of a
  redeploy every time the model list changes.
