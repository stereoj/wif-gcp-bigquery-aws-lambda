#!/usr/bin/env bash
# Invokes the deployed Lambda with a trivial BigQuery query to confirm the
# full Workload Identity Federation trust chain works end-to-end.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

FUNCTION_NAME=$(cd "${ROOT_DIR}/terraform/aws" && terraform output -raw lambda_function_name)

PAYLOAD='{"sql": "SELECT 1 AS ok, CURRENT_TIMESTAMP() AS ts"}'

echo "Invoking ${FUNCTION_NAME} ..."
aws lambda invoke \
  --function-name "${FUNCTION_NAME}" \
  --cli-binary-format raw-in-base64-out \
  --payload "${PAYLOAD}" \
  /tmp/smoke_test_response.json

echo "Response:"
cat /tmp/smoke_test_response.json
echo
