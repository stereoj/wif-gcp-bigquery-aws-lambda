"""
AWS Lambda handler that queries Google BigQuery using Workload Identity
Federation -- no GCP service account key is stored anywhere.

Credential flow:
  1. google-auth reads GOOGLE_APPLICATION_CREDENTIALS (credential-config.json),
     which describes an "external_account" credential backed by AWS.
  2. On first use, google-auth signs a GetCallerIdentity request using the
     Lambda execution role's AWS credentials. Lambda's runtime already
     exposes AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY / AWS_SESSION_TOKEN as
     environment variables, and google-auth's AWS credential source checks
     those before ever falling back to an EC2-style metadata endpoint -- this
     is exactly why the same credential-config.json works unmodified across
     EC2, ECS, and Lambda. No code here touches AWS credentials directly.
  3. That signed request is exchanged with GCP's STS endpoint for a
     short-lived GCP access token, scoped to the impersonated service
     account (not the AWS identity itself -- see DESIGN.md).
  4. The BigQuery client uses that access token like any other GCP
     credential.

See DESIGN.md for why impersonation is used instead of a direct IAM grant,
and for the specific failure modes this handler guards against.
"""

import json
import logging
import os
import time

from google.auth.exceptions import RefreshError, TransportError
from google.cloud import bigquery
from google.api_core.exceptions import Forbidden

logger = logging.getLogger()
logger.setLevel(logging.INFO)

_MAX_CRED_REFRESH_ATTEMPTS = 3
_CRED_REFRESH_BACKOFF_SECONDS = 0.5

# Reused across warm Lambda invocations for performance. Explicitly
# re-validated per call rather than trusted blindly -- see
# DESIGN.md "Handling silent failures", item 4 (token caching across warm
# invocations).
_bq_client = None


def _get_bigquery_client() -> bigquery.Client:
    global _bq_client

    if _bq_client is not None:
        return _bq_client

    project_id = os.environ["GCP_PROJECT_ID"]

    last_error = None
    for attempt in range(1, _MAX_CRED_REFRESH_ATTEMPTS + 1):
        try:
            _bq_client = bigquery.Client(project=project_id)
            return _bq_client
        except (RefreshError, TransportError) as exc:
            last_error = exc
            logger.warning(
                "GCP credential refresh attempt %d/%d failed: %s",
                attempt, _MAX_CRED_REFRESH_ATTEMPTS, exc,
            )
            time.sleep(_CRED_REFRESH_BACKOFF_SECONDS * attempt)

    # Fails closed with a specific, actionable message rather than a bare
    # google-auth stack trace -- see DESIGN.md "Handling silent failures",
    # item 1 (attribute-condition mismatch).
    logger.error(
        "Could not obtain GCP credentials via Workload Identity Federation "
        "after %d attempts. If this just started happening after a "
        "Terraform change, check that the Lambda execution role ARN still "
        "matches the attribute_condition on the GCP workload identity pool "
        "provider (terraform/gcp/main.tf).",
        _MAX_CRED_REFRESH_ATTEMPTS,
    )
    raise last_error


def _bq_param_type(value) -> str:
    if isinstance(value, bool):
        return "BOOL"
    if isinstance(value, int):
        return "INT64"
    if isinstance(value, float):
        return "FLOAT64"
    return "STRING"


def _extract_reason(exc: Forbidden) -> str:
    try:
        return exc.errors[0].get("reason", "unknown")
    except (AttributeError, IndexError, KeyError, TypeError):
        return "unknown"


def _run_query(client: bigquery.Client, sql: str, params: dict) -> list:
    location = os.environ.get("BIGQUERY_LOCATION", "US")

    query_parameters = [
        bigquery.ScalarQueryParameter(name, _bq_param_type(value), value)
        for name, value in (params or {}).items()
    ]
    job_config = bigquery.QueryJobConfig(query_parameters=query_parameters)

    try:
        query_job = client.query(sql, job_config=job_config, location=location)
        return [dict(row) for row in query_job.result()]
    except Forbidden as exc:
        # Distinguish "the service account lost its role" from "the query
        # references something it was never granted" -- these need
        # different responses. See DESIGN.md "Handling silent failures",
        # item 3.
        reason = _extract_reason(exc)
        if reason == "accessDenied":
            logger.error(
                "BigQuery access denied (reason=%s). Check that the "
                "federated service account still holds "
                "roles/bigquery.dataViewer and roles/bigquery.jobUser: %s",
                reason, exc,
            )
        else:
            logger.error("BigQuery request forbidden (reason=%s): %s", reason, exc)
        raise


def lambda_handler(event, context):
    """
    Expected event shape:
        {
          "sql": "SELECT * FROM `project.dataset.table` WHERE region = @region LIMIT 10",
          "params": {"region": "eu-west-1"}
        }
    """
    sql = event.get("sql")
    if not sql:
        return {
            "statusCode": 400,
            "body": json.dumps({"error": "event.sql is required"}),
        }

    params = event.get("params", {})

    try:
        client = _get_bigquery_client()
        rows = _run_query(client, sql, params)
    except Exception as exc:  # noqa: BLE001 -- top-level handler boundary; specific cases already logged above with actionable context
        return {
            "statusCode": 502,
            "body": json.dumps({"error": "BigQuery query failed", "detail": str(exc)}),
        }

    return {
        "statusCode": 200,
        "body": json.dumps({"row_count": len(rows), "rows": rows}, default=str),
    }
