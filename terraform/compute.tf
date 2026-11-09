data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

# ===== SERVICIO 2: Amazon EBS (+ EC2 como complemento obligatorio) =====
resource "aws_ebs_volume" "data" {
  availability_zone = aws_subnet.a.availability_zone
  size              = var.ebs_size_gb
  type              = var.ebs_type
  iops              = var.ebs_iops
  throughput        = var.ebs_throughput
  encrypted         = true

  tags = { Name = "${var.project}-ebs-data" }
}
resource "aws_instance" "a" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.a.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  iam_instance_profile   = "LabInstanceProfile"

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
    ebs_volume_id = replace(aws_ebs_volume.data.id, "-", "")
    mount_point   = "/mnt/reclamos-ebs"
  })
  user_data_replace_on_change = true

  depends_on = [
    aws_s3_object.benchmark_py
  ]

  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Name = "${var.project}-ec2-a", Role = "benchmark-az-a" }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/sdf"
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.a.id
  force_detach = true
}

resource "aws_instance" "b" {
  ami                    = data.aws_ssm_parameter.ami.value
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.b.id
  vpc_security_group_ids = [aws_security_group.bench.id]
  iam_instance_profile   = "LabInstanceProfile"

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
    aws_s3_object.benchmark_py
  ]

  lifecycle {
    ignore_changes = [ami]
  }

  tags = { Name = "${var.project}-ec2-b", Role = "benchmark-az-b" }
}
