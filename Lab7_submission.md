# Lab 7 — The cloud as code: from CloudFormation to Terraform

## 1. Commit

The migration: `infra/{versions,variables,data,auth,reports,ai,outputs}.tf` +
`infra/terraform.tfvars` (and `infra/bootstrap/`, the OIDC role HCP Terraform assumes) replace
`infra/auth.yaml`, `infra/reports.yml` and `infra/ai.yml`. The Makefile now has
`infra-init` / `infra-check` / `infra-plan` / `infra-output` / `infra-env` (reading
`terraform output -raw`) and no apply. The six `deploy-`/`destroy-` scripts for those stacks are
gone. README, PROJECT.md and `.env.example` are updated, and the ADR is
`docs/adr/0007-terraform.md`.

Link: https://github.com/pmykhailyk-dot/PeachPelyno/commit/4e598dec4ac2b7924e13b6a7113d29f537bae0f9

## 2. HCP Terraform run, started by a merge

PR #1 (https://github.com/pmykhailyk-dot/PeachPelyno/pull/1) adds a `ManagedBy = "terraform"`
default tag. HCP Terraform posted a speculative plan on the PR (`0 to add, 18 to change,
0 to destroy`). The merge then started the run below, which applied on its own (auto-apply,
workspace `spry-dev`). No laptop was involved.

Run: https://app.terraform.io/app/ooad-pmykhailyk/spry-dev/runs/run-BafUSdWsm3cJQTCW
(screenshot attached: *Apply finished*, source GitHub, commit `fa0edfd`).

## 3. `terraform plan` right after the migration

The steps were:

1. `DeletionPolicy: Retain` + `UpdateReplacePolicy: Retain` on all 28 resources, deployed.
2. The three stacks deleted. 27 resources reported `DELETE_SKIPPED` (the 28th is the
   conditional SES recipient, never created).
3. 38 `import` blocks.
4. Plan: `38 to import, 0 to add, 3 to change, 0 to destroy`. Two of the changes were
   sensitivity-only and one was the mailer's code, re-zipped with the same content.
5. Apply: `38 imported, 0 added, 3 changed, 0 destroyed`.
6. Then this plan:

```
Running plan in HCP Terraform. Output will stream here. Pressing Ctrl-C
will stop streaming the logs, but will not stop the plan running remotely.

Preparing the remote plan...

The remote workspace is configured to work with configuration at
infra relative to the target repository.

Terraform will upload the contents of the following directory,
excluding files or directories as defined by a .terraformignore file
at /Users/shhhhhhh/Desktop/spry/.terraformignore (if it is present),
in order to capture the filesystem context the remote workspace expects:
    /Users/shhhhhhh/Desktop/spry

To view this run in a browser, visit:
https://app.terraform.io/app/ooad-pmykhailyk/spry-dev/runs/run-oPynQHJ8dKu84954

Waiting for the plan to start...

Terraform v1.17.0
on linux_amd64

Initializing plugins and modules...
data.archive_file.mailer: Refreshing...
data.archive_file.mailer: Refresh complete after 0s [id=57087f103a452025cbc3398518f8b7fec09e23b6]
data.aws_cloudformation_stack.backend: Refreshing...
aws_iam_role.scheduler: Refreshing state... [id=spry-reports-SchedulerRole-8ElOqRd0OpM3]
aws_iam_role.mailer: Refreshing state... [id=spry-reports-MailerRole-LZMU5pk5FKxu]
aws_iam_role.parser: Refreshing state... [id=spry-ai-ExecutionRole-BWVDMMfROCe6]
data.aws_cloudformation_stack.frontend: Refreshing...
aws_sesv2_email_identity.sender: Refreshing state... [id=<sender email>]
aws_iam_role.builder: Refreshing state... [id=spry-reports-BuilderRole-h7v0UYRuoa3q]
aws_budgets_budget.parser: Refreshing state... [id=391713637924:spry-agenda-parser-monthly]
aws_sqs_queue.report_requests_dlq: Refreshing state... [id=https://sqs.us-east-1.amazonaws.com/391713637924/spry-report-requests-dlq]
aws_cloudwatch_log_group.parser: Refreshing state... [id=/aws/lambda/spry-agenda-parser]
aws_cloudwatch_log_group.builder: Refreshing state... [id=/aws/lambda/spry-report-builder]
data.aws_cloudformation_stack.frontend: Refresh complete after 0s [id=arn:aws:cloudformation:us-east-1:391713637924:stack/spry-frontend/cbe45b80-bce1-11f1-bf53-0affee9fb491]
data.aws_cloudformation_stack.backend: Refresh complete after 0s [id=arn:aws:cloudformation:us-east-1:391713637924:stack/spry-backend/f0de5eb0-bcdf-11f1-8d05-0effd17962b7]
data.aws_region.current: Refreshing...
data.aws_caller_identity.current: Refreshing...
aws_cloudwatch_log_group.mailer: Refreshing state... [id=/aws/lambda/spry-report-mailer]
data.aws_region.current: Refresh complete after 0s [id=us-east-1]
data.aws_caller_identity.current: Refresh complete after 0s [id=391713637924]
aws_cognito_user_pool.main: Refreshing state... [id=us-east-1_64PTjJ0Ud]
data.aws_lambda_function.backend: Refreshing...
data.aws_secretsmanager_secret_version.database_url: Refreshing...
aws_sqs_queue.report_requests: Refreshing state... [id=https://sqs.us-east-1.amazonaws.com/391713637924/spry-report-requests]
aws_s3_bucket.reports: Refreshing state... [id=spry-reports-391713637924]
data.aws_secretsmanager_secret_version.database_url: Refresh complete after 0s [id=arn:aws:secretsmanager:us-east-1:391713637924:secret:spry/backend/database-url-fRWWtx|AWSCURRENT]
data.aws_lambda_function.backend: Refresh complete after 0s [id=spry-backend]
aws_iam_role_policy.parser_call_bedrock: Refreshing state... [id=spry-ai-ExecutionRole-BWVDMMfROCe6:call-bedrock]
aws_iam_role_policy_attachment.builder_vpc: Refreshing state... [id=spry-reports-BuilderRole-h7v0UYRuoa3q/arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole]
data.aws_route_table.main: Refreshing...
aws_iam_role_policy_attachment.parser_basic: Refreshing state... [id=spry-ai-ExecutionRole-BWVDMMfROCe6/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole]
aws_iam_role_policy.scheduler_send: Refreshing state... [id=spry-reports-SchedulerRole-8ElOqRd0OpM3:send-report-request]
aws_iam_role_policy_attachment.mailer_basic: Refreshing state... [id=spry-reports-MailerRole-LZMU5pk5FKxu/arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole]
aws_scheduler_schedule.weekly: Refreshing state... [id=default/spry-weekly-report]
aws_lambda_function.mailer: Refreshing state... [id=spry-report-mailer]
data.aws_route_table.main: Refresh complete after 0s [id=rtb-00349a83766b53f4f]
aws_iam_role_policy.builder_consume_requests: Refreshing state... [id=spry-reports-BuilderRole-h7v0UYRuoa3q:consume-report-requests]
aws_vpc_endpoint.reports_s3: Refreshing state... [id=vpce-0b863720af9100988]
aws_cognito_identity_provider.google: Refreshing state... [id=us-east-1_64PTjJ0Ud:Google]
aws_cognito_user_pool_domain.main: Refreshing state... [id=spry-391713637924]
aws_cognito_user_pool_client.frontend: Refreshing state... [id=27rbpo6ucp7teqb0hikpmcumn8]
aws_cognito_managed_login_branding.main: Refreshing state...
aws_lambda_function.parser: Refreshing state... [id=spry-agenda-parser]
aws_s3_bucket_public_access_block.reports: Refreshing state... [id=spry-reports-391713637924]
aws_lambda_permission.mailer_s3: Refreshing state... [id=spry-reports-MailerS3InvokePermission-mhVTji2apTec]
aws_iam_role_policy.mailer_read_and_send: Refreshing state... [id=spry-reports-MailerRole-LZMU5pk5FKxu:read-reports-and-send-mail]
aws_iam_role_policy.builder_write_reports: Refreshing state... [id=spry-reports-BuilderRole-h7v0UYRuoa3q:write-reports]
aws_s3_bucket_lifecycle_configuration.reports: Refreshing state... [id=spry-reports-391713637924]
aws_lambda_function.builder: Refreshing state... [id=spry-report-builder]
aws_s3_bucket_notification.reports: Refreshing state... [id=spry-reports-391713637924]
aws_lambda_permission.parser_url_public: Refreshing state... [id=spry-ai-FunctionUrlPermission-ItwztC1HxhLP]
aws_lambda_function_url.parser: Refreshing state... [id=spry-agenda-parser]
aws_lambda_permission.parser_url_invoke: Refreshing state... [id=spry-ai-FunctionUrlInvokePermission-9rOtBm6Sf54l]
aws_lambda_event_source_mapping.builder: Refreshing state... [id=dd4e0cfe-7a6f-4339-bf98-317fafa35dff]

No changes. Your infrastructure matches the configuration.

Terraform has compared your real infrastructure against your configuration
and found no differences, so no changes are needed.

─────────────────────────────────────────────────────────────────────────────

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```

`imports.tf` and the templates were deleted after this. The plan without them is also
*No changes*.

## 4. Step 5 — drift

The agenda parser's timeout was changed by hand from 30 to 45 s, outside Terraform (as in the
console). The next plan caught it:

```
  # aws_lambda_function.parser will be updated in-place
  ~ resource "aws_lambda_function" "parser" {
        id                             = "spry-agenda-parser"
      ~ timeout                        = 45 -> 30
    }

Plan: 0 to add, 1 to change, 0 to destroy.
```

A run in the workspace (`run-YMWkH9if1MnTRdXE`) put it back to 30, and the plan after it is
*No changes*. A console edit survives only until the next apply, which is why every resource
now carries `ManagedBy = terraform`.
