variable "region" {
  description = "Región de AWS (la misma que usa el proyecto de reclamos)."
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Prefijo para nombres y tag Project. Debe ser minúsculas (se usa en el nombre del bucket)."
  type        = string
  default     = "lab6-s3-vs-ebs"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_a_cidr" {
  description = "Subred en la primera AZ (us-east-2a)."
  type        = string
  default     = "10.0.1.0/24"
}

variable "subnet_b_cidr" {
  description = "Subred en la segunda AZ (us-east-2b)."
  type        = string
  default     = "10.0.2.0/24"
}

variable "instance_type" {
  description = "Tipo de instancia. Se declara en el informe porque limita el ancho de banda hacia EBS y S3."
  type        = string
  default     = "t3.micro"
}

variable "ami_ssm_parameter" {
  description = "Parámetro público de SSM con la AMI (Amazon Linux 2023)."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "ebs_size_gb" {
  description = "Tamaño del volumen EBS (GiB). La prueba T5 lo sube de 10 a 20."
  type        = number
  default     = 10
}

variable "ebs_type" {
  description = "Tipo de volumen. gp3 permite fijar IOPS y throughput."
  type        = string
  default     = "gp3"
}

variable "ebs_iops" {
  description = "IOPS aprovisionadas (gp3: base 3000)."
  type        = number
  default     = 3000
}

variable "ebs_throughput" {
  description = "Throughput en MB/s (gp3: base 125)."
  type        = number
  default     = 125
}

variable "restore_snapshot_id" {
  description = "Si no está vacío, crea en la AZ B un volumen desde este snapshot y lo adjunta a EC2-B (prueba T4). Lo escribe scripts/03_az_failover.sh."
  type        = string
  default     = ""
}
