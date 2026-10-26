# Spry — container diagram (C4, level 2)

Updated for Lab 6, Part 4, Step 6: adds the agenda-parser Lambda and Amazon Bedrock, and the two
new arrows - **parse** (browser → parser → Bedrock, outside the VPC) and **save** (browser → API →
Aurora, same validated path every other write already uses).

Lab 1's original diagram was built outside this repository; this Mermaid version is the
versioned, up-to-date replacement checked in with the code it describes; re-render it with any
Mermaid-compatible viewer (GitHub renders it inline, mermaid.live, the `artifact-diagramming`
skill, etc.).

```mermaid
C4Container
    title Spry — container diagram (updated, Lab 6)

    Person(user, "Team member", "Signs in, manages meetings and agendas")

    System_Boundary(spry, "Spry") {
        Container(frontend, "Frontend", "Next.js static export, S3 + CloudFront", "Meetings list, New meeting, Agenda dialog (paste, check, save)")
        Container(backend, "Backend API", "FastAPI on Lambda, in a VPC", "Validated reads/writes: meetings, agendas")
        ContainerDb(db, "Database", "Aurora PostgreSQL Serverless v2", "meetings, agendas (items, action_items, ai_suggestion)")
        Container(parser, "Agenda parser", "Lambda, app.ai.agenda_lambda, outside the VPC", "Text in, structured JSON out. No database access.")
        Container(auth, "Sign-in", "Amazon Cognito, hosted login", "Email+password, Google; issues the bearer token both Lambdas check")
    }

    System_Ext(bedrock, "Amazon Bedrock", "Claude (Anthropic Messages API)")

    Rel(user, frontend, "Uses", "HTTPS")
    Rel(frontend, auth, "Signs in through", "OIDC / Authorization Code + PKCE")
    Rel(frontend, backend, "Reads/writes meetings and agendas", "HTTPS, JSON, 200ms, same result every time")
    Rel(backend, db, "Reads/writes", "asyncpg, :5432")

    Rel(frontend, parser, "1 Paste an agenda: sends pasted text + bearer token", "HTTPS, function URL")
    Rel(parser, bedrock, "2 Parses text into a structured agenda", "Anthropic Messages API, bedrock-runtime")
    Rel(frontend, backend, "3 Save: sends the checked form + the model's suggestion", "PUT /api/meetings/{id}/agenda")

    UpdateRelStyle(frontend, parser, $offsetY="-40")
    UpdateRelStyle(parser, bedrock, $offsetY="-10")
```

Notes that matter for the diagram, not just the code:

- The **parser never touches the database** and sits **outside the VPC** - no NAT, no VPC
  interface endpoint, $0 when idle (same split as Lab 5's report mailer vs. report builder).
- **Two separate arrows reach the backend**: the agenda dialog's *Save* button (step 3) goes
  through the same validated `PUT /api/meetings/{id}/agenda` every hand-typed agenda uses. The
  parser (steps 1-2) never calls the backend and never writes - "the model suggests, the person
  decides" (Part 0).
- **Cognito** is drawn once because both Lambdas check the same bearer token: the backend's
  routes do not yet require it (pre-Lab 6 scope), but the parser does, since every call there
  costs money (Part 4, Step 3).
