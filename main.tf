# Specify the provider (AWS)
provider "aws" {
  region = var.aws_region
}

# Define variables
variable "aws_region" {
  default = "us-west-2"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr_block" {
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr_block" {
  default = "10.0.2.0/24"
}

variable "key_name" {
  default = "my_key_pair"
}

variable "ami_id" {
  default = "ami-0c55b159cbfafe1f0"
}

variable "instance_type" {
  default = "t2.micro"
}

variable "desired_capacity" {
  default = 2
}

variable "max_size" {
  default = 4
}

variable "min_size" {
  default = 2
}

variable "db_name" {
  default = "wordpress"
}

variable "db_username" {
  default = "admin"
}

variable "db_password" {
  default = "password123"
}

# Create VPC
resource "aws_vpc" "wordpress_vpc" {
  cidr_block = var.vpc_cidr_block
}

# Create public subnet
resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.public_subnet_cidr_block
  availability_zone = "${var.aws_region}a"
}

# Create private subnet
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.wordpress_vpc.id
  cidr_block = var.private_subnet_cidr_block
  availability_zone = "${var.aws_region}b"
}

# Create internet gateway
resource "aws_internet_gateway" "wordpress_igw" {
  vpc_id = aws_vpc.wordpress_vpc.id
}

# Attach internet gateway to VPC
resource "aws_vpc_attachment" "wordpress_igw_attachment" {
  vpc_id       = aws_vpc.wordpress_vpc.id
  internet_gateway_id = aws_internet_gateway.wordpress_igw.id
}

# Create NAT gateway
resource "aws_nat_gateway" "wordpress_nat_gateway" {
  allocation_id = aws_eip.wordpress_eip.id
  subnet_id     = aws_subnet.public_subnet.id
}

# Create Elastic IP
resource "aws_eip" "wordpress_eip" {
  vpc = true
}

# Associate Elastic IP with NAT gateway
resource "aws_eip_association" "wordpress_eip_association" {
  allocation_id = aws_eip.wordpress_eip.id
  subnet_id     = aws_subnet.public_subnet.id
}

# Create security groups
resource "aws_security_group" "wordpress_sg" {
  name_prefix = "wordpress_sg_"
  vpc_id      = aws_vpc.wordpress_vpc.id
}

# Allow traffic from the public subnet to the application instances
resource "aws_security_group_rule" "wordpress_sg_ingress" {
  security_group_id = aws_security_group.wordpress_sg.id
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [aws_subnet.public_subnet.cidr_block]
}

# Allow traffic from the private subnet to the RDS instance
resource "aws_security_group_rule" "wordpress_rds_ingress" {
  security_group_id = aws_security_group.wordpress_sg.id
  type              = "ingress"
  from_port         = 0
  to_port           = 65535
  protocol          = "tcp"
  cidr_blocks       = [aws_subnet.private_subnet.cidr_block]
}

# Create Application Load Balancer
resource "aws_lb" "wordpress_lb" {
  name               = "wordpress_lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.wordpress_sg.id]
  subnets            = [aws_subnet.public_subnet.id]
}

# Create Auto Scaling Group
resource "aws_autoscaling_group" "wordpress_asg" {
  name                 = "wordpress_asg"
  launch_configuration = aws_launch_configuration.wordpress_lc.name
  min_size             = var.min_size
  max_size             = var.max_size
  desired_capacity     = var.desired_capacity
  vpc_zone_identifier  = [aws_subnet.private_subnet.id]
}

# Create Launch Configuration
resource "aws_launch_configuration" "wordpress_lc" {
  name_prefix = "wordpress_lc_"
  image_id    = var.ami_id
  instance_type = var.instance_type
  key_name = var.key_name
  security_groups = [aws_security_group.wordpress_sg.id]
  user_data = <<-EOF
              #!/bin/bash
             # Install Apache, PHP, and WordPress
              yum update -y
              yum install -y httpd php php-mysqlnd
              systemctl start httpd.service
              systemctl enable httpd.service
              cd /var/www/html
              curl -O https://wordpress.org/latest.tar.gz
              tar -xzvf latest.tar.gz
              rm -f latest.tar.gz
              cp -r wordpress/* .
              rm -rf wordpress
              chown -R apache:apache /var/www/html/
              EOF
}

# Create RDS instance
resource "aws_db_instance" "wordpress_rds" {
  allocated_storage    = 20
  engine               = "mysql"
  engine_version       = "5.7"
  instance_class       = "db.t2.micro"
  name                 = var.db_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.mysql5.7"
  vpc_security_group_ids = [aws_security_group.wordpress_sg.id]
  subnet_group_name    = "wordpress_rds_subnet_group"
}

# Create RDS subnet group
resource "aws_db_subnet_group" "wordpress_rds_subnet_group" {
  name       = "wordpress_rds_subnet_group"
  subnet_ids = [aws_subnet.private_subnet.id]
}

# Create Route 53 record
resource "aws_route53_record" "wordpress_dns" {
  name    = "example.com"
  type    = "A"
  zone_id = "my_zone_id"
  alias {
    name                   = aws_lb.wordpress_lb.dns_name
    zone_id                = aws_lb.wordpress_lb.zone_id
    evaluate_target_health = true
  }
}
# Output the load balancer URL
output "wordpress_lb_url" {
  value = aws_lb.wordpress_lb.dns_name
}

# Output the RDS endpoint URL
output "wordpress_rds_url" {
  value = aws_db_instance.wordpress_rds.endpoint
}