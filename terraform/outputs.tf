output "bucket_name" {
  value = aws_s3_bucket.lab.id
}

output "instance_a_id" {
  value = aws_instance.a.id
}

output "instance_b_id" {
  value = aws_instance.b.id
}

output "az_a" {
  value = local.az_a
}

output "az_b" {
  value = local.az_b
}

output "ebs_volume_id" {
  value = aws_ebs_volume.data.id
}

output "restored_volume_id" {
  value = try(aws_ebs_volume.restored[0].id, "")
}

output "dashboard_url" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards:name=${var.project}"
}
