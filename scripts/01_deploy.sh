#!/usr/bin/env bash
# Paso 1: despliegue de TODA la infraestructura con Terraform (sin clics).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
exec > >(tee "$ROOT/evidence/logs/01_deploy.log") 2>&1

echo "== terraform init / fmt / validate"
tf init -input=false
tf fmt -check -recursive || { echo "(aviso) ejecuta: terraform -chdir=terraform fmt -recursive"; }
tf validate

echo "== terraform plan"
tf plan -input=false -out=tfplan

echo "== terraform apply"
T0=$(ts)
tf apply -input=false tfplan
T1=$(ts)
echo "Tiempo de terraform apply: $(secs "$T0" "$T1") s"

A=$(out instance_a_id); B=$(out instance_b_id)
echo "== Esperando a SSM y al arranque de las instancias"
wait_ssm "$A"; wait_ssm "$B"
wait_ready "$A"; wait_ready "$B"
T2=$(ts)
echo "Tiempo total hasta instancias listas: $(secs "$T0" "$T2") s"

echo "== Verificación del volumen EBS en EC2-A (evidencia: formateado y montado por user_data)"
ssm_run "$A" "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT; echo; df -hT /mnt/reclamos-ebs; echo; blkid | grep reclamos"

echo "== Verificación de S3"
BUCKET=$(out bucket_name)
aws s3api get-bucket-versioning --bucket "$BUCKET"
aws s3api get-bucket-encryption --bucket "$BUCKET" --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault'
aws s3api get-public-access-block --bucket "$BUCKET"

echo
echo "Listo. Bucket: $BUCKET | EC2-A: $A ($(out az_a)) | EC2-B: $B ($(out az_b))"
echo "Dashboard: $(out dashboard_url)"
