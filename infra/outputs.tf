output "api_public_ip" {
  description = "Use this to send the curl POST request"
  value       = aws_instance.api_vm.public_ip
}

output "caller_public_ip" {
  description = "SSH here to check Node.js worker logs"
  value       = aws_instance.caller_vm.public_ip
}

output "inference_public_ip" {
  description = "SSH here to check Python AI worker logs"
  value       = aws_instance.inference_vm.public_ip
}

output "api_internal_ip" {
  description = "The dynamic IP successfully injected into the .tpl files"
  value       = aws_instance.api_vm.private_ip
}
