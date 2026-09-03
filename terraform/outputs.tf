# outputs.tf

output "s3_bucket_name" {
  description = "The name of the S3 bucket"
  value       = aws_s3_bucket.sentiment_data.id
}

output "reddit_collector_lambda_arn" {
  description = "The ARN of the Reddit collector Lambda function"
  value       = aws_lambda_function.reddit_collector.arn
}

output "sentiment_analyzer_lambda_arn" {
  description = "The ARN of the sentiment analyzer Lambda function"
  value       = aws_lambda_function.sentiment_analyzer.arn
}


output "lambda_function_names" {
  description = "The names of the Lambda functions"
  value = {
    reddit_collector   = aws_lambda_function.reddit_collector.function_name
    sentiment_analyzer = aws_lambda_function.sentiment_analyzer.function_name
  }
}

output "alerts_topic_arn" {
  description = "The ARN of the SNS topic used for pipeline failure alerts"
  value       = aws_sns_topic.alerts.arn
}

output "quicksight_data_source_arn" {
  description = "The ARN of the QuickSight data source"
  value       = aws_quicksight_data_source.s3_source.arn
}

