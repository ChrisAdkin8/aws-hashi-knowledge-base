resource "aws_s3_bucket" "graph_staging" {
  bucket        = local.staging_bucket_name
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "graph_staging" {
  bucket = aws_s3_bucket.graph_staging.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "graph_staging" {
  bucket = aws_s3_bucket.graph_staging.id
  rule {
    id     = "expire-graph-snapshots"
    status = "Enabled"
    filter {}
    expiration { days = 30 }
    noncurrent_version_expiration { noncurrent_days = 7 }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "graph_staging" {
  bucket = aws_s3_bucket.graph_staging.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "graph_staging" {
  bucket                  = aws_s3_bucket.graph_staging.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
