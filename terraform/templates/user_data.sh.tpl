#!/bin/bash
# Lab 6 - preparación de la instancia. Todo queda registrado en /var/log/lab6-userdata.log
set -uxo pipefail
exec > >(tee /var/log/lab6-userdata.log) 2>&1

dnf install -y python3-pip jq
dnf install -y fio || echo "fio no disponible: se omite la prueba de IOPS"
pip3 install --quiet boto3

mkdir -p /opt/lab6/results

# Descargar el benchmark (reintentos por la propagación de IAM)
for i in $(seq 1 20); do
  aws s3 cp s3://${bucket}/tools/benchmark.py /opt/lab6/benchmark.py --region ${region} && break
  sleep 6
done

%{ if ebs_volume_id != "" ~}
# EC2-A: esperar el volumen EBS, formatearlo (solo si está vacío) y montarlo
DEV=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${ebs_volume_id}
for i in $(seq 1 90); do
  [ -e "$DEV" ] && break
  sleep 5
done

if [ -e "$DEV" ]; then
  blkid "$DEV" || mkfs.ext4 -L reclamos-ebs "$DEV"
  mkdir -p ${mount_point}
  mount "$DEV" ${mount_point}
  grep -q ${mount_point} /etc/fstab || echo "$DEV ${mount_point} ext4 defaults,nofail 0 2" >> /etc/fstab
  chown ec2-user:ec2-user ${mount_point}
fi
%{ else ~}
# EC2-B: punto de montaje para el volumen restaurado desde snapshot (prueba T4)
mkdir -p ${mount_point}
chown ec2-user:ec2-user ${mount_point}
%{ endif ~}

chown -R ec2-user:ec2-user /opt/lab6
touch /opt/lab6/READY
