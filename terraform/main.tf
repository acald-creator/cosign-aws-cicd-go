resource "aws_codecommit_repository" "cosign" {
  repository_name = "repository"
  default_branch  = "main"
  description     = "This is a sample app repository for ${var.name}"
}

resource "aws_ecr_repository" "ecr" {
  name                 = "distroless-base"
  image_tag_mutability = "IMMUTABLE"
  image_scanning_configuration {
    scan_on_push = true
  }
  tags = {
    env = var.name
  }
}

resource "aws_kms_key" "cosign" {
  description             = "Cosign Key"
  deletion_window_in_days = 10
  tags = {
    env = var.name
  }
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "RSA_4096"
}

resource "aws_kms_alias" "cosign" {
  name          = "alias/${var.name}"
  target_key_id = aws_kms_key.cosign.key_id
}