resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnets"
  subnet_ids = aws_subnet.private[*].id
  tags       = { Name = "${var.project_name}-db-subnets" }
}

resource "aws_db_instance" "notes" {
  identifier     = "${var.project_name}-db"
  engine         = "postgres"
  engine_version = var.db_engine_version

  instance_class    = var.db_instance_class
  allocated_storage = var.db_allocated_storage
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  # No password here, ever. AWS generates and stores it in Secrets
  # Manager for us, encrypted with the account's default KMS key, and
  # can rotate it automatically. This is the single most important
  # "secrets management" lesson in this whole project: the master
  # password never exists in Terraform state, git, or a .tfvars file.
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.db_multi_az
  publicly_accessible = false
  skip_final_snapshot = true # fine for a learning project; false + a
                              # final_snapshot_identifier for anything real
  deletion_protection = false

  backup_retention_period    = 1
  copy_tags_to_snapshot      = true
  auto_minor_version_upgrade = true

  tags = { Name = "${var.project_name}-db" }
}
