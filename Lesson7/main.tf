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

resource "aws_instance" "puppet" {
  count         = 2 
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.deployer.key_name
  security_groups = ["Hello-World-SG"]
  tags = {
    Name = "Puppet${count.index}"
  }
}

resource "null_resource" "puppet_master" {
    connection {
      host = aws_instance.puppet.*.public_ip[0]
      user = "ubuntu"
      type = "ssh"
      private_key = tls_private_key.private-key.private_key_pem
    }

    provisioner "file" {
	source      = "${path.cwd}/files/ex7File.pp"
    	destination = "/tmp/ex7File.pp"
    }
    provisioner "remote-exec" {
	inline = [
		"sudo apt-get update -y",
		"sudo su -c 'echo \"${aws_instance.puppet.*.public_ip[0]} ${aws_instance.puppet.*.private_dns[0]} puppet\" >> /etc/hosts'",
		"sudo su -c 'echo \"${aws_instance.puppet.*.public_ip[1]} ${aws_instance.puppet.*.private_dns[1]}\" >> /etc/hosts'",
		"wget https://apt.puppetlabs.com/puppet6-release-focal.deb",
		"sudo dpkg -i puppet6-release-focal.deb",
		"sudo apt-get update -y",
		"sudo apt-get install puppetserver -y",
		"sudo sed -i '9s#.*#JAVA_ARGS=\"-Xms512m -Xmx512m -Djruby.logger.class=com.puppetlabs.jruby_utils.jruby.Slf4jLogger\"#' /etc/default/puppetserver",
		"sudo systemctl start puppetserver",
		"sudo systemctl enable puppetserver",
		"sudo mkdir -p /etc/puppet/code/environments/production/manifests",
		"sudo cp /tmp/ex7File.pp /etc/puppet/code/environments/production/manifests/ex7File.pp" 
    	]
    }


}

resource "null_resource" "puppet_client" {
    connection {
      host = aws_instance.puppet.*.public_ip[1]
      user = "ubuntu"
      type = "ssh"
      private_key = tls_private_key.private-key.private_key_pem
    }
    provisioner "remote-exec" {
	inline = [
		"wget https://apt.puppetlabs.com/puppet6-release-focal.deb",
		"sudo dpkg -i puppet6-release-focal.deb",
		"sudo apt-get update -y",
		"sudo su -c 'echo \"${aws_instance.puppet.*.public_ip[0]} puppetserver puppet\" >> /etc/hosts'",
		"sudo su -c 'echo \"${aws_instance.puppet.*.public_ip[1]} puppet\" >> /etc/hosts'",
		"sudo apt-get install puppet-agent -y",
		"sudo su -c 'echo -ne \"[main]\ncertname = ${aws_instance.puppet.*.private_dns[1]} \nserver = ${aws_instance.puppet.*.private_dns[0]}\" >> /etc/puppetlabs/puppet/puppet.conf'",
		"sudo systemctl start puppet",
		"sudo systemctl enable puppet"
	]
    }
}

resource "null_resource" "puppet_certs" {
    depends_on = [ null_resource.puppet_client,null_resource.puppet_master ]
    connection {
      host = aws_instance.puppet.*.public_ip[0]
      user = "ubuntu"
      type = "ssh"
      private_key = tls_private_key.private-key.private_key_pem
    }
    provisioner "remote-exec" {
	inline = [
		"sudo /opt/puppetlabs/bin/puppetserver ca list --all",
		"sudo /opt/puppetlabs/bin/puppetserver ca sign --all",
		"sudo /opt/puppetlabs/bin/puppet agent --test",
	]
    }
}

# Additional instructions:
# On Puppet Client: sudo rm -f /etc/puppetlabs/puppet/ssl/certs/$(hostname -f)
# On Puppet Master: sudo /opt/puppetlabs/bin/puppetserver ca clean --certname <hostnamefqdn>\
# On Puppet Client: find /var/lib/puppet -name *yourhostnamehere* -delete
# On Puppet Client: puppent agent -tf
# On Puppet Master: sudo /opt/puppetlabs/bin/puppetserver ca list --all
#                    sudo /opt/puppetlabs/bin/puppetserver ca sign --all", 

# Logging into instance
# terraform apply -auto-approve
# terraform output -raw private-key > ~/.ssh/student.pem
# chmod 600 ~/.ssh/student.pem 
# puppet-master: ssh -i ~/.ssh/student.pem ubuntu@$(terraform output -raw puppet-master)
# puppet-client: ssh -i ~/.ssh/student.pem ubuntu@$(terraform output -raw puppet-cient)
# terraform destroy -auto-approve 
