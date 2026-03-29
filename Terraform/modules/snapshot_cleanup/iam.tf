resource "aws_iam_role" "lambda_role" {
  name        = "${var.environment}-lambda-role"
  description = "Execution role for snapshot-cleanup Lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "LambdaAssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.environment}-lambda-role"
  }
}

resource "aws_iam_policy" "ec2_snapshot_policy" {
  name        = "${var.environment}-ec2-snapshot-policy"
  description = "Allows Lambda to list and delete EC2 snapshots owned by this account"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DescribeSnapshots"
        Effect = "Allow"
        Action = [
          "ec2:DescribeSnapshots",
          "ec2:DescribeSnapshotAttribute"
        ]
        # Describe calls do not support resource-level permissions
        Resource = "*"
      },
      {
        Sid    = "DeleteOwnSnapshots"
        Effect = "Allow"
        Action = [
          "ec2:DeleteSnapshot"
        ]
        # Restrict deletion to snapshots owned by this account
        Resource = "arn:aws:ec2:${var.region}::snapshot/*"
        Condition = {
          StringEquals = {
            "ec2:ResourceTag/OwnedBy" : "self"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.environment}-ec2-snapshot-policy"
  }
}
resource "aws_iam_role_policy_attachment" "ec2_snapshot" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.ec2_snapshot_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_vpc_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}