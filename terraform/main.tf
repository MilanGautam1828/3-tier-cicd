# Define the AWS provider and region
provider "aws" {
  region = "us-east-1"  # Set the region to us-east-1
}

# Create the VPC
resource "aws_vpc" "threeVpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_support = true
  enable_dns_hostnames = true
  tags = {
    Name = "three-tier-vpc"  # Name for the VPC
  }
}

# Create a public subnet in us-east-1a
resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.threeVpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-1"  # Name for Public Subnet 1
  }
}

# Create a public subnet in us-east-1b
resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.threeVpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-2"  # Name for Public Subnet 2
  }
}

# Create a private subnet in us-east-1a
resource "aws_subnet" "private_1" {
  vpc_id            = aws_vpc.threeVpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = {
    Name = "private-subnet-1"  # Name for Private Subnet 1
  }
}

# Create a private subnet in us-east-1b
resource "aws_subnet" "private_2" {
  vpc_id            = aws_vpc.threeVpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = {
    Name = "private-subnet-2"  # Name for Private Subnet 2
  }
}
