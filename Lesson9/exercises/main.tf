provider "aws" {
  region                  = "us-east-1"
  access_key              = var.access_key
  secret_key              = var.secret_key
  token                   = var.session_token
}

resource "tls_private_key" "private-key" {
  algorithm   = "RSA"
  rsa_bits    = 2048
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = tls_private_key.private-key.public_key_openssh
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_security_group" "student-sg" {
  name = "Hello-World-SG"
  description = "Student security group"

  tags = {
    Name = "Hello-World-SG"
    Environment = terraform.workspace
  }
}

resource "aws_security_group_rule" "create-sgr-ssh" {
  security_group_id = aws_security_group.student-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 22
  protocol          = "tcp"
  to_port           = 22
  type              = "ingress"
}

resource "aws_security_group_rule" "create-sgr-inbound" {
  security_group_id = aws_security_group.student-sg.id
  cidr_blocks       = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = "all"
  to_port           = 65535
  type              = "ingress"
}

resource "aws_security_group_rule" "create-sgr-outbound" {
  security_group_id = aws_security_group.student-sg.id
  cidr_blocks         = ["0.0.0.0/0"]
  from_port         = 0
  protocol          = "all"
  to_port           = 65535
  type              = "egress"
}

resource "aws_instance" "web" {
  count         = 3
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer.key_name
  security_groups = ["Hello-World-SG"]
  tags = {
    Name = "Web${count.index}"
  }
}

resource "null_resource" "basic" {
  
    connection {
      host = aws_instance.web.*.public_dns[0]
      user = "ubuntu"
      type = "ssh"
      private_key = tls_private_key.private-key.private_key_pem
    }

    provisioner "local-exec" {
      command = "echo '${tls_private_key.private-key.private_key_pem}' > ~/.ssh/student.pem && chmod 600 ~/.ssh/student.pem"   
    }
  
    provisioner "remote-exec" {
      inline = [
        "echo \"[webservers]\" >> ~/hosts"
      ]
    }

    provisioner "remote-exec" {
      inline = [
        "echo -ne '${aws_instance.web.*.public_dns[1]}/n${aws_instance.web.*.public_dns[2]}' >> ~/hosts",
        "sudo apt-get update",
        "sudo apt-get install ansible -y"
      ]
    }
}

resource "null_resource" "web" {
    depends_on = [null_resource.basic]
    count = length(aws_instance.web.*.public_dns)

    connection {
      host = aws_instance.web.*.public_dns[count.index]
      user = "ubuntu"
      type = "ssh"
      private_key = tls_private_key.private-key.private_key_pem
    }
  
    provisioner "remote-exec" {
      inline = [
        "echo '${tls_private_key.private-key.private_key_pem}' > ~/.ssh/student.pem",
        "chmod 600 ~/.ssh/student.pem"
      ]
    }
}
