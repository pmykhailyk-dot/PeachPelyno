# Everything the Makefile and the frontend build read - `make infra-env`
# copies the AUTH_* and PARSER_URL values into .env for `make deploy-frontend`.

# --- auth -----------------------------------------------------------------

output "user_pool_id" {
  value = aws_cognito_user_pool.main.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.frontend.id
}

output "cognito_domain" {
  description = "Hosted login's base URL."
  value       = "https://${aws_cognito_user_pool_domain.main.domain}.auth.${local.region}.amazoncognito.com"
}

output "authority" {
  description = "OIDC issuer / authority for the frontend's OIDC client."
  value       = "https://cognito-idp.${local.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
}

output "redirect_uri" {
  value = "${local.site_url}/auth/callback"
}

output "logout_uri" {
  value = "${local.site_url}/"
}

# --- weekly report --------------------------------------------------------

output "reports_bucket_name" {
  value = aws_s3_bucket.reports.bucket
}

output "report_requests_queue_url" {
  value = aws_sqs_queue.report_requests.url
}

output "report_requests_dlq_url" {
  value = aws_sqs_queue.report_requests_dlq.url
}

output "builder_function_name" {
  value = aws_lambda_function.builder.function_name
}

output "mailer_function_name" {
  value = aws_lambda_function.mailer.function_name
}

output "builder_log_group_name" {
  value = aws_cloudwatch_log_group.builder.name
}

output "mailer_log_group_name" {
  value = aws_cloudwatch_log_group.mailer.name
}

# --- agenda parser --------------------------------------------------------

output "parser_function_name" {
  value = aws_lambda_function.parser.function_name
}

output "parser_url" {
  description = "What the frontend calls to parse pasted text."
  value       = aws_lambda_function_url.parser.function_url
}

output "parser_log_group_name" {
  value = aws_cloudwatch_log_group.parser.name
}
