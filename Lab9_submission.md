# Lab 9 — One project, two clouds: Spry on Google Cloud

## 1. Commit and ADR

`gcp/*.tf` (workspace `spry-gcp`), `gcp/bootstrap/` (service accounts, workload identity
federation for HCP Terraform, the workspace, Firebase), the `make gcp-*` targets, and
`frontend/firebase.json`.

- Merged PR: https://github.com/pmykhailyk-dot/PeachPelyno/pull/2
- HCP Terraform run that applied it on merge: https://app.terraform.io/app/ooad-pmykhailyk/spry-gcp/runs/run-XcfZyqidvwHMBe7C (`14 added`, source GitHub, commit `4013465`)
- ADR with the Part 1 service choices: [`docs/adr/0008-google-cloud.md`](docs/adr/0008-google-cloud.md),
  merged in https://github.com/pmykhailyk-dot/PeachPelyno/pull/3 (also the README section)

Data: **migrations against the empty database** (the image runs `alembic upgrade head` on
start), then `make gcp-copy-data`. That target copies every meeting and agenda from the API on
AWS to the API on Google Cloud. `pg_dump` would have needed a bastion host: Aurora has no
public endpoint.

## 2. Spry on Google Cloud

- Site: https://spry-pelyno-2026.web.app (screenshot `lab9-site.png`: a private window, the
  meetings list read from Cloud SQL)
- An API call that reads from the database: https://spry-pelyno-2026.web.app/api/meetings
  (the site's `/api/**` is rewritten to Cloud Run). The Cloud Run service itself: https://spry-api-rkxqc7mana-uc.a.run.app/api/meetings

## 3. What it costs

On-demand list prices in USD from the lab (5 November 2026): AWS us-east-1, Google Cloud
us-central1, 730 hours a month, tax excluded.

### Spry's core, nobody using it for a month

| Piece | AWS (Lab 4, Stage 2) | Google Cloud (what this project runs) |
|---|---|---|
| Frontend + CDN + HTTPS | CloudFront Free plan → $0 | Firebase Hosting, free plan (10 GB stored, 360 MB/day out) → $0 |
| API | Lambda, idle → $0 | Cloud Run, min 0, request-based billing → $0 |
| Database compute | Aurora, paused → $0 | Cloud SQL `db-f1-micro` running, $0.0105/h × 730 → **$7.67** |
| Database storage | ~1 GB × $0.10 → $0.10 | 10 GB SSD × $0.17 → $1.70 |
| Registry, secrets, logs | a few cents | Artifact Registry < 0.5 GB, 1 secret version, Cloud Logging → free tier |
| **Total** | **≈ $0.30** | **≈ $9.40**, or **≈ $1.70** with the instance stopped |

Free-tier assumptions: Cloud Run 2M requests, 180,000 vCPU-s and 360,000 GiB-s a month;
Lambda 1M requests and 400,000 GB-s. Artifact Registry 0.5 GB (cleanup policy keeps 3 images).
Secret Manager 6 active versions and 10,000 accesses. Firebase Hosting free plan. Cloud SQL has
no free tier, and its disk bills while stopped too.

### Four traffic profiles

Assumptions:

- Aurora runs at 0.5 ACU ($0.06/h) while awake, and pauses 5 minutes after the last
  connection.
- The API is 512 MB / 1 vCPU, about 100 ms per request.
- Demo, office-hours and busy traffic stays within the free tiers of both serverless APIs,
  except where noted.
- "Busy" means one request a second, all day: 2.6M requests a month. Aurora never pauses.

| Profile | DB hours | AWS | Google Cloud, Cloud SQL always on | Google Cloud, stopped when unused | Cheaper |
|---|---|---|---|---|---|
| Nobody | 0 | $0.30 | $9.40 | $1.70 | **AWS** |
| Class demos, 10 × 2 h | 20 h (+ ~1 h of pause tails on AWS) | 21 h × $0.06 + $0.30 ≈ **$1.56** | **$9.40** | 20 h × $0.0105 + $1.70 ≈ **$1.91** | **AWS** |
| Office hours, 8 h × 22 days | 176 h (+ ~2 h) | 178 h × $0.06 + $0.30 ≈ **$11.00** | **$9.40** | 176 h × $0.0105 + $1.70 ≈ **$3.55** | **GCP** |
| Busy around the clock | 730 h | 730 h × $0.06 + $0.10 + Lambda 1.6M billable requests × $0.20/M ≈ **$44.20** | $9.40 + Cloud Run 0.6M billable requests × $0.40/M + (263k − 180k) vCPU-s × $0.000024 ≈ **$11.60** | same, it never stops | **GCP** |

**Which single line decides it: database compute, in every profile.** Hosting, the API,
registry, secrets and logs are $0 or cents on both sides. Up to a few hours of use a day, the
database that pauses (Aurora) wins. At office hours they cross: 178 Aurora hours at
$0.06 ≈ $10.70, against Cloud SQL's flat $7.67. Around the clock, $0.06/h of Aurora at
0.5 ACU (twice that at 1 ACU) loses to $0.0105/h of `db-f1-micro`. Stopping Cloud SQL by hand
beats Aurora from office hours up. Below that, the 10 GB disk alone ($1.70) costs more than
Aurora's few hours. And it only works if someone remembers to stop it.

**The GCP-side trap, the counterpart of something keeping Aurora awake:**

1. **Cloud SQL never pauses.** "Nobody used it this month" still costs $9.40, and forgetting
   `make gcp-db-stop` after a demo is the same mistake as a cron job pinging Aurora every
   4 minutes. Stopped, the disk still bills.
2. **Cloud Run with min instances ≥ 1, or instance-based billing** ("CPU always allocated"):
   the instance bills every second, requests or not. One vCPU and 512 MiB around the clock is
   roughly $45–50 a month.
3. **The console's defaults for Postgres 16+:** Enterprise Plus edition with a
   `db-perf-optimized` machine, hundreds of dollars a month. `gcp/database.tf` pins
   `edition = "ENTERPRISE"`. Without that, `db-f1-micro` is not even accepted.

With Firestore instead of Cloud SQL, Google Cloud is $0 in the first three profiles: one list
page of ~10 documents per request stays under 50,000 reads a day. In the busy profile that is
~26M reads a month, about $7.40. The cost is a rewrite of the data layer (ADR 0008).

## 4. Demos

1. **BigQuery**: the 20 most common names in `bigquery-public-data.usa_names.usa_1910_current`
   (`SUM(number)` grouped by name). **95.56 MB processed** (96 MB billed) in 346 ms. That is
   ~0.01% of the free 1 TiB a month, so $0. At $6.25/TiB it would cost about $0.0006.
   Screenshots: the results, and the Job information tab.
2. **Looker Studio** (now called Data Studio), opened from the query results with
   *Open in → Data Studio*: a bar chart of `total` by `name`, next to the table. Free.
3. **Vision API OCR** (text detection) on a photo of a crumpled PostNL receipt. It found every
   line, including the address, the date and time, and the tracking number, as separate blocks
   with bounding boxes. Within the first 1,000 units a month that are free.

**Document AI vs a general model (Lab 6).** A specialised processor is the better tool when the
input is a document whose layout carries the meaning: forms, invoices, receipts at volume. It
returns bounding boxes and confidence scores at a fixed price per page ($1.50 per 1,000 for
OCR), and it never invents a field. An LLM is the better tool when the input is free text and
the output has to be interpreted, as with Spry's agendas: "Олена, 15 хв" becomes owner and
minutes. No processor knows that schema. The two combine well: OCR first, then the LLM on the
text.

**Lab 8 on Google Cloud.** The S3 bucket of payments becomes Cloud Storage. The Glue crawler
and catalog plus Athena become a BigQuery external table, or a load into BigQuery: there is no
crawler to schedule and no partitions to repair, and you pay per TiB scanned as with Athena.
The Kinesis → Firehose ingestion becomes Pub/Sub → Dataflow (or a BigQuery subscription). The
dashboards become Looker Studio. What you no longer manage: the crawler, the Glue database and
its schema drift, Athena's result bucket and workgroup, and Firehose's buffering.

## Clean up

Kept running until the lab is graded, so the URL above works. It costs ~$0.31 a day, paid
from the free trial's credit. Then:

1. `terraform destroy` in the `spry-gcp` workspace (Cloud SQL, Cloud Run, the registry, the
   secret), then `terraform -chdir=gcp/bootstrap destroy -var project_id=spry-pelyno-2026`.
2. The BigQuery query wrote only a temporary table, which expires on its own in 24 h. The
   Data Studio report holds no data, so delete it.
3. Check Billing → Reports a day later.

Until then, `make gcp-db-stop` stops the database between demos.
