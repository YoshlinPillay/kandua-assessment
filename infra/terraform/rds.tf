resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db"
  subnet_ids = data.aws_subnets.default.ids
}

# rds.force_ssl: every connection must use TLS. That's what makes public read-only access acceptable.
resource "aws_db_parameter_group" "postgres16" {
  name   = "${var.project}-postgres16"
  family = "postgres16"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot" # static parameter; AWS records it this way (perpetual diff otherwise)
  }
}

resource "aws_db_instance" "warehouse" {
  identifier     = "${var.project}-warehouse"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  db_name  = "juan"
  username = "juan_admin"
  # The master password is generated and rotated by RDS in Secrets Manager, so it never enters Terraform state.
  manage_master_user_password = true

  allocated_storage     = 20
  max_allocated_storage = 50
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  parameter_group_name   = aws_db_parameter_group.postgres16.name
  publicly_accessible    = length(var.db_public_cidrs) > 0

  backup_retention_period = 1
  # Assessment environment: `make tf-destroy` must remove everything, so no snapshot or deletion lock.
  deletion_protection = false
  skip_final_snapshot = true
  apply_immediately   = true
}
