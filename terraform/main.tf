# main.tf

terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Variables for lambda artifact locations (S3 URIs written by CI)
variable "reddit_collector_zip" {
  type        = string
  description = "S3 URI for reddit_collector zip (s3://bucket/prefix/reddit_collector.zip)"
  default     = ""
}

variable "sentiment_analyzer_zip" {
  type        = string
  description = "S3 URI for sentiment_analyzer zip (s3://bucket/prefix/sentiment_analyzer.zip)"
  default     = ""
}

# Parse S3 URIs into bucket/key using a simple local expression
locals {
  reddit_parts  = split("/", replace(var.reddit_collector_zip, "s3://", ""))
  reddit_bucket = length(local.reddit_parts) > 0 ? local.reddit_parts[0] : null
  reddit_key    = length(local.reddit_parts) > 1 ? join("/", slice(local.reddit_parts, 1, length(local.reddit_parts))) : null

  sentiment_parts  = split("/", replace(var.sentiment_analyzer_zip, "s3://", ""))
  sentiment_bucket = length(local.sentiment_parts) > 0 ? local.sentiment_parts[0] : null
  sentiment_key    = length(local.sentiment_parts) > 1 ? join("/", slice(local.sentiment_parts, 1, length(local.sentiment_parts))) : null
}

resource "aws_s3_bucket" "sentiment_data" {
  bucket = "${var.project_name}-sentiment-data"
}

resource "aws_iam_role" "lambda_role" {
  name = "${var.project_name}-lambda-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "lambda.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project_name}-lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Effect = "Allow"
        Resource = [
          aws_s3_bucket.sentiment_data.arn,
          "${aws_s3_bucket.sentiment_data.arn}/*"
        ]
      },
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect   = "Allow"
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

resource "aws_lambda_function" "reddit_collector" {
  function_name = "${var.project_name}-reddit-collector"
  role          = aws_iam_role.lambda_role.arn
  handler       = "reddit_collector.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  s3_bucket = local.reddit_bucket
  s3_key    = local.reddit_key

  environment {
    variables = {
      S3_BUCKET            = aws_s3_bucket.sentiment_data.id
      DATA_FOLDER          = "raw_data/reddit/"
      REDDIT_CLIENT_ID     = var.reddit_client_id
      REDDIT_CLIENT_SECRET = var.reddit_client_secret
    }
  }
}


resource "aws_lambda_function" "sentiment_analyzer" {
  function_name = "${var.project_name}-sentiment-analyzer"
  role          = aws_iam_role.lambda_role.arn
  handler       = "sentiment_analyzer.lambda_handler"
  runtime       = "python3.11"
  timeout       = 60
  memory_size   = 256

  s3_bucket = local.sentiment_bucket
  s3_key    = local.sentiment_key

  environment {
    variables = {
      S3_BUCKET = aws_s3_bucket.sentiment_data.id
    }
  }
}

resource "aws_cloudwatch_event_rule" "daily_trigger" {
  name                = "${var.project_name}-daily-trigger"
  description         = "Triggers data collection and analysis daily"
  schedule_expression = "rate(1 day)"
}

resource "aws_cloudwatch_event_target" "trigger_reddit_collector" {
  rule      = aws_cloudwatch_event_rule.daily_trigger.name
  target_id = "RedditCollector"
  arn       = aws_lambda_function.reddit_collector.arn
}



resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.sentiment_data.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.sentiment_analyzer.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw_data/" # Trigger only for new objects in raw_data folder
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sentiment_analyzer.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.sentiment_data.arn
}

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

resource "aws_cloudwatch_metric_alarm" "reddit_collector_errors" {
  alarm_name          = "${var.project_name}-reddit-collector-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 86400
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerts when the reddit_collector Lambda fails"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.reddit_collector.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "sentiment_analyzer_errors" {
  alarm_name          = "${var.project_name}-sentiment-analyzer-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 86400
  statistic           = "Sum"
  threshold           = 0
  alarm_description   = "Alerts when the sentiment_analyzer Lambda fails"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.sentiment_analyzer.function_name
  }
}

resource "aws_quicksight_data_source" "s3_source" {
  data_source_id = "${var.project_name}-s3-source"
  aws_account_id = data.aws_caller_identity.current.account_id
  name           = "Sentiment Analysis S3 Data Source"
  type           = "S3"

  parameters {
    s3 {
      manifest_file_location {
        bucket = aws_s3_bucket.sentiment_data.id
        key    = aws_s3_object.quicksight_manifest.key
      }
    }
  }
}

resource "aws_s3_object" "quicksight_manifest" {
  bucket = aws_s3_bucket.sentiment_data.id
  key    = "quicksight-manifest.json"
  content = jsonencode({
    fileLocations = [
      { URIPrefixes = ["s3://${aws_s3_bucket.sentiment_data.id}/processed_data/"] }
    ],
    globalUploadSettings = { format = "CSV" }
  })
}

data "aws_caller_identity" "current" {}
