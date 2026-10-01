# Lightdash query results and exports (replaces local MinIO). The host's instance role reads and writes it,
# so there are no access keys. Presigned download URLs point at real S3 and work from any browser (cf. D-026).
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "lightdash" {
  bucket        = "${var.project}-lightdash-${data.aws_caller_identity.current.account_id}"
  force_destroy = true # results/exports are disposable
}

resource "aws_s3_bucket_public_access_block" "lightdash" {
  bucket                  = aws_s3_bucket.lightdash.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "lightdash" {
  bucket = aws_s3_bucket.lightdash.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "lightdash" {
  bucket = aws_s3_bucket.lightdash.id
  rule {
    id     = "expire-results"
    status = "Enabled"
    filter {}
    expiration { days = 7 }
  }
}
