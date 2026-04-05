terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    # Bucket and region supplied at init time via -backend-config flags.
    # Run scripts/bootstrap_state.sh to create them first.
    key          = "terraform/state/rag-pipeline/terraform.tfstate"
    use_lockfile = true
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
