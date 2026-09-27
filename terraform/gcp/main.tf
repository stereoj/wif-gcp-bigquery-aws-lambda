# Workload Identity Pool: the trust boundary that lets a specific AWS
# identity exchange its own (AWS-signed) credentials for a GCP token,
# with no GCP key ever generated or stored on the AWS side.
resource "google_iam_workload_identity_pool" "aws_pool" {
  workload_identity_pool_id = var.pool_id
  display_name              = "AWS Lambda federation pool"
  description               = "Trusts specific AWS IAM roles for keyless access to GCP resources."
}

resource "google_iam_workload_identity_pool_provider" "aws_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.aws_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = var.provider_id
  display_name                       = "AWS Lambda provider"

  aws {
    account_id = var.aws_account_id
  }

  # Hard scope: only this exact Lambda execution role ARN may exchange
  # tokens through this provider -- not the AWS account, not a wildcard
  # role path. See DESIGN.md "Security hardening".
  attribute_condition = "assertion.arn == \"${var.aws_lambda_role_arn}\""

  attribute_mapping = {
    "google.subject"       = "assertion.arn"
    "attribute.aws_role"   = "assertion.arn"
    "attribute.account_id" = "assertion.account"
  }
}

# Dedicated service account the federated AWS identity impersonates.
# BigQuery permissions are granted here, not to the AWS principal directly --
# see DESIGN.md for why.
resource "google_service_account" "lambda_bigquery" {
  account_id   = var.service_account_id
  display_name = "Federated identity for AWS Lambda -> BigQuery"
  description  = "Impersonated by the AWS Lambda execution role via Workload Identity Federation. Holds BigQuery read access only."
}

# Allow the federated AWS identity to impersonate the service account
# (NOT to touch BigQuery directly -- that grant is below, on the SA).
resource "google_service_account_iam_member" "wif_impersonation" {
  service_account_id = google_service_account.lambda_bigquery.name
  role                = "roles/iam.workloadIdentityUser"
  member              = "principalSet://iam.googleapis.com/projects/${var.gcp_project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.aws_pool.workload_identity_pool_id}/attribute.aws_role/${var.aws_lambda_role_arn}"
}

# Least-privilege BigQuery grant: dataset-scoped when a dataset is given,
# otherwise project-scoped as a runnable fallback for a first deploy.
resource "google_bigquery_dataset_iam_member" "dataset_viewer" {
  count      = var.bigquery_dataset_id != "" ? 1 : 0
  dataset_id = var.bigquery_dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.lambda_bigquery.email}"
}

resource "google_project_iam_member" "project_viewer_fallback" {
  count   = var.bigquery_dataset_id == "" ? 1 : 0
  project = var.gcp_project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.lambda_bigquery.email}"
}

# dataViewer alone can't execute query jobs -- this is the permission
# people most often forget and then can't figure out why "read access"
# still returns 403.
resource "google_project_iam_member" "job_user" {
  project = var.gcp_project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.lambda_bigquery.email}"
}
