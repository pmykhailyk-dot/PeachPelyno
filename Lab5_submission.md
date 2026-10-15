# Lab 5 — the weekly report, built by events

## 1. Commit

Code: `backend/app/reports/weekly.py`, `backend/app/reports/lambda_handler.py`,
`infra/lambda/report_mailer.py`, `infra/reports.yml`, plus the Makefile targets and deploy
scripts. Link: _(filled in after `git commit` — see the commit this file ships in)_.

## 2. Email screenshot

Confirmed delivered: `pmykhailyk@gmail.com`, subject "Weekly meetings report - 2026-W40", one
CSV attachment, sent via `amazonses.com`. (Landed in Spam — expected for a brand-new sender
identity with no sending domain/reputation; not a defect in the pipeline.)

## 3. `aws s3 ls s3://spry-reports-391713637924/reports/ --recursive`

```
2026-10-15 11:01:06        444 reports/2026-W40.csv
2026-10-15 10:58:48        165 reports/2026-W41.csv
```

`2026-W40` was built on demand (`make report-now WEEK=2026-W40`, real meeting data).
`2026-W41` was built by the schedule (temporarily set to `rate(5 minutes)` to test without
waiting for Monday, then restored to `cron(0 7 ? * MON *)` / `Europe/Kyiv`).

## 4. Three CloudWatch log lines, one per trigger

**Schedule** (`report-builder`):

```
2026-10-15T07:58:47 [INFO] report-builder triggered trigger=schedule week=2026-W41
```

**SQS message** (`report-builder`, sent by `make report-now`):

```
2026-10-15T07:52:42 [INFO] report-builder triggered trigger=manual week=2026-W40
```

**S3 upload** (`report-mailer`):

```
2026-10-15T07:54:17 [INFO] report-mailer sent trigger=s3 bucket=spry-reports-391713637924 key=reports/2026-W40.csv to=pmykhailyk@gmail.com
```

All three carry an explicit `trigger=` field so the originating event is visible without
cross-referencing anything else.

## 5. Written answers — Part 3, Step 7

**Send the same week twice — how many emails, and why?**

Two identical emails. S3 emits one `s3:ObjectCreated:*` notification per successful `PutObject`
call, regardless of whether the new bytes are identical to what was already there — it does not
deduplicate notifications by content or suppress them for a no-op overwrite. The *builder* is
idempotent at the storage layer (same key, overwritten, never duplicated), but that idempotency
does not propagate downstream: the *mailer* keeps no record of "already sent this key" and reacts
to every notification it receives as if it were new. Verified live: ran `make report-now
WEEK=2026-W40` twice ~20s apart, got two `report-mailer sent ... key=reports/2026-W40.csv` log
lines for the one key.

**Where would you store "this report was already sent", and what would the key be?**

A small DynamoDB table, `sent_reports(week PK, sent_at)`, written with a conditional put
(`attribute_not_exists(week)`) right before calling SES. The key is the ISO **week**, not the S3
key or ETag — the business invariant is "one email per week", not "one email per byte-identical
object", so keying on `week` also protects against the one-content-twice case above. The
conditional write is what makes this race-free under concurrent deliveries, which a cheaper
alternative (tagging the S3 object `mailed=true` after sending, checking the tag before sending)
is not: two mailer invocations can both read "untagged" before either one writes the tag.

**Three ways to let the in-VPC builder reach SES, with monthly cost. Which would you choose at
+10 emails/week? At a million?**

| Option | Fixed monthly cost (us-east-1) | Notes |
|---|---|---|
| NAT gateway | ~$33 base (~$0.045/h × 730h) + ~$0.045/GB | Also opens full internet egress — more than the builder needs |
| VPC interface endpoint for SES | ~$15 for 2 AZs (~$0.01/h × 730h × 2) + ~$0.01/GB | Scoped to SES only, still a flat floor |
| The split built here (mailer outside the VPC) | $0 fixed | Pay only per Lambda invocation; no hourly charge either way |

At **+10 emails/week**: the split stays the obvious choice — paying a $15-33/month floor for a
handful of emails makes no sense; SES itself costs essentially nothing at that volume.

At **~1,000,000 emails/week** (~$430/month in SES sending fees alone, at $0.10/1000): the SES
cost now dwarfs any of the three connectivity costs, so the $15-30/month endpoint fee becomes
noise. At that scale I'd keep the split for its operational simplicity (it already works, scales
independently, and keeps the VPC-bound builder untouched) rather than merge everything back
behind a paid endpoint just to save an architecture diagram box — the split isn't more expensive
at high volume, only the SES bill is.

**A presigned S3 link instead of an attachment, that works for a week — not hours?**

A Lambda execution role's temporary (STS) credentials cap how long a presigned URL signed with
them can live, typically well under 12 hours — `generate_presigned_url(ExpiresIn=604800)` would
be accepted by the SDK but silently rejected by S3 the moment the underlying session expires.
Two ways around it:

1. Sign with a long-lived IAM **user's** static access key (not a role) scoped to
   `s3:GetObject` on just `reports/*`, kept in Secrets Manager. Static keys aren't bounded by a
   session lifetime, so a 7-day `ExpiresIn` works as asked — at the cost of a long-lived secret
   that has to be rotated and guarded like any other credential.
2. Better: don't presign once and email it. Email a link to a small authenticated endpoint
   (the existing API, behind Cognito) that mints a **fresh, short-lived** presigned URL and
   redirects on every click. The thing that is valid "for a week" is the user's ability to
   authenticate, not an S3 signature — so nothing long-lived ever leaves AWS, and revoking access
   is just revoking the user, not rotating a key.
