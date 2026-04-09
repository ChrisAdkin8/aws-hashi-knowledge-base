resource "aws_s3_bucket" "rag_docs" {
  bucket        = local.rag_bucket_name
  force_destroy = var.force_destroy

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "rag_docs" {
  bucket = aws_s3_bucket.rag_docs.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_lifecycle_configuration" "rag_docs" {
  bucket = aws_s3_bucket.rag_docs.id
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 90 }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "rag_docs" {
  bucket = aws_s3_bucket.rag_docs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "rag_docs" {
  bucket                  = aws_s3_bucket.rag_docs.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}
