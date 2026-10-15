"""Lambda entry point for the report builder (Lab 5, Steps 3-4).

Runs in the VPC, same image and security group as the API: it reaches Aurora
directly on :5432 and S3 through the gateway endpoint - no NAT, so nothing
else on the internet is reachable from here, which is why the mailer that
sends through SES is a separate function outside the VPC.

Two event shapes arrive here, both carrying the same {"source", "week"}
payload:

- a direct invocation - EventBridge Scheduler's target before Step 4 added
  the queue, and still how `aws lambda invoke` tests it by hand;
- an SQS record, ``event["Records"][0]["body"]`` - from the schedule once its
  target became the queue, or from `make report-now` sending a message by
  hand. Either way the builder does not care who put the message there.
"""

import json
import logging
import os
from typing import Any

import boto3

from app.reports.weekly import build_weekly_report, previous_iso_week, report_key

logger = logging.getLogger(__name__)
logging.getLogger().setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

_s3 = boto3.client("s3")


def _payload(event: dict[str, Any]) -> dict[str, Any]:
    """The {"source": ..., "week": ...} dict, whichever shape the event arrived in."""
    records = event.get("Records")
    if records:
        return json.loads(records[0]["body"])
    return event


def handler(event: dict[str, Any], context: Any) -> dict[str, str]:
    payload = _payload(event)
    trigger = payload.get("source") or ("sqs" if "Records" in event else "direct")
    week = payload.get("week") or previous_iso_week()

    logger.info("report-builder triggered trigger=%s week=%s", trigger, week)

    bucket = os.environ["REPORTS_BUCKET"]
    key = report_key(week)
    body = build_weekly_report(week)
    _s3.put_object(Bucket=bucket, Key=key, Body=body, ContentType="text/csv")

    logger.info(
        "report-builder wrote trigger=%s week=%s bucket=%s key=%s", trigger, week, bucket, key
    )
    return {"status": "ok", "week": week, "key": key}
