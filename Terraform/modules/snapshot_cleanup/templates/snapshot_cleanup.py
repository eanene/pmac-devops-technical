"""
snapshot_cleanup.py
────────────────────────────────────────────────────────────────────
Lambda function that deletes EC2 snapshots owned by this account
that are older than SNAPSHOT_RETENTION_DAYS (default: 365).

Environment variables (injected by Terraform):
  SNAPSHOT_RETENTION_DAYS  – integer, default 365
  AWS_REGION_NAME          – region string, e.g. "us-east-1"
  LOG_LEVEL                – Python log level string, default "INFO"
"""

import logging
import os
from datetime import datetime, timezone, timedelta

import boto3
from botocore.exceptions import ClientError


LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger(__name__)
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))


REGION = os.environ.get("AWS_REGION_NAME", "us-east-1")
RETENTION_DAYS = int(os.environ.get("SNAPSHOT_RETENTION_DAYS", "365"))


def get_ec2_client() -> boto3.client:
    """Return a boto3 EC2 client for the configured region."""
    return boto3.client("ec2", region_name=REGION)


def fetch_own_snapshots(ec2_client) -> list[dict]:
    """
    Retrieve all snapshots owned by this AWS account.
    Handles pagination transparently.
    """
    snapshots: list[dict] = []
    paginator = ec2_client.get_paginator("describe_snapshots")

    try:
        for page in paginator.paginate(OwnerIds=["self"]):
            snapshots.extend(page.get("Snapshots", []))
        logger.info("Total snapshots retrieved: %d", len(snapshots))
    except ClientError as exc:
        logger.error(
            "Failed to describe snapshots: %s – %s",
            exc.response["Error"]["Code"],
            exc.response["Error"]["Message"],
        )
        raise

    return snapshots


def filter_old_snapshots(
    snapshots: list[dict], cutoff: datetime
) -> list[dict]:
    """Return only snapshots whose StartTime is before *cutoff*."""
    old = [s for s in snapshots if s["StartTime"] < cutoff]
    logger.info(
        "Snapshots older than %d days: %d of %d",
        RETENTION_DAYS,
        len(old),
        len(snapshots),
    )
    return old


def delete_snapshot(ec2_client, snapshot: dict) -> bool:
    """
    Attempt to delete a single snapshot.

    Returns True on success, False on a handled error.
    Raises on unexpected errors so the Lambda is marked as failed.
    """
    snapshot_id = snapshot["SnapshotId"]
    start_time = snapshot["StartTime"].strftime("%Y-%m-%d")
    description = snapshot.get("Description", "")

    logger.info(
        "Deleting snapshot: %s  (created: %s  description: %s)",
        snapshot_id,
        start_time,
        description or "<none>",
    )

    try:
        ec2_client.delete_snapshot(SnapshotId=snapshot_id)
        logger.info("Successfully deleted snapshot: %s", snapshot_id)
        return True

    except ClientError as exc:
        error_code = exc.response["Error"]["Code"]

        if error_code == "InvalidSnapshot.InUse":
            logger.warning(
                "Skipping snapshot %s — currently in use by an AMI: %s",
                snapshot_id,
                exc.response["Error"]["Message"],
            )
            return False

        if error_code == "InvalidSnapshot.NotFound":
            # Already deleted by another process — treat as success.
            logger.warning(
                "Snapshot %s not found — already deleted.", snapshot_id
            )
            return True

        logger.error(
            "Unexpected error deleting snapshot %s: %s – %s",
            snapshot_id,
            error_code,
            exc.response["Error"]["Message"],
        )
        return False


def lambda_handler(event: dict, context) -> dict:
    """
    Lambda entry point.

    Returns a summary dict:
    {
        "statusCode": 200,
        "region": "us-east-1",
        "retention_days": 365,
        "total_snapshots": <int>,
        "eligible_for_deletion": <int>,
        "deleted": [<snapshot_id>, ...],
        "skipped": [<snapshot_id>, ...],
        "failed": [<snapshot_id>, ...],
    }
    """
    logger.info(
        "Starting snapshot cleanup | region=%s | retention_days=%d",
        REGION,
        RETENTION_DAYS,
    )

    cutoff = datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    logger.info("Cutoff date: %s", cutoff.strftime("%Y-%m-%d %H:%M:%S UTC"))

    ec2_client = get_ec2_client()

    all_snapshots = fetch_own_snapshots(ec2_client)

    old_snapshots = filter_old_snapshots(all_snapshots, cutoff)

    deleted: list[str] = []
    skipped: list[str] = []
    failed: list[str] = []

    for snapshot in old_snapshots:
        snapshot_id = snapshot["SnapshotId"]
        try:
            success = delete_snapshot(ec2_client, snapshot)
            if success:
                deleted.append(snapshot_id)
            else:
                skipped.append(snapshot_id)
        except Exception as exc:  # pylint: disable=broad-except
            logger.error(
                "Unhandled exception for snapshot %s: %s",
                snapshot_id,
                str(exc),
            )
            failed.append(snapshot_id)

    logger.info(
        "Cleanup complete | deleted=%d | skipped=%d | failed=%d",
        len(deleted),
        len(skipped),
        len(failed),
    )

    return {
        "statusCode": 200,
        "region": REGION,
        "retention_days": RETENTION_DAYS,
        "total_snapshots": len(all_snapshots),
        "eligible_for_deletion": len(old_snapshots),
        "deleted": deleted,
        "skipped": skipped,
        "failed": failed,
    }
