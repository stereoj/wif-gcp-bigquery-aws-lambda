#!/usr/bin/env bash
# End-to-end deploy: GCP federation resources -> credential config -> Lambda package -> AWS resources.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

echo "== Step 1/4: GCP -- Workload Identity Pool, provider, service account =="
( cd "${ROOT_DIR}/terraform/gcp" && terraform init -input=false && terraform apply -auto-approve )

echo "== Step 2/4: Generating credential-config.json =="
"${ROOT_DIR}/scripts/generate_credential_config.sh"

echo "== Step 3/4: Building Lambda package =="
"${ROOT_DIR}/lambda/build.sh"

echo "== Step 4/4: AWS -- IAM role + Lambda function =="
( cd "${ROOT_DIR}/terraform/aws" && terraform init -input=false && terraform apply -auto-approve )

echo
echo "Deployed. Lambda execution role ARN:"
( cd "${ROOT_DIR}/terraform/aws" && terraform output -raw lambda_execution_role_arn )
echo
echo "IMPORTANT (first deploy only): this ARN must match terraform/gcp's"
echo "aws_lambda_role_arn variable EXACTLY, or the trust relationship will"
echo "reject every request. The ARN is deterministic (see the variable's"
echo "description in terraform/gcp/variables.tf), so you can usually get this"
echo "right on the first pass -- but if it doesn't match, re-run 'terraform"
echo "apply' in terraform/gcp with the ARN above, then re-run this script"
echo "from Step 2 onward."
