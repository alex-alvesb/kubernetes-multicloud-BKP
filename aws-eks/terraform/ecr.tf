resource "aws_ecr_repository" "sample_app" {
  name                 = "kubernetes-multicloud-sample-app"
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "sample_app" {
  repository = aws_ecr_repository.sample_app.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Manter só as últimas 10 imagens"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}