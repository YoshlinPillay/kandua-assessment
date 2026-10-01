# Application secrets, generated here and stored as SSM SecureStrings under /juan/. The host reads them at
# deploy time with its instance role. Trade-off (docs/decisions.md): random_password values also live in the
# Terraform state, which is in a private, encrypted, versioned S3 bucket. The RDS master password does not
# (it is managed by RDS in Secrets Manager).

locals {
  generated_secrets = {
    "postgres-loader-password" = 32 # dlt/dbt role; the RDS master login only creates roles (it rotates)
    "postgres-reader-password" = 32
    "lightdash-secret"         = 48
    "lightdash-db-password"    = 32
    "cubejs-api-secret"        = 48
    "basic-auth-password"      = 20
  }
}

resource "random_password" "app" {
  for_each = local.generated_secrets
  length   = each.value
  special  = false # used in URLs, env files and connection strings
}

resource "random_password" "lightdash_pat" {
  length  = 40
  special = false
}

resource "aws_ssm_parameter" "app" {
  for_each = local.generated_secrets
  name     = "/${var.project}/${each.key}"
  type     = "SecureString"
  value    = random_password.app[each.key].result
}

resource "aws_ssm_parameter" "lightdash_pat" {
  name  = "/${var.project}/lightdash-api-key"
  type  = "SecureString"
  value = "ldpat_${random_password.lightdash_pat.result}" # Lightdash personal access token format
}

# Non-secret deploy settings the host needs (plain strings).
resource "aws_ssm_parameter" "config" {
  for_each = {
    "rds-host"             = aws_db_instance.warehouse.address
    "rds-master-secret"    = aws_db_instance.warehouse.master_user_secret[0].secret_arn
    "lightdash-bucket"     = aws_s3_bucket.lightdash.bucket
    "public-domain"        = local.domain
    "bedrock-region"       = var.bedrock_region
    "bedrock-model-id"     = var.bedrock_model_id
    "lightdash-admin-mail" = var.admin_email
  }
  name  = "/${var.project}/config/${each.key}"
  type  = "String"
  value = each.value
}
