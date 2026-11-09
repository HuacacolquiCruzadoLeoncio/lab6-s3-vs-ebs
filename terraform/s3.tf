resource "random_id" "suffix" {
  byte_length = 4
}

# ===== SERVICIO 1: Amazon S3 =====
resource "aws_s3_bucket" "lab" {
  bucket        = "${var.project}-${random_id.suffix.hex}"
  force_destroy = true # laboratorio: permite destruir aunque tenga objetos y versiones
}

resource "aws_s3_bucket_public_access_block" "lab" {
  bucket                  = aws_s3_bucket.lab.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "lab" {
  bucket = aws_s3_bucket.lab.id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES-256). Se declara explícitamente para no confundirlo con SSE-KMS.
resource "aws_s3_bucket_server_side_encryption_configuration" "lab" {
  bucket = aws_s3_bucket.lab.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# El script de benchmark viaja por IaC: Terraform lo sube y las EC2 lo descargan al arrancar.
resource "aws_s3_object" "benchmark_py" {
  bucket = aws_s3_bucket.lab.id
  key    = "tools/benchmark.py"
  source = "${path.module}/../scripts/benchmark.py"
  etag   = filemd5("${path.module}/../scripts/benchmark.py")
}
