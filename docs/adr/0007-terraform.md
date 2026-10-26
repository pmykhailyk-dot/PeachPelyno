# 0007. Terraform on HCP Terraform for the infrastructure

Status: accepted — 2026-10-26

## Context

Labs 4-6 added three CloudFormation stacks, each with its own deploy script run from a laptop:
`spry-auth` (Cognito), `spry-reports` (the weekly report: two Lambdas, SQS, a schedule, S3, SES)
and `spry-ai` (the agenda parser and its budget alert). Those scripts had grown into a second
configuration language. They read `.env`, looked up the other stacks' outputs, passed the
mailer's source in as a parameter, and wrote outputs back into `.env`. Nobody but the laptop
that ran them knew what was deployed or with which values, and nothing stopped two laptops
deploying different versions.

What Lab 7 asks for, and what the project needs, comes down to three things:

- **One reviewed road for changes.** A pull request shows the plan, a merge applies it, and a
  laptop never applies.
- **No stored keys.** The tool reaches AWS the same way GitHub Actions already does, through
  OIDC.
- **No outage during the move.** The user pool holds every account and the bucket holds every
  report built so far. Re-creating either one loses data, and a new pool also gets a new client
  id that is compiled into the frontend.

## Decision

**Terraform, one root module in `infra/`, one HCP Terraform workspace `spry-dev`** in remote
execution mode, connected to this repository (working directory `infra`). A pull request gets a
speculative plan, and a merge to `main` plans and applies. HCP Terraform reaches AWS through
dynamic credentials (`TFC_AWS_PROVIDER_AUTH`, `TFC_AWS_RUN_ROLE_ARN`). The IAM role it assumes
lives in `infra/bootstrap/`, the one piece applied from a laptop, because it has to exist before
HCP Terraform can do anything.

**The three stacks were imported, not re-created.** The steps were:

1. Set `DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain` on every resource and deploy
   once more.
2. Delete the stacks. CloudFormation lets go and the resources stay.
3. Add `import` blocks and write `.tf` files, using `-generate-config-out` as a starting point.
4. Change the `.tf` files until the plan showed only imports.
5. Apply, then plan again and get *No changes*.
6. Delete `imports.tf`, the generated file and the templates.

The names CloudFormation generated (for example `spry-reports-BuilderRole-h7v0UYRuoa3q`) are
kept as they are. A new name is a new resource. Three diffs were accepted in that first apply:

- The Google client secret and `DATABASE_URL` showed a sensitivity-only diff. The values are
  equal, but Terraform marks them sensitive.
- The mailer's code was re-uploaded as a zip from `archive_file`. The code inside is the same.

**Two roads.** Terraform owns the infrastructure. `make deploy-backend` (CI on push to `main`)
owns which image the backend, the report builder and the parser run. That is why the builder
and the parser carry `ignore_changes = [image_uri]`. Without it every app deploy would show up
as drift, and every `terraform apply` would roll the functions back to whatever image Terraform
last saw.

**Out of scope for this lab.** The backend (API and Aurora), the frontend (S3 and CloudFront)
and the GitHub OIDC role stay CloudFormation. `data.tf` reads their outputs, so nothing is
duplicated, and they can move later the same way.

## Why Terraform, not the alternatives

- **CloudFormation (stay).** It works, and the state is AWS's problem. But it has no plan you
  can trust before you deploy: a change set does not show what a nested `!If` or a custom
  resource will do. It also has no clean import story; `IMPORT` change sets are limited and do
  not work for every resource type. The deploy scripts showed the real gap: the "configuration"
  was half YAML and half bash. Terraform's references (`aws_cognito_user_pool.main.id`) replace
  `describe-stacks` lookups, and the circular dependency between the bucket, its notification
  and the mailer's permission (`reports.yml` broke it with a hard-coded name) is gone, because
  those are three separate resources.
- **AWS CDK.** It is real code (TypeScript or Python), but it synthesizes CloudFormation, so it
  keeps every CloudFormation limit above and adds a build step and a bootstrap stack. Its main
  advantage, loops and abstractions, does not pay off for about 40 resources, and HCL's
  `for_each` and `count` cover what is needed.
- **OpenTofu.** It is the open-source (MPL) fork, with the same language and providers, so
  moving there later is cheap. The course and HCP Terraform (remote runs, VCS integration, OIDC
  dynamic credentials, a free tier) are Terraform. With OpenTofu all of that would have to be
  assembled from GitHub Actions and an S3 backend. The BSL licence restricts building a
  competing product, which this is not.

## Who can change the infrastructure, and how

- **Through a pull request, merged to `main`.** That is the only road that applies. On the PR,
  HCP Terraform posts a speculative plan. On merge, it plans and applies. Anyone with merge
  rights on the repository can therefore change the infrastructure. For this course that is the
  repository owner, and a team would add branch protection and a required review.
- **Not from a laptop.** The workspace is VCS-driven, so HCP Terraform refuses CLI applies.
  `make infra-plan` runs a speculative plan remotely and can never apply. There is deliberately
  no `infra-apply` target.
- **Not from the AWS console.** Hand edits are not forbidden by IAM, but the next plan shows
  them as drift, and the next apply undoes them. Lab 7, Step 5 shows this with the parser's
  timeout.
- **What the role can do.** The role HCP Terraform assumes trusts only workspace `spry-dev` of
  this organization (the `sub` claim). It has `AdministratorAccess`, which is acceptable for a
  class account and is the first thing a real team would narrow. A team would also split it into
  a read-only plan role and an apply role (`TFC_AWS_PLAN_ROLE_ARN` / `TFC_AWS_APPLY_ROLE_ARN`),
  so that a PR's plan cannot write.

## Where the secrets end up, state included

- **Not in the repository.** The repository is public. `terraform.tfvars` holds only
  non-secret values, and the Google client id is public by design. The Google client secret and
  the email addresses are workspace variables, with the secret marked sensitive. HCP Terraform
  never shows them again after they are set.
- **`DATABASE_URL` is not a variable at all.** It is read at plan time from Secrets Manager
  (`data.aws_secretsmanager_secret_version`), where the backend stack keeps it.
- **In the state, in plain text.** Both values above end up in the state, because the Cognito
  identity provider and the builder's environment store them as attributes. The state lives in
  HCP Terraform, encrypted at rest. Only users with state access on the workspace can read it,
  and runs read it through their short-lived token. This is the real trade-off, and it is why
  the state must never be in the repository (`.gitignore` covers `*.tfstate*`). The same
  `DATABASE_URL` is already visible in the Lambda console to anyone with
  `lambda:GetFunctionConfiguration`. The fix for both is to have the builder read the secret at
  runtime by ARN, which is a code change for later.
- **Not on laptops.** `make infra-env` copies only outputs that are not secret (pool and client
  ids, URLs) into `.env`.

## What happens if HCP Terraform is down

- **Nothing that is running stops.** HCP Terraform is only the control plane for changes. The
  user pool, the Lambdas, the queue and the schedule run in AWS and never call it.
- **App deploys keep working.** CI's `make deploy-backend` / `make deploy-frontend` do not
  touch Terraform. The frontend build looks the pool and the parser URL up by name
  (`deploy-frontend.sh`), not through `terraform output`.
- **Infrastructure changes wait.** PRs cannot be planned and merges are not applied until the
  service is back. HCP Terraform then picks up the latest commit on `main`.
- **For an emergency** (for example a leaked Google secret that has to be rotated now), change
  it in the AWS console, then update the workspace variable. The next plan shows whether the
  code and the console agree. If HCP Terraform were gone for good, `terraform state pull` (from
  a recent copy) plus a `backend "s3"` block would move the state somewhere else in minutes. The
  configuration is plain Terraform, not tied to HCP.

## Consequences

- Every infrastructure change is a reviewed diff with a plan attached, and the history of
  applies lives in the workspace.
- Six deploy/destroy scripts and three templates are gone. The Makefile only plans and reads
  outputs.
- There are now two tools (Terraform for these three parts, CloudFormation for the rest) until
  the backend and frontend move too.
- A new image no longer flows through the infrastructure tool. `deploy-backend.sh` updates the
  builder and the parser itself, after the backend.
