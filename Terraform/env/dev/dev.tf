terraform {
  required_version = ">= 1.5.0"
  backend "s3" {
    required_providers {
      aws = {
        source  = "hashicorp/aws"
        version = "20.8.3"
      }
      archive = {
        source  = "hashicorp/archive"
        version = "~> 2.0"
      }
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Environment = "dev"
      ManagedBy   = "terraform"
      Owner       = "devops"
    }
  }
}


module "snapshot_cleanup" {
  source = "../../modules/snapshot_cleanup"

  # General
  environment  = "dev"
  region       = "us-east-1"

  vpc_cidr                  = "10.0.0.0/16"
  private_subnet_cidr       = "10.0.1.0/24"
  availability_zone         = "us-east-1a"

  lambda_runtime          = "python3.12"
  lambda_timeout          = 300
  lambda_memory_size      = 128
  snapshot_retention_days = 365

  # EventBridge — daily at 02:00 UTC
  lambda_schedule         = "cron(0 2 * * ? *)"

  log_retention_days = 30
}

