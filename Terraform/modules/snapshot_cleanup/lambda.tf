
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/templates/snapshot_cleanup.py"
  output_path = "${path.module}/templates/snapshot_cleanup.zip"
}


resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.environment}-snapshot-cleanup"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${var.environment}-snapshot-cleanup-logs"
  }
}

resource "aws_lambda_function" "snapshot_cleanup" {
  function_name    = "${var.environment}-snapshot-cleanup"
  description      = "Deletes EC2 snapshots older than ${var.snapshot_retention_days} days"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  role             = aws_iam_role.lambda_role.arn
  handler          = "snapshot_cleanup.lambda_handler"
  runtime          = var.lambda_runtime
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = [aws_subnet.private.id]
    security_group_ids = [aws_security_group.lambda_sg.id]
  }

  environment {
    variables = {
      ENVIRONMENT             = var.environment
      AWS_REGION_NAME         = var.region
      SNAPSHOT_RETENTION_DAYS = tostring(var.snapshot_retention_days)
      LOG_LEVEL               = "INFO"
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.lambda,
    aws_iam_role_policy_attachment.ec2_snapshot,
    aws_iam_role_policy_attachment.lambda_vpc_execution,
  ]

  tags = {
    Name = "${var.environment}-snapshot-cleanup"
  }
}


resource "aws_cloudwatch_event_rule" "daily_trigger" {
  name                = "${var.environment}-daily-snapshot-cleanup"
  description         = "Invokes the snapshot-cleanup Lambda on a daily schedule"
  schedule_expression = var.lambda_schedule
  state               = "ENABLED"

  tags = {
    Name = "${var.environment}-daily-snapshot-cleanup"
  }
}

resource "aws_cloudwatch_event_target" "lambda" {
  rule      = aws_cloudwatch_event_rule.daily_trigger.name
  target_id = "SnapshotCleanupLambdaTarget"
  arn       = aws_lambda_function.snapshot_cleanup.arn
}


resource "aws_lambda_permission" "allow_eventbridge" {
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.snapshot_cleanup.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.daily_trigger.arn
}


resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.environment}-snapshot-cleanup-errors"
  alarm_description   = "Fires when the snapshot-cleanup Lambda reports execution errors"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 86400 # 24 hours — matches the daily schedule
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.snapshot_cleanup.function_name
  }

  tags = {
    Name = "${var.environment}-snapshot-cleanup-errors"
  }
}
