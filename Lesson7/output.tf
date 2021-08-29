output "private-key" {
  value = tls_private_key.private-key.private_key_pem
  sensitive = true
}

output "public-key-openssh" {
  value = tls_private_key.private-key.public_key_openssh
}

output "puppet-master" {
  value = aws_instance.puppet.*.public_ip[0]
}

output "puppet-client" {
  value = aws_instance.puppet.*.public_ip[1]
}
