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

# --- VPC and Basic Networking ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.env}-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "${var.env}-igw"
  }
}

resource "aws_eip" "nat_eip" {
  domain = "vpc" # Corrected from 'instance = true' to 'domain = "vpc"' for NAT Gateway EIP
  tags = {
    Name = "${var.env}-nat-eip"
  }
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
  tags = {
    Name = "${var.env}-nat"
  }
  depends_on = [aws_internet_gateway.igw]
}

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


# --- ECS Cluster & IAM Role ---
resource "aws_ecs_cluster" "main" {
  name = "${var.env}-ecs-cluster"
  tags = {
    Name = "${var.env}-ecs-cluster"
  }
}

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

# --- MODIFIED: IAM Policy for Task EXECUTION Role to access MongoDB Secret (v9) from Secrets Manager ---
resource "aws_iam_policy" "ecs_task_execution_secrets_manager_policy" {
  name        = "${var.env}-ecs-task-exec-secrets-mgr-policy-v9" # CHANGED
  description = "Allows ECS Task Execution Role to read the MongoDB URI secret (v9) from Secrets Manager" # CHANGED
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = [
          "secretsmanager:GetSecretValue",
          "kms:Decrypt" # If the secret is encrypted with a CMK, ECS Task Role needs kms:Decrypt
        ],
        Resource = [
          aws_secretsmanager_secret.mongo_uri_secret.arn # This will point to the -v9 secret
        ]
      }
    ]
  })
  tags = { Name = "${var.env}-ecs-task-exec-secrets-mgr-policy-v9" } # CHANGED
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_secrets_manager_access_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = aws_iam_policy.ecs_task_execution_secrets_manager_policy.arn
}

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


# --- ECR Repositories & Policies ---
resource "aws_ecr_repository" "frontend_repo" {
  name                 = "${var.env}-frontend-repo"
  image_tag_mutability = "MUTABLE"
  lifecycle { ignore_changes = [name] } # To prevent Terraform from trying to recreate if name is "managed" elsewhere
  tags = { Name = "${var.env}-frontend-repo" }
}

resource "aws_ecr_lifecycle_policy" "frontend_repo_policy" {
  repository = aws_ecr_repository.frontend_repo.name
  policy = jsonencode({
    rules = [
      {
        "rulePriority": 1,
        "description": "Expire untagged images older than 14 days for frontend.",
        "selection": {
          "tagStatus": "untagged",
          "countType": "sinceImagePushed",
          "countUnit": "days",
          "countNumber": 14
        },
        "action": { "type": "expire" }
      },
      {
        "rulePriority": 2,
        "description": "Keep only the last 5 tagged images for frontend.",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["v"],
          "countType": "imageCountMoreThan",
          "countNumber": 5
        },
        "action": { "type": "expire" }
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
        "description": "Expire untagged images older than 14 days for backend.",
        "selection": {
          "tagStatus": "untagged",
          "countType": "sinceImagePushed",
          "countUnit": "days",
          "countNumber": 14
        },
        "action": { "type": "expire" }
      },
      {
        "rulePriority": 2,
        "description": "Keep only the last 5 tagged images for backend.",
        "selection": {
          "tagStatus": "tagged",
          "tagPrefixList": ["v"],
          "countType": "imageCountMoreThan",
          "countNumber": 5
        },
        "action": { "type": "expire" }
      }
    ]
  })
}
# --- End ECR ---


# --- Route 53 & ACM ---
data "aws_route53_zone" "primary" {
  name         = "${var.domain_name}."
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

resource "aws_security_group" "frontend_tasks_sg" {
  name        = "${var.env}-frontend-tasks-sg"
  description = "Allow traffic to frontend tasks from Frontend ALB"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "From Frontend ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_alb_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.env}-frontend-tasks-sg" }
}

resource "aws_security_group" "backend_alb_sg" {
  name        = "${var.env}-backend-alb-sg"
  description = "Allow traffic to backend ALB from frontend tasks"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "From Frontend Tasks"
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.frontend_tasks_sg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.env}-backend-alb-sg" }
}

resource "aws_security_group" "backend_tasks_sg" {
  name        = "${var.env}-backend-tasks-sg"
  description = "Allow traffic to backend tasks from Backend ALB and for MongoDB"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "From Backend ALB"
    from_port       = 5000 # Backend container port
    to_port         = 5000
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_alb_sg.id]
  }
  # CHANGED: Added inbound rule for port 27017
  # WARNING: Allowing 0.0.0.0/0 on port 27017 to your backend tasks is generally
  # not recommended unless your tasks are specifically designed to listen publicly on this port.
  # This rule implies the backend tasks themselves are listening for MongoDB connections from anywhere.
  # Typically, backend tasks act as MongoDB *clients*, initiating outbound connections.
  ingress {
    description = "Allow inbound all for MongoDB port (if backend tasks listen on 27017 - review security)"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # "allow inbound all"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${var.env}-backend-tasks-sg" }
}

resource "aws_security_group" "mongodb_vpce_sg" {
  name        = "${var.env}-mongodb-vpce-sg"
  description = "Allow traffic to MongoDB VPC Endpoint from backend tasks"
  vpc_id      = aws_vpc.main.id
  ingress {
    description     = "From Backend Tasks to MongoDB Endpoint"
    from_port       = 27017
    to_port         = 27017
    protocol        = "tcp"
    security_groups = [aws_security_group.backend_tasks_sg.id]
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
  enable_deletion_protection = false
  tags                       = { Name = "${var.env}-frontend-alb" }
}

resource "aws_lb_target_group" "frontend_tg" {
  name        = "${var.env}-frontend-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "ip"
  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-299"
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
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200-399"
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

# --- VPC Interface Endpoint for MongoDB ---
data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

resource "aws_vpc_endpoint" "mongodb_interface_endpoint" {
  vpc_id             = aws_vpc.main.id
  service_name       = "com.amazonaws.vpce.us-east-1.vpce-svc-09f0c19c8688e5504" # HARDCODED - Ensure this is your correct service name
  vpc_endpoint_type  = "Interface"
  # CHANGED: Using both private subnets for HA
  subnet_ids         = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_group_ids = [aws_security_group.mongodb_vpce_sg.id]
  private_dns_enabled = false # Set to true ONLY if the service supports it and you want to use its private DNS name
  tags                 = { Name = "${var.env}-mongodb-interface-vpce" }
}
# --- End MongoDB VPC Endpoint ---

# --- AWS Secrets Manager Secret for MongoDB URI (Name updated to -v9) ---
resource "aws_secretsmanager_secret" "mongo_uri_secret" {
  name        = "${var.env}/mongo_uri-v9" # CHANGED
  description = "MongoDB connection URI v9 for the backend service using PrivateLink" # CHANGED
  tags = {
    Name        = "${var.env}-mongo-uri-secret-v9" # CHANGED
    Environment = var.env
  }
}

# --- null_resource to update the secret after VPC endpoint is created ---
resource "null_resource" "update_mongo_uri_secret" {
  triggers = {
    vpce_dns_trigger = join(",", sort(aws_vpc_endpoint.mongodb_interface_endpoint.dns_entry.*.dns_name))
    secret_arn       = aws_secretsmanager_secret.mongo_uri_secret.arn
  }

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
        # Use the first available DNS name for the endpoint.
        # In a multi-AZ setup, there will be multiple DNS names.
        # Applications should ideally resolve the regional endpoint DNS name or handle multiple for HA.
        # For the secret, we'll pick the first one for simplicity.
        FIRST_DNS_NAME=$(echo '${element(aws_vpc_endpoint.mongodb_interface_endpoint.dns_entry.*.dns_name, 0)}' | tr -d '[:space:]')
        echo "Using first DNS name for MONGO_URI: $FIRST_DNS_NAME"

        # Ensure your MongoDB connection string format is correct for your specific MongoDB setup (e.g., replica sets might need more DNS names).
        aws secretsmanager put-secret-value \
          --secret-id "${aws_secretsmanager_secret.mongo_uri_secret.id}" \
          --secret-string "mongodb://$FIRST_DNS_NAME:27017/contacts" \
          --region "${data.aws_region.current.name}"
        echo "MongoDB URI secret updated successfully in Secrets Manager."
      else
        echo "WARNING: No VPC Endpoint DNS entries found for MongoDB. Secret not updated."
        # Consider failing the apply here if the secret is critical and must be populated.
        # exit 1
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
    image     = "${aws_ecr_repository.frontend_repo.repository_url}:latest", # Consider using specific tags/digests
    essential = true,
    portMappings = [{ containerPort = 80, hostPort = 80, protocol = "tcp" }],
    environment  = [{ name = "BACKEND_URL", value = "http://${aws_lb.backend_alb.dns_name}:5000" }]
  }])
  tags = { Name = "${var.env}-frontend-task" }
}

resource "aws_cloudwatch_log_group" "backend_ecs_logs" {
  name              = "/ecs/${var.env}-backend-task"
  retention_in_days = 30
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
    image     = "${aws_ecr_repository.backend_repo.repository_url}:latest", # Consider using specific tags/digests
    essential = true,
    portMappings = [{ containerPort = 5000, hostPort = 5000, protocol = "tcp" }],
    secrets = [
      {
        name      = "MONGO_URI",
        valueFrom = aws_secretsmanager_secret.mongo_uri_secret.arn # Will now get the -v9 secret
      }
    ],
    logConfiguration = {
      logDriver = "awslogs",
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.backend_ecs_logs.name,
        "awslogs-region"        = data.aws_region.current.name,
        "awslogs-stream-prefix" = "ecs"
      }
    }
  }])
  depends_on = [
    null_resource.update_mongo_uri_secret,
    aws_cloudwatch_log_group.backend_ecs_logs
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
    aws_lb_listener.frontend_https # Ensures ALB is ready
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
    aws_lb_listener.backend_listener, # Ensures ALB is ready
    aws_vpc_endpoint.mongodb_interface_endpoint # Ensures VPCE is ready before tasks needing it start
  ]
  tags = { Name = "${var.env}-backend-service" }
}
# --- End ECS Services ---


# --- Route 53 Records for Frontend ALB ---
resource "aws_route53_record" "frontend_apex" {
  zone_id         = data.aws_route53_zone.primary.zone_id
  name            = var.domain_name
  type            = "A"
  allow_overwrite = true # Use with caution, usually false unless you know you need to overwrite
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
  allow_overwrite = true # Use with caution
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
  description = "ARN of the Secrets Manager secret storing the MongoDB URI (now v9)."
  value       = aws_secretsmanager_secret.mongo_uri_secret.arn
}