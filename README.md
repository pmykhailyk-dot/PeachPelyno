# Spry

Team meetings at a glance: a FastAPI + Postgres backend and a Next.js frontend, in one
repository. **[PROJECT.md](PROJECT.md) is the specification** — structure, contracts, decisions.

## Run it locally

Install Docker Desktop, then:

```bash
cp .env.example .env
docker compose up --build
```

| URL | What |
|---|---|
| http://localhost:3000 | Frontend — the meetings page |
| http://localhost:8000/docs | API docs (Swagger) |
| http://localhost:8000/api/meetings | The meetings list, raw JSON |

Add a meeting, reload the page: if it is still there, the whole chain works —
component → API → ORM → Postgres and back.

```bash
make logs            # tail everything
make test            # pytest + vitest inside the containers
make lint            # ruff + eslint inside the containers
make clean           # stop and wipe the database volume
```

## Deploy to AWS

Prerequisites: AWS CLI configured (`aws sts get-caller-identity` works), Docker running,
a domain with a Route 53 hosted zone.

```bash
make deploy-backend                               # ECR + Lambda + Aurora (~10 min the first time)
make domain-backend  DOMAIN=api.<your-domain>     # certificate + https://api.<your-domain>
make deploy-backend                               # re-writes BACKEND_URL to the custom domain
make deploy-frontend                              # S3 + CloudFront, built against BACKEND_URL
make domain-frontend DOMAIN=app.<your-domain>     # certificate + https://app.<your-domain>
# then in .env: API_CORS_ORIGINS=https://app.<your-domain>
make deploy-backend                               # let the site through CORS
make github-role                                  # OIDC role for GitHub Actions
```

From then on every green push to `main` redeploys both sides
([ci-cd.yml](.github/workflows/ci-cd.yml)).

## Infrastructure as code: Terraform

Sign-in (Cognito), the weekly report and the agenda parser live in [`infra/*.tf`](infra/) and
are applied by **HCP Terraform** (workspace `spry-dev`, remote execution, AWS reached through
OIDC - no access keys anywhere). Why, and who may change what: [ADR 0007](docs/adr/0007-terraform.md).

The road to a change is a pull request, never a laptop:

1. Edit `infra/*.tf`, then `make infra-check` (fmt + validate) and `make infra-plan`
   (a speculative plan, run remotely - it cannot apply).
2. Open a PR: HCP Terraform posts the plan on it.
3. Merge to `main`: HCP Terraform plans again and applies. There is no `make` target for apply.

```bash
terraform login        # once, a user token for app.terraform.io
make infra-init        # once per clone
make infra-plan        # what would change
make infra-env         # write AUTH_* and PARSER_URL from `terraform output` into .env
```

The Google client secret (sensitive) and the email addresses are variables in the workspace,
not in the repo; `DATABASE_URL` is read from Secrets Manager at plan time. The
backend, the frontend and the GitHub OIDC role are still CloudFormation (`make deploy-*`), and
the backend image the report builder and the parser run is rolled by `make deploy-backend`, not
by Terraform.

Tear down when done: destroy the `spry-dev` workspace in HCP Terraform, then
`make destroy-frontend && make destroy-backend`.

## The same core on Google Cloud (Lab 9)

The frontend, the API and the database also run on Google Cloud, in project `spry-pelyno-2026`
(`us-central1`). Why each service, and what stayed on AWS:
[ADR 0008](docs/adr/0008-google-cloud.md).

| AWS | Google Cloud |
|---|---|
| S3 + CloudFront | Firebase Hosting, `https://spry-pelyno-2026.web.app` (`/api/**` rewritten to Cloud Run) |
| Lambda + function URL | Cloud Run `spry-api`, min 0 instances |
| Aurora Serverless v2 | Cloud SQL for PostgreSQL 17, `db-f1-micro` - **does not pause** |
| ECR, Secrets Manager | Artifact Registry `spry`, Secret Manager `spry-database-url` |

**Still on AWS:** sign-in (Cognito), the weekly report and the agenda parser. The Google Cloud
site is built with sign-in and *Paste an agenda* switched off, and its database is a copy of
Aurora's, not a replica.

`gcp/*.tf` is its own HCP Terraform workspace, `spry-gcp`, with its own state. Same road as
`infra/`: a PR gets a plan, a merge to `main` applies. HCP Terraform reaches the project through
workload identity federation. No service account key exists.

Once per project, from a laptop:

```bash
gcloud auth login && gcloud auth application-default login
gcloud projects create spry-pelyno-2026 --name=Spry --organization=<org-id>
gcloud billing projects link spry-pelyno-2026 --billing-account=<billing-account-id>
cd gcp/bootstrap && terraform init && terraform apply -var project_id=spry-pelyno-2026
# then add Firebase to the project once in console.firebase.google.com (accepts its terms)
```

Then:

```bash
# in .env: GCP_PROJECT=spry-pelyno-2026, GCP_REGION=us-central1
make gcp-plan              # speculative plan of gcp/; merge the PR to apply
make gcp-deploy-backend    # build the runtime image (linux/amd64), push, roll Cloud Run
make gcp-copy-data         # meetings + agendas from the API on AWS to the one on Google Cloud
make gcp-deploy-frontend   # static export -> Firebase Hosting
```

**Stop the database when you are not using it.** Cloud SQL bills $0.0105 an hour while it runs
(≈ $7.70 a month). Stopped, only its disk bills (≈ $1.70), and the API answers 503 until it is
started again:

```bash
make gcp-db-stop
make gcp-db-start
```

Tear down: destroy the `spry-gcp` workspace in HCP Terraform, then
`terraform -chdir=gcp/bootstrap destroy -var project_id=spry-pelyno-2026`.

Based on the course starter [dobosevych/Peach](https://github.com/dobosevych/Peach).
