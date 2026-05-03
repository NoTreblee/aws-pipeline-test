terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "ecr_registry_url" {
  description = "ECR registry URL"
  type        = string
  default     = "000000000000.dkr.ecr.eu-central-1.amazonaws.com"
}

variable "ecr_repository_name" {
  description = "ECR repository name"
  type        = string
  default     = "aws-pipeline-test"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

provider "aws" {
	region = var.aws_region
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"]
}

resource "aws_instance" "app_server" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.deployer.key_name
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = <<EOF
#!/bin/bash
set -ex

# Install Docker
apt-get update -y
apt-get install -y ca-certificates curl
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo "\$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Install AWS CLI
apt-get install -y awscli

# Get ECR login password and login to ECR
ECR_REGISTRY="${var.ecr_registry_url}"
ECR_REPOSITORY="${var.ecr_repository_name}"
aws ecr get-login-password --region ${var.aws_region} | docker login --username AWS --password-stdin $ECR_REGISTRY

# Pull the latest image
IMAGE_NAME=$ECR_REGISTRY/$ECR_REPOSITORY:latest
docker pull $IMAGE_NAME

# Run the container
docker stop web-app 2>/dev/null || true
docker rm web-app 2>/dev/null || true
docker run -d --name web-app -p 80:80 $IMAGE_NAME
EOF

  tags = {
    Name = "pipeline-test"
  }
}

resource "aws_key_pair" "deployer" {
  key_name   = "pipeline-test-key"
  public_key = file("~/.ssh/pipeline-test-key.pub")
}

resource "aws_security_group" "app" {
  name        = "pipeline-test-sg"
  description = "Allow SSH and HTTP"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
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
