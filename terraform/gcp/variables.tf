variable "gcp_project_id" {
  description = "GCP project ID that hosts the Workload Identity Pool, service account, and BigQuery dataset."
  type        = string
}

variable "gcp_project_number" {
  description = "GCP project NUMBER (not ID). Required because WIF resource names use the numeric project ID."
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID that owns the Lambda execution role."
  type        = string
}

variable "aws_lambda_role_arn" {
  description = "Exact ARN of the AWS IAM role assumed by the Lambda function. The workload identity pool provider trusts ONLY this ARN. Can be precomputed as arn:aws:iam::<aws_account_id>:role/<function_name>-exec-role before the AWS stack is ever applied, since Lambda execution role names are deterministic."
  type        = string
}

variable "pool_id" {
  description = "ID for the Workload Identity Pool."
  type        = string
  default     = "aws-lambda-pool"
}

variable "provider_id" {
  description = "ID for the Workload Identity Pool AWS provider."
  type        = string
  default     = "aws-lambda-provider"
}

variable "service_account_id" {
  description = "Account ID (local part) for the GCP service account that Lambda impersonates."
  type        = string
  default     = "lambda-bigquery-federated"
}

variable "bigquery_dataset_id" {
  description = "BigQuery dataset the federated service account is granted read access to. Leave empty to grant project-level bigquery.dataViewer instead."
  type        = string
  default     = ""
}
