#------------------------------------------------------------------------------
# EC2 Instance Outputs
#------------------------------------------------------------------------------
output "webserver_instance_id" {
  description = "ID of the web server EC2 instance"
  value       = aws_instance.webserver.id
}

output "webserver_public_ip" {
  description = "Public IP address (Elastic IP) of the web server"
  value       = aws_eip.ec2.public_ip
}

output "webserver_private_ip" {
  description = "Private IP address of the web server"
  value       = aws_instance.webserver.private_ip
}


#------------------------------------------------------------------------------
# Connectivity Outputs
#------------------------------------------------------------------------------
output "web_url" {
  description = "URL to access the web server"
  value       = "http://${aws_eip.ec2.public_ip}"
}

output "ec2_instance_connect_command" {
  description = "AWS CLI command to connect via EC2 Instance Connect"
  value       = "aws ec2-instance-connect ssh --instance-id ${aws_instance.webserver.id} --region ${data.aws_region.current.name}"
}



