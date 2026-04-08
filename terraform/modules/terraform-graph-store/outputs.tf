output "cluster_endpoint" {
  description = "Neptune cluster writer endpoint."
  value       = aws_neptune_cluster.main.endpoint
}

output "cluster_reader_endpoint" {
  description = "Neptune cluster reader endpoint."
  value       = aws_neptune_cluster.main.reader_endpoint
}

output "cluster_id" {
  description = "Neptune cluster identifier."
  value       = aws_neptune_cluster.main.id
}

output "cluster_arn" {
  description = "Neptune cluster ARN."
  value       = aws_neptune_cluster.main.arn
}

output "port" {
  description = "Neptune port (8182)."
  value       = aws_neptune_cluster.main.port
}

output "security_group_id" {
  description = "ID of the Neptune security group."
  value       = aws_security_group.neptune.id
}

output "graph_staging_bucket_name" {
  description = "S3 bucket name for rover JSON staging."
  value       = aws_s3_bucket.graph_staging.id
}

output "graph_staging_bucket_arn" {
  description = "ARN of the rover JSON staging S3 bucket."
  value       = aws_s3_bucket.graph_staging.arn
}

output "codebuild_project_name" {
  description = "Name of the graph pipeline CodeBuild project."
  value       = aws_codebuild_project.graph_pipeline.name
}

output "codebuild_project_arn" {
  description = "ARN of the graph pipeline CodeBuild project."
  value       = aws_codebuild_project.graph_pipeline.arn
}

output "state_machine_arn" {
  description = "ARN of the graph pipeline Step Functions state machine."
  value       = aws_sfn_state_machine.graph_pipeline.arn
}

output "neptune_proxy_url" {
  description = "API Gateway URL for the Neptune openCypher proxy (POST /query)."
  value       = var.create_neptune_proxy ? "${aws_apigatewayv2_api.neptune_proxy[0].api_endpoint}/query" : null
}
