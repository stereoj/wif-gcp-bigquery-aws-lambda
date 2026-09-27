variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "function_name" {
  type    = string
  default = "gcp-bigquery-federated-query"
}

variable "lambda_zip_path" {
  description = "Path to the packaged Lambda deployment zip (see lambda/build.sh)."
  type        = string
  default     = "../../lambda/build/function.zip"
}

variable "gcp_project_id" {
  type = string
}

variable "bigquery_location" {
  type    = string
  default = "US"
}

variable "log_retention_days" {
  type    = number
  default = 30
}
