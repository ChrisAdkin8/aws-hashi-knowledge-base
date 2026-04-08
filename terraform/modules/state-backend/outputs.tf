output "bucket_name" {
  description = "Name of the Terraform state S3 bucket."
  value       = aws_s3_bucket.state.id
}

output "bucket_arn" {
  description = "ARN of the Terraform state S3 bucket."
  value       = aws_s3_bucket.state.arn
}

output "region" {
  description = "Region the state bucket was created in."
  value       = var.region
}

output "backend_config" {
  description = "Ready-to-use -backend-config flags for terraform init."
  value       = "-backend-config=\"bucket=${aws_s3_bucket.state.id}\" -backend-config=\"region=${var.region}\""
}
