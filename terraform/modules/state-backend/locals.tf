locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${local.account_id}-tf-state-${substr(sha256(local.account_id), 0, 8)}"
}
