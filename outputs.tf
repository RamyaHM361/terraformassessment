output "elb_dns_name" {
  value = aws_elb.main.dns_name
}
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnets" {
  value = aws_subnet.public[*].id
}

output "private_subnets" {
  value = aws_subnet.private[*].id
}

output "jump_server_public_ip" {
  value = aws_instance.jump_server.public_ip
}

output "db_instance_endpoint" {
  value = aws_db_instance.db_instance.endpoint
}

