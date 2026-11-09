#!/usr/bin/env bash
# Paso 4 (T5): escalar capacidad. EBS crece en línea pero NO se puede reducir. S3 no requiere nada.
# Uso: scripts/04_resize_ebs.sh [nuevo_tamano_gb]   (por defecto 20)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
exec > >(tee "$ROOT/evidence/logs/04_resize.log") 2>&1

NEW="${1:-20}"
A=$(out instance_a_id); VOL=$(out ebs_volume_id)
DEVCMD="DEV=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_$(nodash "$VOL")"

echo "### Antes"
ssm_run "$A" "$DEVCMD; lsblk -o NAME,SIZE,MOUNTPOINT | grep -E 'NAME|nvme1'; df -h /mnt/reclamos-ebs | tail -1"

echo; echo "### Intento de REDUCIR el volumen a 5 GiB (se espera error)"
set +e
aws ec2 modify-volume --volume-id "$VOL" --size 5
set -e

echo; echo "### Ampliar a ${NEW} GiB con Terraform (sin detener la instancia)"
echo "ebs_size_gb = $NEW" > "$ROOT/terraform/resize.auto.tfvars"
T0=$(ts)
tf apply -input=false -auto-approve
until s=$(aws ec2 describe-volumes-modifications --volume-ids "$VOL" --query 'VolumesModifications[0].ModificationState' --output text) && [[ "$s" == optimizing || "$s" == completed ]]; do
  echo "  estado de la modificación: $s"; sleep 5
done
T1=$(ts)
echo "Tiempo hasta que el volumen está ampliado: $(secs "$T0" "$T1") s"

echo; echo "### Extender el sistema de archivos ext4 en caliente"
ssm_run "$A" "$DEVCMD; resize2fs \$DEV; lsblk -o NAME,SIZE,MOUNTPOINT | grep -E 'NAME|nvme1'; df -h /mnt/reclamos-ebs | tail -1"
T2=$(ts)
echo "Tiempo total de ampliación (volumen + sistema de archivos): $(secs "$T0" "$T2") s, sin tiempo de inactividad."
