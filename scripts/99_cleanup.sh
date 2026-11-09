#!/usr/bin/env bash
# Paso final: destruir TODO (después de tomar las capturas) y borrar los snapshots creados fuera de Terraform.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
exec > >(tee "$ROOT/evidence/logs/99_cleanup.log") 2>&1

echo "== terraform destroy"
tf destroy -input=false -auto-approve

echo "== Snapshots del laboratorio (creados por scripts/03_az_failover.sh)"
for s in $(aws ec2 describe-snapshots --owner-ids self --filters "Name=tag:Project,Values=lab6-s3-vs-ebs" --query 'Snapshots[].SnapshotId' --output text); do
  echo "Eliminando $s"; aws ec2 delete-snapshot --snapshot-id "$s"
done

rm -f "$ROOT/terraform/restore.auto.tfvars" "$ROOT/terraform/resize.auto.tfvars" "$ROOT/terraform/tfplan"
echo "== Verificación: no deben quedar recursos con el tag Project=lab6-s3-vs-ebs"
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=lab6-s3-vs-ebs --query 'ResourceTagMappingList[].ResourceARN' --output text
