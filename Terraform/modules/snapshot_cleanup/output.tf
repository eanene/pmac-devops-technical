output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = aws_subnet.private.id
}

output "security_group_id" {
  description = "ID of the Lambda security group"
  value       = aws_security_group.lambda_sg.id
}

output "ec2_vpc_endpoint_id" {
  description = "ID of the EC2 Interface VPC Endpoint"
  value       = aws_vpc_endpoint.ec2.id
}

output "logs_vpc_endpoint_id" {
  description = "ID of the CloudWatch Logs Interface VPC Endpoint"
  value       = aws_vpc_endpoint.logs.id
}

output "lambda_role_arn" {
  description = "ARN of the Lambda IAM execution role"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.snapshot_cleanup.function_name
}

output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.snapshot_cleanup.arn
}

output "cloudwatch_log_group" {
  description = "CloudWatch Log Group name for Lambda logs"
  value       = aws_cloudwatch_log_group.lambda.name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.daily_trigger.arn
}

output "lambda_error_alarm_arn" {
  description = "ARN of the CloudWatch alarm for Lambda errors"
  value       = aws_cloudwatch_metric_alarm.lambda_errors.arn
}
