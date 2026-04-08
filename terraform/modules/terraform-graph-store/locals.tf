locals {
  staging_bucket_name = "hashicorp-graph-staging-${var.region}-${substr(sha256(var.account_id), 0, 8)}"
}
