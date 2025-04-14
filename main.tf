# Configuration du provider AWS
provider "aws" {
  region = "us-east-1"
  # Pour LocalStack
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true

  endpoints {
    ec2            = "http://localhost:4566"
    rds            = "http://localhost:4566"
    elasticloadbalancing = "http://localhost:4566"
    iam            = "http://localhost:4566"
    cloudfront     = "http://localhost:4566"
    s3             = "http://localhost:4566"
  }
}

# Variables
variable "environment" {
  default = "dev"
}

variable "vpc_cidr" {
  default = "10.0.0.0/16"
}

variable "db_username" {
  default = "admin"
}

variable "db_password" {
  default = "StrongPassword123!" # À changer dans un environnement de production
}

# VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  
  tags = {
    Name = "wordpress-vpc-${var.environment}"
  }
}

# Sous-réseaux publics dans 2 AZs pour le load balancer
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true
  
  tags = {
    Name = "wordpress-public-subnet-${count.index}-${var.environment}"
  }
}

# Sous-réseaux privés dans 2 AZs pour EC2 et RDS
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.wordpress_vpc.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 2)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  
  tags = {
    Name = "wordpress-private-subnet-${count.index}-${var.environment}"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
  
  tags = {
    Name = "wordpress-igw-${var.environment}"
  }
}

# NAT Gateway pour permettre aux instances privées d'accéder à Internet
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id
  
  tags = {
    Name = "wordpress-nat-${var.environment}"
  }
}

# Table de routage pour les sous-réseaux publics
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.wordpress_vpc.id
  
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  
  tags = {
    Name = "wordpress-public-rt-${var.environment}"
  }
}

# Table de routage pour les sous-réseaux privés
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.wordpress_vpc.id
  
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  
  tags = {
    Name = "wordpress-private-rt-${var.environment}"
  }
}

# Association des tables de routage
resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# Groupe de sécurité pour l'ALB
resource "aws_security_group" "alb_sg" {
  name        = "wordpress-alb-sg"
  description = "ALB Security Group"
  vpc_id      = aws_vpc.wordpress_vpc.id
  
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "wordpress-alb-sg-${var.environment}"
  }
}

# Groupe de sécurité pour EC2
resource "aws_security_group" "ec2_sg" {
  name        = "wordpress-ec2-sg"
  description = "WordPress EC2 Security Group"
  vpc_id      = aws_vpc.wordpress_vpc.id
  
  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "wordpress-ec2-sg-${var.environment}"
  }
}

# Groupe de sécurité pour RDS
resource "aws_security_group" "rds_sg" {
  name        = "wordpress-rds-sg"
  description = "RDS Security Group"
  vpc_id      = aws_vpc.wordpress_vpc.id
  
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
  }
  
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  tags = {
    Name = "wordpress-rds-sg-${var.environment}"
  }
}

# Rôle IAM pour EC2
resource "aws_iam_role" "wordpress_role" {
  name = "wordpress-ec2-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

# Politique IAM pour accéder à S3 (pour les sauvegardes)
resource "aws_iam_policy" "s3_access" {
  name        = "wordpress-s3-access"
  description = "Allow WordPress to access S3 for backups"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Effect   = "Allow"
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.wordpress_bucket.id}",
          "arn:aws:s3:::${aws_s3_bucket.wordpress_bucket.id}/*"
        ]
      }
    ]
  })
}

# Attacher la politique au rôle
resource "aws_iam_role_policy_attachment" "s3_access_attachment" {
  role       = aws_iam_role.wordpress_role.name
  policy_arn = aws_iam_policy.s3_access.arn
}

# Profil d'instance pour EC2
resource "aws_iam_instance_profile" "wordpress_profile" {
  name = "wordpress-instance-profile"
  role = aws_iam_role.wordpress_role.name
}

# Subnet group pour RDS
resource "aws_db_subnet_group" "wordpress_db_subnet" {
  name       = "wordpress-db-subnet"
  subnet_ids = aws_subnet.private[*].id
  
  tags = {
    Name = "wordpress-db-subnet-${var.environment}"
  }
}

# Base de données RDS
resource "aws_db_instance" "wordpress_db" {
  allocated_storage      = 20
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  identifier             = "wordpress-db"
  db_name                = "wordpress"
  username               = var.db_username
  password               = var.db_password
  parameter_group_name   = "default.mysql8.0"
  db_subnet_group_name   = aws_db_subnet_group.wordpress_db_subnet.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  skip_final_snapshot    = true
  multi_az               = true  # Pour haute disponibilité
  backup_retention_period = 7    # Sauvegardes quotidiennes pendant 7 jours
  
  tags = {
    Name = "wordpress-db-${var.environment}"
  }
}

# Bucket S3 pour les médias et les sauvegardes
resource "aws_s3_bucket" "wordpress_bucket" {
  bucket = "wordpress-media-${var.environment}-${random_string.suffix.result}"
  
  tags = {
    Name = "wordpress-bucket-${var.environment}"
  }
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# Politique de bucket S3
resource "aws_s3_bucket_policy" "wordpress_bucket_policy" {
  bucket = aws_s3_bucket.wordpress_bucket.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action   = ["s3:GetObject"]
        Effect   = "Allow"
        Resource = "${aws_s3_bucket.wordpress_bucket.arn}/*"
        Principal = {
          AWS = aws_cloudfront_origin_access_identity.oai.iam_arn
        }
      }
    ]
  })
}

# CloudFront Origin Access Identity
resource "aws_cloudfront_origin_access_identity" "oai" {
  comment = "OAI for WordPress S3 bucket"
}

# CloudFront Distribution
resource "aws_cloudfront_distribution" "wordpress_cdn" {
  origin {
    domain_name = aws_s3_bucket.wordpress_bucket.bucket_regional_domain_name
    origin_id   = "S3-${aws_s3_bucket.wordpress_bucket.id}"
    
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    }
  }
  
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${aws_s3_bucket.wordpress_bucket.id}"
    
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
    
    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }
  
  price_class = "PriceClass_100"  # Optimisation des coûts: utilise uniquement les emplacements les moins chers
  
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  
  viewer_certificate {
    cloudfront_default_certificate = true
  }
  
  tags = {
    Name = "wordpress-cdn-${var.environment}"
  }
}

# Application Load Balancer
resource "aws_lb" "wordpress_alb" {
  name               = "wordpress-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = aws_subnet.public[*].id
  
  tags = {
    Name = "wordpress-alb-${var.environment}"
  }
}

# Target Group pour ALB
resource "aws_lb_target_group" "wordpress_tg" {
  name     = "wordpress-target-group"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.wordpress_vpc.id
  
  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }
  
  tags = {
    Name = "wordpress-tg-${var.environment}"
  }
}

# Listener pour ALB
resource "aws_lb_listener" "wordpress_listener" {
  load_balancer_arn = aws_lb.wordpress_alb.arn
  port              = 80
  protocol          = "HTTP"
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.wordpress_tg.arn
  }
}

# User data script pour WordPress
data "template_file" "user_data" {
  template = <<-EOF
  #!/bin/bash
  # Mettre à jour le système
  apt-get update && apt-get upgrade -y
  
  # Installer les dépendances
  apt-get install -y apache2 mysql-client php php-mysql php-curl php-gd php-intl php-mbstring php-soap php-xml php-xmlrpc php-zip
  
  # Télécharger et installer WordPress
  wget https://wordpress.org/latest.tar.gz
  tar -xzf latest.tar.gz
  cp -R wordpress/* /var/www/html/
  chown -R www-data:www-data /var/www/html/
  
  # Créer le fichier de configuration WordPress
  cat > /var/www/html/wp-config.php << WPCONFIG
<?php
define('DB_NAME', '${aws_db_instance.wordpress_db.db_name}');
define('DB_USER', '${var.db_username}');
define('DB_PASSWORD', '${var.db_password}');
define('DB_HOST', '${aws_db_instance.wordpress_db.endpoint}');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

define('AUTH_KEY',         '$(openssl rand -hex 32)');
define('SECURE_AUTH_KEY',  '$(openssl rand -hex 32)');
define('LOGGED_IN_KEY',    '$(openssl rand -hex 32)');
define('NONCE_KEY',        '$(openssl rand -hex 32)');
define('AUTH_SALT',        '$(openssl rand -hex 32)');
define('SECURE_AUTH_SALT', '$(openssl rand -hex 32)');
define('LOGGED_IN_SALT',   '$(openssl rand -hex 32)');
define('NONCE_SALT',       '$(openssl rand -hex 32)');

define('WP_DEBUG', false);

// Configuration pour S3
define('AS3CF_SETTINGS', serialize(array(
    'provider' => 'aws',
    'access-key-id' => '${aws_iam_role.wordpress_role.name}',
    'secret-access-key' => '',
    'use-instance-profile' => true,
    'bucket' => '${aws_s3_bucket.wordpress_bucket.id}',
    'region' => '${var.region}'
)));

// Configuration pour CloudFront
define('CLOUDFRONT_URL', '${aws_cloudfront_distribution.wordpress_cdn.domain_name}');

\$table_prefix = 'wp_';

require_once(ABSPATH . 'wp-settings.php');
WPCONFIG
  
  # Installer le plugin Amazon S3 pour WordPress
  cd /var/www/html/wp-content/plugins/
  wget https://downloads.wordpress.org/plugin/amazon-s3-and-cloudfront.zip
  unzip amazon-s3-and-cloudfront.zip
  chown -R www-data:www-data amazon-s3-and-cloudfront
  
  # Redémarrer Apache
  systemctl restart apache2
  EOF
}

# EC2 Launch Template
resource "aws_launch_template" "wordpress_template" {
  name_prefix   = "wordpress-"
  image_id      = "ami-0c55b159cbfafe1f0"  # Remplacer par une AMI Ubuntu récente
  instance_type = "t3.micro"
  
  user_data = base64encode(data.template_file.user_data.rendered)
  
  iam_instance_profile {
    name = aws_iam_instance_profile.wordpress_profile.name
  }
  
  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.ec2_sg.id]
  }
  
  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "wordpress-ec2-${var.environment}"
    }
  }
}

# Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                = "wordpress-asg"
  vpc_zone_identifier = aws_subnet.private[*].id
  desired_capacity    = 1  # Optimisation des coûts: commencer avec une seule instance
  min_size            = 1
  max_size            = 3
  
  launch_template {
    id      = aws_launch_template.wordpress_template.id
    version = "$Latest"
  }
  
  target_group_arns = [aws_lb_target_group.wordpress_tg.arn]
  
  health_check_type         = "ELB"
  health_check_grace_period = 300
  
  tag {
    key                 = "Name"
    value               = "wordpress-asg-${var.environment}"
    propagate_at_launch = true
  }
}

# Auto Scaling Policy basée sur l'utilisation CPU
resource "aws_autoscaling_policy" "scale_out" {
  name                   = "wordpress-scale-out"
  scaling_adjustment     = 1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
}

resource "aws_autoscaling_policy" "scale_in" {
  name                   = "wordpress-scale-in"
  scaling_adjustment     = -1
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.wordpress_asg.name
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "wordpress-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 70
  alarm_description   = "Scale out if CPU > 70% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_out.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress_asg.name
  }
}

resource "aws_cloudwatch_metric_alarm" "low_cpu" {
  alarm_name          = "wordpress-low-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 30
  alarm_description   = "Scale in if CPU < 30% for 4 minutes"
  alarm_actions       = [aws_autoscaling_policy.scale_in.arn]
  
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.wordpress_asg.name
  }
}

# Data source pour obtenir les AZs disponibles
data "aws_availability_zones" "available" {}

# Outputs
output "alb_dns_name" {
  value = aws_lb.wordpress_alb.dns_name
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.wordpress_cdn.domain_name
}

output "rds_endpoint" {
  value = aws_db_instance.wordpress_db.endpoint
}

output "s3_bucket" {
  value = aws_s3_bucket.wordpress_bucket.id
}