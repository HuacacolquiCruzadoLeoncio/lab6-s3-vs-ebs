# Dashboard de CloudWatch: evidencia visual de la carga sobre EBS y de la red de las EC2.
resource "aws_cloudwatch_dashboard" "lab" {
  dashboard_name = var.project

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "EBS - operaciones por minuto (volumen de EC2-A)"
          region = var.region, stat = "Sum", period = 60
          metrics = [
            ["AWS/EBS", "VolumeReadOps", "VolumeId", aws_ebs_volume.data.id],
            ["AWS/EBS", "VolumeWriteOps", "VolumeId", aws_ebs_volume.data.id],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "EBS - bytes por minuto"
          region = var.region, stat = "Sum", period = 60
          metrics = [
            ["AWS/EBS", "VolumeReadBytes", "VolumeId", aws_ebs_volume.data.id],
            ["AWS/EBS", "VolumeWriteBytes", "VolumeId", aws_ebs_volume.data.id],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 24, height = 6
        properties = {
          title  = "EC2 - NetworkOut (tráfico hacia S3)"
          region = var.region, stat = "Sum", period = 60
          metrics = [
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.a.id],
            ["AWS/EC2", "NetworkOut", "InstanceId", aws_instance.b.id],
          ]
        }
      },
    ]
  })
}
