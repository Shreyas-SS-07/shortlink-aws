resource "aws_ecr_repository" "app" {
  name                 = var.project
  image_tag_mutability = "MUTABLE"
  force_delete         = true # lets `terraform destroy` clean up after demos
  image_scanning_configuration { scan_on_push = true }
}

resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db"
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_db_instance" "main" {
  identifier        = "${var.project}-db"
  engine            = "postgres"
  engine_version    = "16"
  instance_class    = var.db_instance_class
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "shortlink"
  username = "shortlink"
  # RDS creates and rotates the master password in Secrets Manager. No password in code or state.
  manage_master_user_password = true

  multi_az               = var.db_multi_az
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = false

  backup_retention_period = 1
  skip_final_snapshot     = true # demo project; set false for real data
  deletion_protection     = false
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.project}-redis"
  subnet_ids = aws_subnet.data[*].id
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id       = "${var.project}-redis"
  description                = "Redirect cache, click counters, rate limiter"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = var.redis_node_type
  num_cache_clusters         = 1 # raise to 2 (+ automatic_failover_enabled) for HA
  subnet_group_name          = aws_elasticache_subnet_group.main.name
  security_group_ids         = [aws_security_group.redis.id]
  at_rest_encryption_enabled = true
}
