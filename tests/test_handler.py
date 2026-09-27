"""
Unit tests for the Lambda handler. These mock the BigQuery client entirely --
they do not exercise real Workload Identity Federation (that's what
scripts/smoke_test.sh is for, against a real deployment).
"""
import json
import os
import sys
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "lambda"))

os.environ.setdefault("GCP_PROJECT_ID", "test-project")
os.environ.setdefault("BIGQUERY_LOCATION", "US")

import handler  # noqa: E402


class FakeQueryJob:
    def __init__(self, rows):
        self._rows = rows

    def result(self):
        return self._rows


def test_missing_sql_returns_400():
    response = handler.lambda_handler({}, None)
    assert response["statusCode"] == 400
    body = json.loads(response["body"])
    assert "error" in body


@patch("handler._get_bigquery_client")
def test_successful_query_returns_rows(mock_get_client):
    mock_client = MagicMock()
    mock_client.query.return_value = FakeQueryJob([{"ok": 1}])
    mock_get_client.return_value = mock_client

    event = {"sql": "SELECT 1 AS ok"}
    response = handler.lambda_handler(event, None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["row_count"] == 1
    assert body["rows"] == [{"ok": 1}]


@patch("handler._get_bigquery_client")
def test_query_with_params_builds_correct_job_config(mock_get_client):
    mock_client = MagicMock()
    mock_client.query.return_value = FakeQueryJob([])
    mock_get_client.return_value = mock_client

    event = {
        "sql": "SELECT * FROM t WHERE region = @region AND active = @active",
        "params": {"region": "eu-west-1", "active": True},
    }
    handler.lambda_handler(event, None)

    _, kwargs = mock_client.query.call_args
    job_config = kwargs["job_config"]
    types_by_name = {p.name: p.type_ for p in job_config.query_parameters}
    assert types_by_name == {"region": "STRING", "active": "BOOL"}


@patch("handler._get_bigquery_client")
def test_bigquery_error_returns_502(mock_get_client):
    mock_client = MagicMock()
    mock_client.query.side_effect = RuntimeError("boom")
    mock_get_client.return_value = mock_client

    event = {"sql": "SELECT 1"}
    response = handler.lambda_handler(event, None)

    assert response["statusCode"] == 502
    body = json.loads(response["body"])
    assert "error" in body


def test_param_type_mapping():
    assert handler._bq_param_type(True) == "BOOL"
    assert handler._bq_param_type(5) == "INT64"
    assert handler._bq_param_type(5.5) == "FLOAT64"
    assert handler._bq_param_type("x") == "STRING"
