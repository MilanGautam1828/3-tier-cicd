variable "env" {
  description = "Environment name"
  type        = string
}

variable "domain_name" {
  description = "The domain name for the frontend (e.g., rockymeranaam.site)"
  type        = string
  default     = "rockymeranaam.site" # Change this if your domain is different
}


provider "aws" {
  region = "us-east-1"
}

# --- VPC and Basic Networking (No changes here from your script) ---
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.env}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.env}-igw"
  }
}

# NAT Gateway Elastic IP
resource "aws_eip" "nat_eip" {
  domain = "vpc"
  tags = {
    Name = "${var.env}-nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id # Assuming one NAT GW for now
  tags = {
    Name = "${var.env}-nat"
  }
  depends_on = [aws_internet_gateway.igw]
}

# Route Table - Public
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Name = "${var.env}-public-rt"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# Route Table - Private
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }
  tags = {
    Name = "${var.env}-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# Subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.env}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "${var.env}-public-b"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "${var.env}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "${var.env}-private-b"
  }
}
# --- End Basic Networking ---


# --- ECS Cluster & IAM Role (No changes here) ---
resource "aws_ecs_cluster" "main" {
  name = "${var.env}-ecs-cluster"
  tags = {
    Name = "${var.env}-ecs-cluster"
  }
}

# This is the Task EXECUTION Role, used by ECS agent to pull images, fetch secrets/ssm for 'secrets' block
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.env}-ecs-task-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${var.env}-ecs-task-exec-role" }
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_base_policy_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# --- MODIFIED: IAM Policy for Task EXECUTION Role to access MongoDB Secret (v8) from Secrets Manager ---
resource "aws_iam_policy" "ecs_task_execution_secrets_manager_policy" {
  name        = "${var.env}-ecs-task-exec-secrets-mgr-policy-v8" # CHANGED
  description = "Allows ECS Task Execution Role to read the MongoDB URI secret (v8) from Secrets Manager" # CHANGED
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt"
        ],
        Resource = [
          aws_secretsmanager_secret.mongo_uri_secret.arn # This will point to the -v8 secret
        ]
      }
    ]
  })
  tags = { Name = "${var.env}-ecs-task-exec-secrets-mgr-policy-v8" } # CHANGED
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets_manager_access_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_secrets_manager_policy.arn
}

# This is the Task Role, for application code running INSIDE the container to call AWS services.
resource "aws_iam_role" "ecs_backend_app_task_role" {
  name = "${var.env}-ecs-backend-app-task-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ecs-tasks.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
  tags = { Name = "${var.env}-ecs-backend-app-task-role" }
}
# --- End ECS Cluster & IAM Role ---


# --- ECR Repositories & Policies (MODIFIED ECR Policy JSON) ---
resource "aws_ecr_repository" "frontend_repo" {
  name                 = "${var.env}-frontend-repo"
  image_tag_mutability = "MUTABLE"
  lifecycle { ignore_changes = [name] }
  tags = { Name = "${var.env}-frontend-repo" }
}

resource "aws_ecr_lifecycle_policy" "frontend_repo_policy" {
  repository = aws_ecr_repository.frontend_repo.name
  policy = jsonencode({
    rules = [
      {
        "rulePriority": 1,
        "description": "Expire untagged images older than 14 days to keep the repository clean and reduce storage costs from old, unreferenced image layers for the frontend service.",
        "selection": {
          "tagStatus": "untagged",
          "countType": "sinceImagePushed",
          "countUnit": "days",
          "countNumber": 14
        },
        "action": {
          "type": "expire"
        }
      },
      {
        "rulePriority": 2,
        "description": "Keep only the last 5 tagged images (e.g., starting with 'v') to manage storage for versioned releases, removing older tagged images for the frontend service.",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["v"],
          "countType": "imageCountMoreThan",
          "countNumber": 5
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_repository" "backend_repo" {
  name                 = "${var.env}-backend-repo"
  image_tag_mutability = "MUTABLE"
  tags                 = { Name = "${var.env}-backend-repo" }
}

resource "aws_ecr_lifecycle_policy" "backend_repo_policy" {
  repository = aws_ecr_repository.backend_repo.name
  policy = jsonencode({
    rules = [
      {
        "rulePriority": 1,
        "description": "Expire untagged images older than 14 days to keep the repository clean and reduce storage costs from old, unreferenced image layers for the backend service.",
        "selection": {
          "tagStatus": "untagged",
          "countType": "sinceImagePushed",
          "countUnit": "days",
          "countNumber": 14
        },
        "action": {
          "type": "expire"
        }
      },
      {
        "rulePriority": 2,
        "description": "Keep only the last 5 tagged images (e.g., starting with 'v') to manage storage for versioned releases, removing older tagged images for the backend service.",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["v"],
          "countType": "imageCountMoreThan",
          "countNumber": 5
        },
        "action": {
          "type": "expire"
        }
      }
    ]
  })
}
# --- End ECR ---


# --- Route 53 & ACM ---
data "aws_route53_zone" "primary" {
  name         = "${var.domain_name}." # Note the trailing dot
  private_zone = false
}

resource "aws_acm_certificate" "frontend_cert" {
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"
  tags = {
    Name        = "${var.env}-frontend-cert"
    Environment = var.env
  }
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "frontend_cert_validation_records" {
  for_each = {
    for dvo in aws_acm_certificate.frontend_cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.primary.zone_id
}

resource "aws_acm_certificate_validation" "frontend_cert_validation" {
  certificate_arn         = aws_acm_certificate.frontend_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.frontend_cert_validation_records : record.fqdn]
}
# --- End Route 53 & ACM ---


# --- Security Groups ---
# Security Group for Public Frontend ALB
resource "aws_security_group" "frontend_alb_sg" {
  name        = "${var.env}-frontend-alb-sg"
  description = "Allow HTTP/HTTPS inbound to Frontend ALB"
  vpc_id      = aws_vpc.main.id
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
  tags = { Name = "${var.env}-frontend-alb-sg" }
}

# Security Group for Frontend ECS Tasks
resource "aws_security_group" "frontend_tasks_sg" {
  name        = "${var.env}-frontend-tasks-sg"
  description = "Allow traffic to frontend tasks from Frontend ALB"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "From Frontend ALB"
    from_port       = 80 # Frontend container port
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_alb_sg.id]
  }
  egress { # To backend ALB and internet (via IGW as tasks have public IP for ECR pull)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.env}-frontend-tasks-sg" }
}

# Security Group for Internal Backend ALB
resource "aws_security_group" "backend_alb_sg" {
  name        = "${var.env}-backend-alb-sg"
  description = "Allow traffic to backend ALB from frontend tasks"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "From Frontend Tasks"
    from_port       = 5000 # Backend ALB listener port
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_tasks_sg.id] # Source is frontend tasks SG
  }
  egress { # ALB to backend tasks
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.env}-backend-alb-sg" }
}

# Security Group for Backend ECS Tasks
resource "aws_security_group" "backend_tasks_sg" {
  name        = "${var.env}-backend-tasks-sg"
  description = "Allow traffic to backend tasks from Backend ALB"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "From Backend ALB"
    from_port       = 5000 # Backend container port
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_alb_sg.id] # Source is backend ALB's SG
  }
  egress { # To MongoDB via VPCE and internet (via NAT)
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.env}-backend-tasks-sg" }
}

# --- NEW: Security Group for MongoDB VPC Interface Endpoint ---
resource "aws_security_group" "mongodb_vpce_sg" {
  name        = "${var.env}-mongodb-vpce-sg"
  description = "Allow traffic to MongoDB VPC Endpoint from backend tasks"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "From Backend Tasks to MongoDB Endpoint"
    from_port       = 27017 # MongoDB port
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_tasks_sg.id] # Source is backend tasks SG
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.env}-mongodb-vpce-sg" }
}
# --- End Security Groups ---


# --- Frontend ALB & Listeners ---
resource "aws_lb" "frontend_alb" {
  name                       = "${var.env}-frontend-alb"
  internal                   = false
  load_balancer_type         = "application"
  subnets                    = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  security_groups            = [aws_security_group.frontend_alb_sg.id]
  enable_deletion_protection = false # Set to true for production
  tags                       = { Name = "${var.env}-frontend-alb" }
}

resource "aws_lb_target_group" "frontend_tg" {
  name        = "${var.env}-frontend-tg"
  port        = 80 # Frontend container port
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-299" # Frontend should serve 2xx on /
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = { Name = "${var.env}-frontend-tg" }
}

resource "aws_lb_listener" "frontend_http" {
  load_balancer_arn = aws_lb.frontend_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "frontend_https" {
  load_balancer_arn = aws_lb.frontend_alb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_acm_certificate_validation.frontend_cert_validation.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend_tg.arn
  }
  depends_on = [aws_acm_certificate_validation.frontend_cert_validation]
}
# --- End Frontend ALB ---


# --- Backend ALB & Listeners ---
resource "aws_lb" "backend_alb" {
  name               = "${var.env}-backend-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_groups    = [aws_security_group.backend_alb_sg.id]
  tags               = { Name = "${var.env}-backend-alb" }
}

resource "aws_lb_target_group" "backend_tg" {
  name        = "${var.env}-backend-tg"
  port        = 5000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/"       # Assuming backend has a GET / for health
    protocol            = "HTTP"
    matcher             = "200-399" # Backend health check
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
  tags = { Name = "${var.env}-backend-tg" }
}

resource "aws_lb_listener" "backend_listener" {
  load_balancer_arn = aws_lb.backend_alb.arn
  port              = 5000
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend_tg.arn
  }
}
# --- End Backend ALB ---

# --- NEW: VPC Interface Endpoint for MongoDB (MODIFIED private_dns_enabled and subnet_ids) ---
data "aws_region" "current" {} # To get the current region
data "aws_caller_identity" "current" {} # To get current account ID for KMS key ARN construction if needed

resource "aws_vpc_endpoint" "mongodb_interface_endpoint" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.vpce.us-east-1.vpce-svc-09f0c19c8688e5504" # HARDCODED SERVICE NAME
  vpc_endpoint_type  = "Interface"
  subnet_ids         = [aws_subnet.private_a.id] # Using only the supported AZ for the endpoint service
  security_group_ids = [aws_security_group.mongodb_vpce_sg.id]
  private_dns_enabled = false # Set to false as the service doesn't provide a private DNS name
  tags                 = { Name = "${var.env}-mongodb-interface-vpce" }
}
# --- End MongoDB VPC Endpoint ---

# --- NEW: AWS Secrets Manager Secret for MongoDB URI (Name updated to -v8) ---
resource "aws_secretsmanager_secret" "mongo_uri_secret" {
  name        = "${var.env}/mongo_uri-v8" # CHANGED
  description = "MongoDB connection URI v8 for the backend service using PrivateLink" # CHANGED
  tags = {
    Name        = "${var.env}-mongo-uri-secret-v8" # CHANGED
    Environment = var.env
  }
}

# --- NEW: null_resource to update the secret after VPC endpoint is created ---
resource "null_resource" "update_mongo_uri_secret" {
  # Trigger this when the VPC endpoint's DNS entries change or the base secret ARN changes
  triggers = {
    vpce_dns_trigger = join(",", sort(aws_vpc_endpoint.mongodb_interface_endpoint.dns_entry.*.dns_name))
    secret_arn       = aws_secretsmanager_secret.mongo_uri_secret.arn
  }

  # Ensure the VPC endpoint and the base secret resource exist before trying to update
  depends_on = [
    aws_vpc_endpoint.mongodb_interface_endpoint,
    aws_secretsmanager_secret.mongo_uri_secret
  ]

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<EOT
      set -e
      DNS_ENTRIES_COUNT=$(echo '${length(aws_vpc_endpoint.mongodb_interface_endpoint.dns_entry.*.dns_name)}' | tr -d '[:space:]')
      echo "Number of DNS entries found for MongoDB VPCE: $DNS_ENTRIES_COUNT"

      if [ "$DNS_ENTRIES_COUNT" -gt 0 ]; then
        echo "VPC Endpoint DNS entries found. Updating secret..."
        FIRST_DNS_NAME=$(echo '${element(aws_vpc_endpoint.mongodb_interface_endpoint.dns_entry.*.dns_name, 0)}' | tr -d '[:space:]')
        echo "Using first DNS name for MONGO_URI: $FIRST_DNS_NAME"

        aws secretsmanager put-secret-value \
          --secret-id "${aws_secretsmanager_secret.mongo_uri_secret.id}" \
          --secret-string "mongodb://$FIRST_DNS_NAME:27017/contacts" \
          --region "${data.aws_region.current.name}"
        echo "MongoDB URI secret updated successfully in Secrets Manager."
      else
        echo "WARNING: No VPC Endpoint DNS entries found for MongoDB. Secret not updated."
      fi
    EOT
  }
}


# --- ECS Task Definitions ---
resource "aws_ecs_task_definition" "frontend_task" {
  family                   = "${var.env}-frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  container_definitions = jsonencode([{
    name      = "frontend-container",
    image     = "${aws_ecr_repository.frontend_repo.repository_url}:latest",
    essential = true,
    portMappings = [{ containerPort = 80, hostPort = 80, protocol = "tcp" }],
    environment  = [{ name = "BACKEND_URL", value = "http://${aws_lb.backend_alb.dns_name}:5000" }]
    // Ensure your frontend app reads BACKEND_URL and its server.js listens on port 80
  }])
  tags = { Name = "${var.env}-frontend-task" }
}

# --- RE-ADD: CloudWatch Log Group for Backend ECS Tasks ---
resource "aws_cloudwatch_log_group" "backend_ecs_logs" {
  name              = "/ecs/${var.env}-backend-task" # Matches task definition family
  retention_in_days = 30                             # Or your desired retention period
  # tags block removed to avoid logs:TagResource permission issue for Terraform executor
}

resource "aws_ecs_task_definition" "backend_task" {
  family                   = "${var.env}-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_backend_app_task_role.arn

  container_definitions = jsonencode([{
    name      = "backend-container",
    image     = "${aws_ecr_repository.backend_repo.repository_url}:latest",
    essential = true,
    portMappings = [{ containerPort = 5000, hostPort = 5000, protocol = "tcp" }],
    secrets = [
      {
        name      = "MONGO_URI",
        valueFrom = aws_secretsmanager_secret.mongo_uri_secret.arn # This ARN now refers to the secret named with -v8
      }
    ],
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend_ecs_logs.name, # Reference the created log group
        "awslogs-region"        = data.aws_region.current.name,
        "awslogs-stream-prefix" = "ecs"
      }
    }
    // Ensure your backend app (index.js) listens on port 5000 and has GET / for health check
  }])

  depends_on = [
    null_resource.update_mongo_uri_secret,
    aws_cloudwatch_log_group.backend_ecs_logs # Add dependency on the log group
  ]
  tags = { Name = "${var.env}-backend-task" }
}
# --- End ECS Task Definitions ---


# --- ECS Services ---
resource "aws_ecs_service" "frontend_service" {
  name            = "${var.env}-frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend_task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id, aws_subnet.public_b.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.frontend_tasks_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.frontend_tg.arn
    container_name   = "frontend-container"
    container_port   = 80
  }

  depends_on = [
    aws_ecs_cluster.main,
    aws_lb_listener.frontend_https,
    aws_lb_listener.frontend_http
  ]
  tags = { Name = "${var.env}-frontend-service" }
}

resource "aws_ecs_service" "backend_service" {
  name            = "${var.env}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend_task.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.backend_tasks_sg.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend_tg.arn
    container_name   = "backend-container"
    container_port   = 5000
  }

  depends_on = [
    aws_ecs_cluster.main,
    aws_lb_listener.backend_listener,
    aws_vpc_endpoint.mongodb_interface_endpoint
  ]
  tags = { Name = "${var.env}-backend-service" }
}
# --- End ECS Services ---


# --- Route 53 Records for Frontend ALB ---
resource "aws_route53_record" "frontend_apex" {
  zone_id         = data.aws_route53_zone.primary.zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = true
  alias {
    name                   = aws_lb.frontend_alb.dns_name
    zone_id                = aws_lb.frontend_alb.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "frontend_www" {
  zone_id         = data.aws_route53_zone.primary.zone_id
  name            = "www.${var.domain_name}"
  type            = "A"
  allow_overwrite = true
  alias {
    name                   = aws_lb.frontend_alb.dns_name
    zone_id                = aws_lb.frontend_alb.zone_id
    evaluate_target_health = true
  }
}
# --- End Route 53 Records ---


# --- Outputs ---
output "frontend_alb_dns_name" {
  description = "The DNS name of the public frontend Application Load Balancer."
  value       = aws_lb.frontend_alb.dns_name
}

output "backend_alb_dns_name" {
  description = "The DNS name of the internal backend Application Load Balancer."
  value       = aws_lb.backend_alb.dns_name
}

output "frontend_url" {
  description = "Main URL for the frontend application."
  value       = "https://${var.domain_name}"
}

output "mongodb_vpce_dns_entries" {
  description = "DNS entries for the MongoDB VPC Interface Endpoint. Use one of these for MONGO_URI if needed for debugging."
  value       = aws_vpc_endpoint.mongodb_interface_endpoint.dns_entry.*.dns_name
}

output "mongo_uri_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the MongoDB URI."
  value       = aws_secretsmanager_secret.mongo_uri_secret.arn # This correctly refers to the updated secret
}