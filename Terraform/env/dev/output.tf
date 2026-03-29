output "vpc_id" {
  description = "VPC created for the Lambda function"
  value       = module.snapshot_cleanup.vpc_id
}

output "private_subnet_id" {
  description = "Private subnet the Lambda function runs in"
  value       = module.snapshot_cleanup.private_subnet_id
}

output "lambda_function_name" {
  description = "Name of the deployed Lambda function"
  value       = module.snapshot_cleanup.lambda_function_name
}

output "lambda_function_arn" {
  description = "ARN of the deployed Lambda function"
  value       = module.snapshot_cleanup.lambda_function_arn
}

output "lambda_iam_role_arn" {
  description = "ARN of the Lambda execution IAM role"
  value       = module.snapshot_cleanup.lambda_role_arn
}

output "security_group_id" {
  description = "Security group attached to the Lambda function"
  value       = module.snapshot_cleanup.security_group_id
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group for Lambda logs"
  value       = module.snapshot_cleanup.cloudwatch_log_group
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = module.snapshot_cleanup.eventbridge_rule_arn
}
