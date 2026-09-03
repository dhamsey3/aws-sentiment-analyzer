variable "aws_region" {
  description = "AWS region"
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Name of the project"
  default     = "sentiment-analysis"
}

variable "reddit_client_id" {
  description = "Reddit API Client ID"
  sensitive   = true
}

variable "reddit_client_secret" {
  description = "Reddit API Client Secret"
  sensitive   = true
}


variable "notification_email" {
  type        = string
  description = "Email for QuickSight notifications"
  validation {
    condition     = can(regex("^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$", var.notification_email))
    error_message = "Invalid email format."
  }
}