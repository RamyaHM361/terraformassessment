provider "aws" {
  region = var.aws_region
}

// Data block for availability zones and ami id
data "aws_availability_zones" "available" {}
data "aws_ami" "latest" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

// VPC
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "mainvpc"
  }
}

// Subnets
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = element(var.public_subnet_cidrs, count.index)
  availability_zone       = element(data.aws_availability_zones.available.names, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "public-subnet-${count.index + 1}"
  }
}

resource "aws_subnet" "private" {
  count             = 4
  vpc_id            = aws_vpc.main.id
  cidr_block        = element(var.private_subnet_cidrs, count.index)
  availability_zone = element(data.aws_availability_zones.available.names, count.index % length(data.aws_availability_zones.available.names))

  tags = {
    Name = "private-subnet-${count.index + 1}"
  }
}

// Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main-igw"
  }
}

// Route Table for Public Subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
// Security groups
resource "aws_security_group" "allow_ssh" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
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
    Name = "allow-ssh"
  }
}
// SG for ELB
resource "aws_security_group" "allow_app" {
  vpc_id = aws_vpc.main.id

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
    Name = "allow-app"
  }
}
// SG for RDS-DB
resource "aws_security_group" "rds_sg" {
  name        = "rds-security-group"
  vpc_id      = aws_vpc.main.id 

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "RDS Security Group"
  }
}
// Jumpserver
resource "aws_instance" "jump_server" {
  ami           = data.aws_ami.latest.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.public[0].id
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "JumpServer"
  }
}
// App Instance1
resource "aws_instance" "app_instance_1" {
  ami           = data.aws_ami.latest.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private[0].id

  vpc_security_group_ids = [aws_security_group.allow_app.id]

  tags = {
    Name = "AppInstance1"
  }
}
// DB Instance
resource "aws_db_instance" "db_instance" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "8.0.33"
  instance_class       = "db.t3.micro"
  username             = var.db_username
  password             = var.db_password
  db_subnet_group_name = aws_db_subnet_group.db_subnet_group.name
  publicly_accessible  = false
  
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  tags = {
    Name = "DBInstance"
  }
}
// DB Subnet group
resource "aws_db_subnet_group" "db_subnet_group" {
  name       = "main-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id 

  tags = {
    Name = "DBSubnetGroup"
  }
}
// App instance2
resource "aws_instance" "app_instance_2" {
  ami           = data.aws_ami.latest.id
  instance_type = var.instance_type
  subnet_id     = aws_subnet.private[2].id

  vpc_security_group_ids = [aws_security_group.allow_app.id]

  tags = {
    Name = "AppInstance2"
  }
}
// ELB
resource "aws_elb" "main" {
  name    = "main-elb"
  subnets = [
    aws_subnet.public[0].id, 
    aws_subnet.public[1].id  
  ]

  listener {
    instance_port     = 80
    instance_protocol = "HTTP"
    lb_port           = 80
    lb_protocol       = "HTTP"
  }

  health_check {
    target              = "HTTP:80/"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  security_groups = [aws_security_group.allow_app.id] 

  tags = {
    Name = "MainELB"
  }
}


