data "aws_caller_identity" "current" {}

resource "aws_iam_role" "lambda_exec" {
  name = "${var.function_name}-exec-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Only what's strictly needed: CloudWatch Logs for observability, and
# sts:GetCallerIdentity -- the AWS side of the WIF handshake (google-auth
# signs this exact call to prove the Lambda's identity to GCP's STS).
# The Lambda has NO direct AWS data-plane permissions beyond proving its
# own identity.
resource "aws_iam_role_policy" "lambda_minimal" {
  name = "${var.function_name}-minimal-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.function_name}:*"
      },
      {
        # sts:GetCallerIdentity is allowed to any authenticated principal by
        # default and needs no resource-level grant; included here purely
        # for documentation -- so anyone reading this role's policy sees
        # exactly what the WIF handshake relies on, in one place.
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
}

resource "aws_lambda_function" "bigquery_query" {
  function_name = var.function_name
  role          = aws_iam_role.lambda_exec.arn
  handler       = "handler.lambda_handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = 256

  filename         = var.lambda_zip_path
  source_code_hash = filebase64sha256(var.lambda_zip_path)

  environment {
    variables = {
      GOOGLE_APPLICATION_CREDENTIALS = "/var/task/credential-config.json"
      GCP_PROJECT_ID                 = var.gcp_project_id
      BIGQUERY_LOCATION              = var.bigquery_location
    }
  }

  depends_on = [aws_cloudwatch_log_group.lambda_logs]
}
