terraform {
  backend "s3" {
    bucket       = "terraformstatebucket20018"
    key          = "envs/dev/ecs/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
  required_version = "1.13.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.2.0"
    }

    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}
