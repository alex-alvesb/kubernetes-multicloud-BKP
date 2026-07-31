output "state_bucket_name" {
  description = "Nome do bucket S3 usado como backend remoto do Terraform"
  value       = aws_s3_bucket.terraform_state.id
}