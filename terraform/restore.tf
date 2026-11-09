# Prueba T4: recuperación en otra AZ a partir de un snapshot.
# Solo se crea cuando restore_snapshot_id tiene valor (lo escribe scripts/03_az_failover.sh).
resource "aws_ebs_volume" "restored" {
  count             = var.restore_snapshot_id == "" ? 0 : 1
  availability_zone = aws_subnet.b.availability_zone
  snapshot_id       = var.restore_snapshot_id
  type              = var.ebs_type
  iops              = var.ebs_iops
  throughput        = var.ebs_throughput
  encrypted         = true

  tags = { Name = "${var.project}-ebs-restored" }
}

resource "aws_volume_attachment" "restored" {
  count        = var.restore_snapshot_id == "" ? 0 : 1
  device_name  = "/dev/sdg"
  volume_id    = aws_ebs_volume.restored[0].id
  instance_id  = aws_instance.b.id
  force_detach = true
}
