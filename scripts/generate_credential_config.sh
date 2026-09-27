#!/usr/bin/env bash
# Generates lambda/credential-config.json from live Terraform outputs.
# Run this AFTER `terraform apply` in terraform/gcp, and BEFORE lambda/build.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "${ROOT_DIR}/terraform/gcp"
PROVIDER_NAME=$(terraform output -raw workload_identity_pool_provider_name)
SERVICE_ACCOUNT=$(terraform output -raw service_account_email)
cd - >/dev/null

echo "Provider:        ${PROVIDER_NAME}"
echo "Service account: ${SERVICE_ACCOUNT}"

gcloud iam workload-identity-pools create-cred-config \
  "${PROVIDER_NAME}" \
  --service-account="${SERVICE_ACCOUNT}" \
  --aws \
  --output-file="${ROOT_DIR}/lambda/credential-config.json"

echo "Wrote lambda/credential-config.json"
echo "(Safe to inspect -- contains no secret material. See DESIGN.md.)"
