terraform {
  backend "s3" {
    bucket = "cosign-aws-codepipeline-phxvlabs"
    key    = "cosign-aws-codepipeline-phxvlabs/terraform_state"
    region = "us-east-2"
  }
}
