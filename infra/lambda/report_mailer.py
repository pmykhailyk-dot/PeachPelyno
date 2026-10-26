"""Lambda entry point for the report mailer (Lab 5, Step 5).

Outside the VPC, unlike the builder: it has normal internet access, reaches
SES, and never touches the database. It is woken by S3's ObjectCreated event
on ``reports/*.csv`` - the builder and this function never call each other
directly, only through that event, which is the part that makes this
event-driven rather than just "two functions that happen to run in order".

Zipped from the repository by Terraform (data.archive_file.mailer in
infra/reports.tf) on every run - no build step, no dependencies.
Must never write into reports/: a function invoked by uploads to that prefix
that also uploads there would call itself forever.
"""

import email.message
import logging
import os
import urllib.parse

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())

s3 = boto3.client("s3")
ses = boto3.client("sesv2")

SENDER = os.environ["REPORT_SENDER"]
RECIPIENT = os.environ["REPORT_RECIPIENT"]


def handler(event, context):
    record = event["Records"][0]
    bucket = record["s3"]["bucket"]["name"]
    key = urllib.parse.unquote_plus(record["s3"]["object"]["key"])

    logger.info("report-mailer triggered trigger=s3 bucket=%s key=%s", bucket, key)

    body = s3.get_object(Bucket=bucket, Key=key)["Body"].read()
    week = key.rsplit("/", 1)[-1].removesuffix(".csv")

    message = email.message.EmailMessage()
    message["Subject"] = f"Weekly meetings report - {week}"
    message["From"] = SENDER
    message["To"] = RECIPIENT
    message.set_content(f"The meetings report for {week} is attached as a CSV.")
    message.add_attachment(body, maintype="text", subtype="csv", filename=f"{week}.csv")

    ses.send_email(
        FromEmailAddress=SENDER,
        Destination={"ToAddresses": [RECIPIENT]},
        Content={"Raw": {"Data": message.as_bytes()}},
    )

    logger.info("report-mailer sent trigger=s3 bucket=%s key=%s to=%s", bucket, key, RECIPIENT)
    return {"status": "ok", "key": key}
