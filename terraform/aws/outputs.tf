output "lambda_function_name" {
  value = aws_lambda_function.bigquery_query.function_name
}

output "lambda_execution_role_arn" {
  description = "This exact ARN must match terraform/gcp's aws_lambda_role_arn variable, or GCP's attribute_condition will reject every token exchange."
  value       = aws_iam_role.lambda_exec.arn
}
