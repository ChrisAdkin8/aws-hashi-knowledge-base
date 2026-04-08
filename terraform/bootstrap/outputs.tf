output "bucket_name" {
  description = "State bucket name — pass to main module terraform init."
  value       = module.state_backend.bucket_name
}

output "bucket_arn" {
  description = "State bucket ARN."
  value       = module.state_backend.bucket_arn
}

output "backend_config" {
  description = "Ready-to-use -backend-config flags for the main module terraform init."
  value       = module.state_backend.backend_config
}
