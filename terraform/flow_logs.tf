# VPC Flow Logs: a record of the IP traffic hitting the VPC's network
# interfaces. Cheap (you only pay for the CloudWatch log storage, which
# at this project's traffic level is negligible) and it's exactly the
# kind of audit trail a real security review asks for, so it's worth
# keeping even in a "simple" project.

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/vpc/${var.project_name}/flow-logs"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "flow_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["vpc-flow-logs.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "flow_logs" {
  name               = "${var.project_name}-vpc-flow-logs"
  assume_role_policy = data.aws_iam_policy_document.flow_logs_assume.json
}

data "aws_iam_policy_document" "flow_logs_publish" {
  statement {
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
    ]
    resources = ["${aws_cloudwatch_log_group.vpc_flow_logs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "flow_logs_publish" {
  name   = "${var.project_name}-vpc-flow-logs-publish"
  role   = aws_iam_role.flow_logs.id
  policy = data.aws_iam_policy_document.flow_logs_publish.json
}

resource "aws_flow_log" "vpc" {
  vpc_id               = aws_vpc.main.id
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.vpc_flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn
  traffic_type         = "ALL"

  tags = { Name = "${var.project_name}-vpc-flow-logs" }
}
