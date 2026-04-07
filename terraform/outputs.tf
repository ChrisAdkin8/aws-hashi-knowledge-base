output "rag_bucket_name" {
  description = "S3 bucket name for processed RAG documents."
  value       = aws_s3_bucket.rag_docs.id
}

output "rag_bucket_arn" {
  description = "ARN of the RAG documents S3 bucket."
  value       = aws_s3_bucket.rag_docs.arn
}

output "kendra_index_id" {
  description = "Kendra index ID."
  value       = aws_kendra_index.main.id
}

output "kendra_index_arn" {
  description = "Kendra index ARN."
  value       = aws_kendra_index.main.arn
}

output "kendra_data_source_id" {
  description = "Kendra S3 data source ID."
  value       = local.kendra_data_source_id
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine."
  value       = aws_sfn_state_machine.rag_pipeline.arn
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project."
  value       = aws_codebuild_project.rag_pipeline.name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project."
  value       = aws_codebuild_project.rag_pipeline.arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild execution IAM role."
  value       = aws_iam_role.codebuild.arn
}

output "aws_region" {
  description = "AWS region where resources are deployed."
  value       = var.region
}
