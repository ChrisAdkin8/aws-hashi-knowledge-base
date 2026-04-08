terraform {
  # Bootstrap uses a local backend — it manages only the state bucket,
  # which must exist before the main root module can initialise its S3 backend.
  # State for this module is stored locally in terraform/bootstrap/terraform.tfstate
  # and should be kept safe (e.g. committed to a secure store or re-applied if lost —
  # the bucket is idempotent and prevent_destroy guards against accidental deletion).
  required_version = ">= 1.10, < 1.15"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "hashicorp-rag-pipeline"
      ManagedBy = "terraform"
    }
  }
}
