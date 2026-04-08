output "aws_region" {
  description = "AWS region where resources are deployed."
  value       = var.region
}

# ── hashicorp-kendra-rag ──────────────────────────────────────────────────────

output "rag_bucket_name" {
  description = "S3 bucket name for processed RAG documents."
  value       = module.hashicorp_docs_pipeline.rag_bucket_name
}

output "rag_bucket_arn" {
  description = "ARN of the RAG documents S3 bucket."
  value       = module.hashicorp_docs_pipeline.rag_bucket_arn
}

output "kendra_index_id" {
  description = "Kendra index ID."
  value       = module.hashicorp_docs_pipeline.kendra_index_id
}

output "kendra_index_arn" {
  description = "Kendra index ARN."
  value       = module.hashicorp_docs_pipeline.kendra_index_arn
}

output "kendra_data_source_id" {
  description = "Kendra S3 data source ID."
  value       = module.hashicorp_docs_pipeline.kendra_data_source_id
}

output "state_machine_arn" {
  description = "ARN of the Step Functions state machine."
  value       = module.hashicorp_docs_pipeline.state_machine_arn
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project."
  value       = module.hashicorp_docs_pipeline.codebuild_project_name
}

output "codebuild_project_arn" {
  description = "ARN of the CodeBuild project."
  value       = module.hashicorp_docs_pipeline.codebuild_project_arn
}

output "codebuild_role_arn" {
  description = "ARN of the CodeBuild execution IAM role."
  value       = module.hashicorp_docs_pipeline.codebuild_role_arn
}

# ── terraform-graph-store ────────────────────────────────────────────────────

output "neptune_cluster_endpoint" {
  description = "Neptune cluster writer endpoint."
  value       = try(module.terraform_graph_store[0].cluster_endpoint, null)
}

output "neptune_cluster_reader_endpoint" {
  description = "Neptune cluster reader endpoint."
  value       = try(module.terraform_graph_store[0].cluster_reader_endpoint, null)
}

output "neptune_cluster_arn" {
  description = "Neptune cluster ARN."
  value       = try(module.terraform_graph_store[0].cluster_arn, null)
}

output "neptune_port" {
  description = "Neptune port."
  value       = try(module.terraform_graph_store[0].port, null)
}

output "graph_state_machine_arn" {
  description = "ARN of the graph pipeline Step Functions state machine."
  value       = try(module.terraform_graph_store[0].state_machine_arn, null)
}

output "graph_staging_bucket_name" {
  description = "S3 bucket name for rover JSON staging."
  value       = try(module.terraform_graph_store[0].graph_staging_bucket_name, null)
}

output "graph_codebuild_project_name" {
  description = "Name of the graph pipeline CodeBuild project."
  value       = try(module.terraform_graph_store[0].codebuild_project_name, null)
}
