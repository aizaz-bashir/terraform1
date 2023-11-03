provider "aws" {
}


module "vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-west-3a","eu-west-3b"]
  public_subnets  = ["10.0.101.0/24","10.0.102.0/24"]
  public_subnet_tags = {Name= "my-subnets"}


  tags = {
    Name="my-vpc"
  }
}

resource "aws_route" "main_route" {
  route_table_id         = module.vpc.default_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = module.vpc.igw_id
}



resource "aws_security_group" "my-sg" {
  name = "my-sg"
  vpc_id = module.vpc.vpc_id

  ingress = [ {
    from_port =22
    to_port = 22
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
    ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups = []
      self            = false
  },

  {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
    ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups = []
      self            = false
  }
  ]
   egress = [
   {
    from_port =0
    to_port = 0
    protocol = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "all outbound traffic"
    ipv6_cidr_blocks = []
      prefix_list_ids  = []
      security_groups = []
      self            = false
  }
   ]
}


resource "aws_key_pair" "my-key-pair" {
  key_name  = "my-key-pair"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDL1LDQ8IKcart/WEJWEAaXhe9BcykEVJc4wMHdJhMbXN1gwgbExn7qoRCUgX0vAgALmTwEr+4tegYn/mrvPrA6OgcoaHvcvKXSxcd5F0EAWK/Gd2Z7N6lx6VKJxp1fKgWTjgRYnzbSCVl3uiAYoiGRwsxlXafK+HLXDAPlMhQKcr3DvYQQ896knmKUXOAzWeMOFlXVDvEk8f8CVyzrIZnwo9AqSf9EsGFe19OSrjRz9fd8hygqnnD6Aa5rB/zdNk2p8euxVdzrdgmVlxGm6C5G6cwnRUCTbArqZWQdiEwONZ+kG/dlRoDmrfzjdfJQcPMcFVeSlxNTW4zpglGWr5FL hashm@DESKTOP-MN05T8V"
  
}

data "aws_ami" "latest-amazon-image" {
  most_recent = true
  owners = ["amazon"]
   filter {
     name = "name"
     values = ["amzn2-ami-hvm-*-gp2"]
   }
   filter {
     name = "virtualization-type"
     values = ["hvm"]
   }
  
}


module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 8.0"

  name = "my-alb"

  load_balancer_type = "application"

  vpc_id             = module.vpc.vpc_id
  subnets            = module.vpc.public_subnets
  security_groups    = [aws_security_group.my-sg.id]

  target_groups = [
    {
       name     = "my-target-groups"
      backend_protocol = "HTTP"
      backend_port     = 80 
      vpc_id      = module.vpc.vpc_id
      target_type = "instance"
     target_group_arns=aws_lb_target_group.my-target-group.arn 
    
    }
  ]

  http_tcp_listeners = [
    {
      port               = 80
      protocol           = "HTTP"
      target_group_index = 0
    }
  ]

  tags = {
    Name = "my-alb"
  }
  
}
output "target_group_arns" {
    description = "ARN of the first target group"
    value       = module.alb.target_group_arns[0]
  }

  resource "aws_lb_target_group" "my-target-group" {
  name        = "my-target-group"
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "instance"
  port        = 80
 
}

resource "aws_autoscaling_group" "my-asg" {
  name                      = "my-asg"
  launch_template {
    id      = aws_launch_template.my-launch-template.id
  
  }
  vpc_zone_identifier       = module.vpc.public_subnets
  min_size                  = 1
  max_size                  = 3
  desired_capacity          = 2
  health_check_type         = "ELB"
  health_check_grace_period = 300

  target_group_arns = [module.alb.target_group_arns[0]] 
}

resource "aws_autoscaling_policy" "my-policy" {
  name          = "example-policy"
  policy_type   = "SimpleScaling"
  adjustment_type = "ChangeInCapacity"
  scaling_adjustment = 1
  autoscaling_group_name = aws_autoscaling_group.my-asg.name
  cooldown      = 300

  metric_aggregation_type = "Average"
  
}

resource "aws_launch_template" "my-launch-template" {
  name_prefix = "my-launch-template-"
  description = "My Launch Template"

  image_id = data.aws_ami.latest-amazon-image.id

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 8
    }
  }

  instance_type = "t2.micro"
  key_name      = "my-key-pair"

  network_interfaces {
    associate_public_ip_address = true
    security_groups = [aws_security_group.my-sg.id]
  }

  user_data =  base64encode(<<-EOF

#!/bin/bash
sudo amazon-linux-extras install epel -y
sudo yum install https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm -y
sudo yum install https://rpms.remirepo.net/enterprise/remi-release-7.rpm -y
sudo yum-config-manager --
enable
 remi-php74
sudo yum -y update
sudo yum -y install httpd
sudo service httpd start
sudo chkconfig httpd on

sudo amazon-linux-extras install -y php7.4 
sudo yum install -y php-mysql

sudo yum -y install mariadb-server
sudo service mariadb start
sudo chkconfig mariadb on

mysql_secure_installation <<-EOFI

y
abc123
abc123
y
y
y
y
EOFI

sudo mysql -u root -pabc123 <<-EOFC
CREATE DATABASE wordpress;
CREATE USER 'wordpress'@'localhost' IDENTIFIED BY 'abc123';
GRANT ALL PRIVILEGES ON wordpress.* TO 'wordpress'@'localhost';
FLUSH PRIVILEGES;
EOFC

sudo wget https://wordpress.org/latest.tar.gz
tar -xzvf latest.tar.gz -C /var/www/html/
mv /var/www/html/wordpress/* /var/www/html/
rm -rf /var/www/html/wordpress
rm -f latest.tar.gz

sudo chown -R apache:apache /var/www/html/
sudo chmod -R 755 /var/www/html/

sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i 's/database_name_here/wordpress/' /var/www/html/wp-config.php
sed -i 's/username_here/wordpress/' /var/www/html/wp-config.php
sed -i 's/password_here/abc123/' /var/www/html/wp-config.php

service httpd restart

EOF
  )

  
}




