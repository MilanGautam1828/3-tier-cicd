variable "env" {
  description = "Environment name"
  type        = string
}

provider "aws" {
  region = "us-east-1"
}

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
  vpc = true
  tags = {
    Name = "${var.env}-nat-eip"
  }
}

# NAT Gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
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

# ECS Cluster
resource "aws_ecs_cluster" "main" {
  name = "${var.env}-ecs-cluster"
  tags = {
    Name = "${var.env}-ecs-cluster"
  }
}

# ECR Repository for Frontend
resource "aws_ecr_repository" "frontend_repo" {
  name                 = "${var.env}-frontend-repo"
  image_tag_mutability = "MUTABLE"

  lifecycle {
    ignore_changes = [name]
  }

  tags = {
    Name = "${var.env}-frontend-repo"
  }
}

# ECR Lifecycle Policy - Frontend
resource "aws_ecr_lifecycle_policy" "frontend_repo_policy" {
  repository = aws_ecr_repository.frontend_repo.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1,
        description  = "Remove untagged images older than 14 days",
        selection = {
          tagStatus   = "untagged",
          countType   = "sinceImagePushed",
          countUnit   = "days",
          countNumber = 14
        },
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# IAM Role for ECS Task Execution
resource "aws_iam_role" "ecs_task_execution_role" {
  name = "${var.env}-ecs-task-exec-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_attach" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# Security Group for ECS
resource "aws_security_group" "ecs_service" {
  name        = "${var.env}-ecs-sg"
  description = "Allow HTTP inbound traffic"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Internal ALB for Backend
resource "aws_lb" "backend_alb" {
  name               = "${var.env}-backend-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  security_groups    = [aws_security_group.ecs_service.id]
}

resource "aws_lb_target_group" "backend_tg" {
  name     = "${var.env}-backend-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    path                = "/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200-399"
  }
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

# Task Definition - Frontend (with BACKEND_URL)
resource "aws_ecs_task_definition" "frontend_task" {
  family                   = "${var.env}-frontend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "frontend-container",
    image = "${aws_ecr_repository.frontend_repo.repository_url}:latest",
    essential = true,
    portMappings = [{
      containerPort = 80,
      hostPort      = 80,
      protocol      = "tcp"
    }],
    environment = [
      {
        name  = "BACKEND_URL",
        value = "http://${aws_lb.backend_alb.dns_name}:5000"
      }
    ]
  }])
}

# ECS Service - Frontend
resource "aws_ecs_service" "frontend_service" {
  name            = "${var.env}-frontend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.frontend_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public_a.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.ecs_service.id]
  }

  depends_on = [aws_ecs_cluster.main]
}

# ECR Repository - Backend
resource "aws_ecr_repository" "backend_repo" {
  name                 = "${var.env}-backend-repo"
  image_tag_mutability = "MUTABLE"
  tags = {
    Name = "${var.env}-backend-repo"
  }
}

resource "aws_ecr_lifecycle_policy" "backend_repo_policy" {
  repository = aws_ecr_repository.backend_repo.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1,
      description  = "Remove untagged images older than 14 days",
      selection = {
        tagStatus   = "untagged",
        countType   = "sinceImagePushed",
        countUnit   = "days",
        countNumber = 14
      },
      action = {
        type = "expire"
      }
    }]
  })
}

# ECS Task Definition - Backend
resource "aws_ecs_task_definition" "backend_task" {
  family                   = "${var.env}-backend-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_task_execution_role.arn

  container_definitions = jsonencode([{
    name  = "backend-container",
    image = "${aws_ecr_repository.backend_repo.repository_url}:latest",
    essential = true,
    portMappings = [{
      containerPort = 5000,
      hostPort      = 5000,
      protocol      = "tcp"
    }],
    environment = [
      {
        name  = "MONGO_URI",
        value = "mongodb://your-mongodb-uri"
      }
    ]
  }])
}

# ECS Service - Backend with ALB Target Group
resource "aws_ecs_service" "backend_service" {
  name            = "${var.env}-backend-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.backend_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_b.id]
    assign_public_ip = false
    security_groups  = [aws_security_group.ecs_service.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.backend_tg.arn
    container_name   = "backend-container"
    container_port   = 5000
  }

  depends_on = [aws_ecs_cluster.main, aws_lb_listener.backend_listener]
}
