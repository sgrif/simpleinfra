resource "random_password" "db" {
  length  = 64
  special = false
}

resource "aws_db_subnet_group" "db" {
  name       = "docs-rs-prod"
  subnet_ids = data.terraform_remote_state.shared.outputs.prod_vpc.private_subnets
}

data "aws_security_group" "bastion" {
  vpc_id = data.terraform_remote_state.shared.outputs.prod_vpc.id
  name   = "rust-prod-bastion"
}

data "aws_security_group" "legacy_instance" {
  vpc_id = data.terraform_remote_state.shared.outputs.legacy_vpc.id
  name   = "legacy-docs-rs-instance"
}

resource "aws_security_group" "db" {
  vpc_id      = data.terraform_remote_state.shared.outputs.prod_vpc.id
  name        = "docs-rs-db-prod"
  description = "Access to the docs.rs production database"

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    description     = "Connections from the legacy docs.rs instance"
    security_groups = [data.aws_security_group.legacy_instance.id]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    description     = "Connections from the docs.rs web servers on ECS"
    security_groups = [aws_security_group.web.id]
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    description     = "Connections from the bastion"
    security_groups = [data.aws_security_group.bastion.id]
  }
}

resource "aws_db_instance" "db" {
  identifier = "docs-rs-prod"

  engine         = "postgres"
  engine_version = "14.3"

  instance_class        = "db.t4g.small"
  storage_type          = "gp2"
  db_subnet_group_name  = aws_db_subnet_group.db.name
  allocated_storage     = 20
  max_allocated_storage = 100

  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.db.id]

  db_name  = "docsrs"
  username = "docsrs"
  password = random_password.db.result

  backup_retention_period = 30
  backup_window           = "05:00-06:00" # UTC

  deletion_protection      = true
  delete_automated_backups = false

  allow_major_version_upgrade = false
  auto_minor_version_upgrade  = true
  maintenance_window          = "Tue:15:00-Tue:16:00" # UTC

  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  performance_insights_enabled    = true

  lifecycle {
    ignore_changes = [
      latest_restorable_time
    ]
  }
}

resource "aws_ssm_parameter" "connection_url" {
  name  = "/prod/docs-rs/database-url"
  type  = "SecureString"
  value = "postgres://docsrs:${random_password.db.result}@${aws_db_instance.db.address}/docsrs"
}
