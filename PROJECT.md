# Spry — PROJECT.md

This file is the specification. It describes the **structure** of the repository and the
**contracts** between its parts — not the implementation. Code in this repository is generated
from it and reviewed against it; if the two disagree, fix this file first.

Scope of the first slice: list meetings, add a meeting. Nothing else.

---

## 1. Decision: one repository (monorepo)

Backend, frontend, database configuration, infrastructure and CI live in one repository.

- **Atomic changes.** One commit changes the API and the client that calls it, so they cannot
  drift apart.
- **The repository is the context window.** An agent (or a new teammate) can read the endpoint,
  the model, the migration and the component that renders it in one pass. Split across three
  repositories, each reader sees a third of the system and guesses the rest — and a guessed
  contract is a bug found at integration time.
- **Cost of the choice.** No independent release cadence, and CI runs for both sides on every
  push. For a team of four and a product that does not exist yet, context is worth more than
  independence. Revisit when a side needs its own release cycle or its own team.

Boundary rule: nothing outside `backend/` imports Python from it; nothing outside `frontend/`
imports TypeScript from it. The only contract between them is the HTTP API in §5.

---

## 2. Stack (pinned)

| Part | Choice | Pinned where |
|---|---|---|
| Backend runtime | Python **3.14** (`python:3.14-slim`) | `backend/Dockerfile`, `pyproject.toml` |
| Web framework | FastAPI + Uvicorn | `backend/uv.lock` |
| ORM | SQLAlchemy 2.x, async, `asyncpg` driver | `backend/uv.lock` |
| Migrations | Alembic | `backend/uv.lock` |
| Backend lint | ruff | `backend/uv.lock` |
| Frontend runtime | Node **22** (`node:22-alpine`), pnpm **10.34.5** | `frontend/Dockerfile`, `package.json` |
| Frontend framework | Next.js **16.3.4** (App Router, static export), React **19.2.8** | `frontend/pnpm-lock.yaml` |
| UI | Tailwind CSS v4, shadcn/ui components | `frontend/pnpm-lock.yaml` |
| Frontend lint | ESLint 9 + Prettier 3 | `frontend/pnpm-lock.yaml` |
| Database | PostgreSQL **17** (`postgres:17-alpine` locally, Aurora PostgreSQL 17.4 on AWS) | `docker-compose.yml`, `infra/backend.yaml` |

Deviation from the course brief: the frontend is Next.js rather than React + Vite, because the
course starter repository ships with it. It is built as a **static export** (plain HTML/JS/CSS),
so in production it behaves exactly like a Vite bundle: files in S3, no Node server.

Not in this repository, on purpose: authentication, a cache, a message queue, a reverse proxy,
a second database, Kubernetes. Add them when a requirement asks, not before.

---

## 3. Repository layout

```
spry/
├── PROJECT.md                  # this specification
├── README.md                   # how to run and deploy, in short
├── .env.example                # every variable Compose and the scripts read; copy to .env
├── docker-compose.yml          # db + backend + frontend: the production-shaped stack
├── docker-compose.override.yml # dev only: bind mounts + hot reload (loaded automatically)
├── Makefile                    # the command contract: local and CI run the same targets
├── .github/workflows/ci-cd.yml # lint + test on every push; deploy on green push to main
├── infra/                      # CloudFormation templates, one per stack
│   ├── backend.yaml            #   Lambda + function URL + Aurora Serverless v2 + API custom domain
│   ├── frontend.yaml           #   private S3 bucket + CloudFront + custom domain
│   └── github-oidc.yaml        #   the IAM role GitHub Actions assumes (OIDC, no keys)
├── scripts/                    # what the Makefile calls; each one is idempotent
│   ├── deploy-backend.sh       #   build image -> ECR (tag = commit SHA) -> stack -> migrate
│   ├── deploy-frontend.sh      #   static export -> S3 -> CloudFront invalidation
│   ├── domain.sh               #   ACM certificate (DNS-validated) + custom domain, either side
│   ├── github-role.sh          #   creates the OIDC role, sets repo variables
│   └── destroy-*.sh            #   tear the stacks down
├── backend/
│   ├── Dockerfile              # stages: builder, dev, runtime (Compose), lambda (AWS)
│   ├── pyproject.toml, uv.lock # dependencies, ruff + pytest config
│   ├── alembic.ini
│   ├── app/
│   │   ├── main.py             # app factory: CORS, /health, routers
│   │   ├── config.py           # Settings from environment variables (pydantic-settings)
│   │   ├── db.py               # engine, session factory, get_session dependency
│   │   ├── lambda_handler.py   # Lambda entry: HTTP via Mangum; {"action":"migrate"} -> alembic
│   │   ├── api/                # HTTP layer: parse, validate, call a service, shape the response
│   │   │   ├── router.py       #   mounts everything under /api
│   │   │   └── routes/         #   health.py, meetings.py
│   │   ├── schemas/            # Pydantic request/response models = the API contract in code
│   │   ├── services/           # business logic and queries; no HTTP types here
│   │   └── models/             # SQLAlchemy ORM models = the table shape in code
│   ├── migrations/versions/    # Alembic revisions; the only way the schema changes
│   ├── scripts/entrypoint.sh   # runtime container: alembic upgrade head, then uvicorn
│   └── tests/                  # pytest against a real Postgres, one rolled-back txn per test
└── frontend/
    ├── Dockerfile              # stages: deps, dev, builder, runtime
    ├── package.json, pnpm-lock.yaml
    ├── app/                    # routes: layout.tsx, page.tsx (the one page)
    ├── components/             # meetings-page, meeting-stats, meeting-form-dialog, headers
    │   └── ui/                 # generated by the shadcn CLI; not hand-edited
    ├── lib/
    │   ├── api.ts              # the only place that calls the backend; zod-validates responses
    │   └── meeting-stats.ts    # week-over-week numbers, pure functions
    └── tests/                  # vitest + Testing Library
```

---

## 4. Configuration

All configuration comes from environment variables. `.env.example` is committed; `.env` is
git-ignored. **No credential is ever committed.** On AWS, CI authenticates through OIDC (§8).

| Variable | Used by | Local default |
|---|---|---|
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | db | `spry` / `spry` / `spry` |
| `DATABASE_URL` | backend | `postgresql+asyncpg://spry:spry@db:5432/spry` |
| `CORS_ORIGINS` | backend | `http://localhost:3000` (comma-separated) |
| `NEXT_PUBLIC_API_URL` | frontend, **compiled in at build time** | `http://localhost:8000` |
| `BACKEND_URL` | `deploy-frontend.sh` | written by `make deploy-backend` |
| `API_CORS_ORIGINS` | deployed backend | `*` until the frontend has a domain |
| `DOMAIN_NAME` / `API_DOMAIN_NAME` | `domain.sh` | written by `make domain-*` |

---

## 5. API contract

Base path `/api`. JSON only. Errors use FastAPI's shape: `{"detail": ...}`.
Datetimes are **ISO 8601 with a UTC offset** (`2026-10-01T07:00:00Z` or `…+03:00`); the API
stores `timestamptz` and returns UTC. A datetime without an offset is rejected — the API never
guesses a timezone.

### `GET /api/meetings`

`200`, a JSON **array** of `Meeting`, ordered by `starts_at` ascending (ties by `id`).
Empty list → `[]`.

```json
[
  {
    "id": "6f1c2c1e-6a53-4b4e-9d61-1f6f0d9a1b2c",
    "title": "Weekly sync",
    "starts_at": "2026-10-01T07:00:00Z",
    "ends_at": "2026-10-01T07:30:00Z",
    "attendee_count": 5,
    "created_at": "2026-09-30T12:00:00Z"
  }
]
```

| Field | Type | Rules |
|---|---|---|
| `id` | string (UUID v4) | generated by the database |
| `title` | string | 1–200 characters |
| `starts_at` | string (ISO 8601, offset required) | |
| `ends_at` | string (ISO 8601, offset required) | strictly after `starts_at` |
| `attendee_count` | integer | 0–10 000 |
| `created_at` | string (ISO 8601, UTC) | set by the database |

### `POST /api/meetings`

Body: `title`, `starts_at`, `ends_at`, `attendee_count` (rules above; any other field is
ignored). `201` with the created `Meeting`. Invalid body → `422` with FastAPI's validation
detail.

### Health

| Path | Response | Touches the DB |
|---|---|---|
| `GET /health` | `{"status":"ok"}` — liveness | no |
| `GET /api/health/ready` | `{"status":"ok","database":"ok"}`, or `503` | yes (`SELECT 1`) |

Interactive docs: `/docs`. Schema: `/openapi.json`.

### Table `meetings`

`id uuid pk default gen_random_uuid()`, `title varchar(200) not null`,
`starts_at timestamptz not null` (indexed), `ends_at timestamptz not null`,
`attendee_count integer not null`, `created_at timestamptz not null default now()`.
Check constraints: `ends_at > starts_at`, `attendee_count >= 0` — the database enforces the
same rules as the API, so a bug in one layer cannot write a bad row.

---

## 6. Frontend behaviour

One page, `/`:

- **Week-over-week tiles**: meetings this week, hours in meetings, average attendees — each with
  the % change against last week (weeks run Monday to Monday, local time).
- **List**: meetings grouped by day, each a card with start/end time, duration and attendees.
- **New meeting**: a dialog with title, date, start, end, attendees. Local time is converted to
  UTC ISO 8601 before sending. Validation mirrors §5.
- Loading → skeletons; empty → a call to action; API failure → an alert with *Retry*.

---

## 7. Local stack — `docker compose up`

The only command a new developer runs (after installing Docker Desktop and `cp .env.example .env`):

| Service | Image / build | Port (host:container) | Depends on | Knows it is ready by |
|---|---|---|---|---|
| `db` | `postgres:17-alpine` | `5432:5432` | — | healthcheck `pg_isready` every 5 s |
| `backend` | `build: ./backend` | `8000:8000` | `db: service_healthy` | healthcheck `curl /health` |
| `frontend` | `build: ./frontend` | `3000:3000` | `backend: service_healthy` | — |

- `depends_on` alone only orders **start**. `condition: service_healthy` waits for the
  healthcheck, i.e. until Postgres actually answers.
- **Migrations run at container start**, before Uvicorn: `alembic upgrade head` in
  `entrypoint.sh` (runtime) or in the override's `command` (dev). A fresh volume comes up migrated.
- If the database disappears **later**, no Compose feature helps: the engine uses
  `pool_pre_ping`, requests fail with 5xx meanwhile, `/api/health/ready` answers `503`, and the
  app recovers by itself once Postgres is back.
- Dev-only (in `docker-compose.override.yml`): bind mounts, `--reload`, `next dev`, dev
  dependencies. Publishing the DB port is also a dev convenience. Run the production-shaped
  stack with `docker compose -f docker-compose.yml up --build`.

---

## 8. AWS

Everything in **us-east-1**, every resource tagged `PROJECT_NAME=spry`.

```
browser ──HTTPS──> app.<domain>  CloudFront ──(OAC)──> private S3 bucket (static export)
browser ──HTTPS──> api.<domain>  API Gateway HTTP API ──> Lambda (FastAPI via Mangum, in VPC)
                                                              └──5432──> Aurora Serverless v2
```

- **Frontend**: S3 stores the files, CloudFront serves them from the edge, terminates HTTPS and
  is the only reader of the private bucket. Every deploy invalidates `/*`.
- **Backend**: the image goes to **ECR** tagged with the **commit SHA**; Lambda runs it. The
  function URL is the always-on HTTPS endpoint; `api.<domain>` is an API Gateway HTTP API in
  front of the same function, because a function URL cannot carry a custom domain.
  Migrations run after each deploy through a direct invoke `{"action":"migrate"}`.
- **Why not ECS + ALB** (the brief's option): an ALB bills ~$16/month idle and Fargate
  per-hour on top; Lambda + Aurora scaling to zero costs cents for a demo. The trade-off —
  cold starts, ~15 s wake-up after Aurora pauses — is acceptable for a course project.
- **Domains**: `make domain-frontend` / `make domain-backend` request an ACM certificate,
  publish the **validation CNAME** in Route 53, wait for `ISSUED`, then attach the domain and
  create the **routing alias record**.
- **CI/CD** (`.github/workflows/ci-cd.yml`): every push → ruff, pytest (real Postgres),
  `alembic check`, ESLint, Prettier, tsc, vitest. A green push to `main` → `make deploy-backend`
  then `make deploy-frontend`, authenticated by **OIDC**: the role in `infra/github-oidc.yaml`
  trusts only `repo:<owner>/<repo>:ref:refs/heads/main` with audience `sts.amazonaws.com`.
