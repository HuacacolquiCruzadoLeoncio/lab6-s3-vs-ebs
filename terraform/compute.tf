data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

# ===== SERVICIO 2: Amazon EBS (+ EC2 como complemento obligatorio) =====
# El volumen es ZONAL: se crea en la misma AZ que EC2-A.
resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.a.availability_zone
  size              = var.ebs_size_gb
  type              = var.ebs_type
  iops              = var.ebs_iops
  throughput        = var.ebs_throughput
  encrypted         = true # clave administrada aws/ebs

  tags = { Name = "${var.project}-ebs-data" }
}

# EC2-A (AZ a): ejecuta la carga contra S3 y contra el volumen EBS.
resource "aws_instance" "a" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.a.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_tokens   = "required" # IMDSv2
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    bucket        = aws_s3_bucket.lab.id
    region        = var.region
    ebs_volume_id = replace(aws_ebs_volume.data.id, "-", "")
    mount_point   = "/mnt/reclamos-ebs"
  })
  user_data_replace_on_change = true

  depends_on = [
    aws_s3_object.benchmark_py,
    aws_iam_role_policy.s3,
    aws_iam_role_policy_attachment.ssm,
  ]

  lifecycle {
    ignore_changes = [ami] # evita reemplazos cuando AWS publica una AMI nueva
  }

  tags = { Name = "${var.project}-ec2-a", Role = "benchmark-az-a" }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/sdf" # en Nitro aparece como /dev/nvme1n1
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.a.id
  force_detach = true
}

# EC2-B (AZ b): segundo consumidor. Lee S3 sin problema; NO puede adjuntar el volumen de la AZ a.
resource "aws_instance" "b" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.b.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = 8
    encrypted   = true
  }

  user_data = templatefile("${path.module}/templates/user_data.sh.tpl", {
    bucket        = aws_s3_bucket.lab.id
    region        = var.region
    ebs_volume_id = ""
    mount_point   = "/mnt/reclamos-restored"
  })
  user_data_replace_on_change = true

  depends_on = [
    aws_s3_object.benchmark_py,
    aws_iam_role_policy.s3,
    aws_iam_role_policy_attachment.ssm,
  ]

  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Name = "${var.project}-ec2-b", Role = "benchmark-az-b" }
}
