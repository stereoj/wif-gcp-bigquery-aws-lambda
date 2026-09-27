output "workload_identity_pool_name" {
  value = google_iam_workload_identity_pool.aws_pool.name
}

output "workload_identity_pool_provider_name" {
  value = google_iam_workload_identity_pool_provider.aws_provider.name
}

output "service_account_email" {
  value = google_service_account.lambda_bigquery.email
}

output "generate_credential_config_command" {
  description = "Run this (or scripts/generate_credential_config.sh) to produce the credential-config.json the Lambda package needs."
  value       = "gcloud iam workload-identity-pools create-cred-config ${google_iam_workload_identity_pool_provider.aws_provider.name} --service-account=${google_service_account.lambda_bigquery.email} --aws --output-file=lambda/credential-config.json"
}
