#!/usr/bin/env bash
# Paso 3 (T4): disponibilidad / "se cae la AZ a". Qué pasa en la AZ b con S3 y con EBS.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
exec > >(tee "$ROOT/evidence/logs/03_az_failover.log") 2>&1

BUCKET=$(out bucket_name); A=$(out instance_a_id); B=$(out instance_b_id); VOL=$(out ebs_volume_id)
RTO_OBJETIVO=3600   # RNF-11 del informe del proyecto: RTO <= 1 hora

echo "### 1) S3: EC2-B (otra AZ) lee los datos escritos desde EC2-A, sin hacer nada"
ssm_run "$B" "s=\$(date +%s.%N); aws s3 ls s3://$BUCKET/bench/a/small/r1/t1/ --region $REGION | head -3; aws s3 cp s3://$BUCKET/bench/a/small/r1/t1/00000.json /tmp/x.json --region $REGION --only-show-errors; e=\$(date +%s.%N); ls -l /tmp/x.json; awk -v s=\$s -v e=\$e 'BEGIN{printf \"Tiempo hasta leer el primer objeto: %.2f s\n\", e-s}'"

echo; echo "### 2) EBS: intentar adjuntar el volumen original (AZ a) a EC2-B (AZ b)  -> se espera ZoneMismatch"
set +e
aws ec2 attach-volume --volume-id "$VOL" --instance-id "$B" --device /dev/sdh
set -e

echo; echo "### 3) EBS: estado del volumen en EC2-A y snapshot"
ssm_run "$A" "sync; df -h /mnt/reclamos-ebs | tail -1; echo archivos_en_A=\$(find /mnt/reclamos-ebs/bench -type f | wc -l)"
T0=$(ts)
SNAP=$(aws ec2 create-snapshot --volume-id "$VOL" --description "lab6 failover test" \
       --tag-specifications "ResourceType=snapshot,Tags=[{Key=Project,Value=lab6-s3-vs-ebs}]" \
       --query SnapshotId --output text)
echo "Snapshot: $SNAP"
until [ "$(aws ec2 describe-snapshots --snapshot-ids "$SNAP" --query 'Snapshots[0].State' --output text)" = "completed" ]; do
  echo "  progreso: $(aws ec2 describe-snapshots --snapshot-ids "$SNAP" --query 'Snapshots[0].Progress' --output text)"
  sleep 10
done
T1=$(ts)
echo "Tiempo de snapshot: $(secs "$T0" "$T1") s"

echo; echo "### 4) Restaurar el snapshot en la AZ b y adjuntarlo a EC2-B (con Terraform)"
echo "restore_snapshot_id = \"$SNAP\"" > "$ROOT/terraform/restore.auto.tfvars"
tf apply -input=false -auto-approve
T2=$(ts)
echo "Tiempo de restore + attach (terraform apply): $(secs "$T1" "$T2") s"
RV=$(out restored_volume_id)

echo; echo "### 5) Montar en EC2-B y verificar datos"
ssm_run "$B" "DEV=/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_$(nodash "$RV"); for i in \$(seq 1 60); do [ -e \$DEV ] && break; sleep 5; done; mountpoint -q /mnt/reclamos-restored || mount \$DEV /mnt/reclamos-restored; df -h /mnt/reclamos-restored | tail -1; echo archivos_en_B=\$(find /mnt/reclamos-restored/bench -type f | wc -l)"
T3=$(ts)
echo "Tiempo de montaje + verificación: $(secs "$T2" "$T3") s"

echo; echo "### 6) Lectura en frío del volumen restaurado (los bloques se cargan desde S3 al primer acceso)"
ssm_run "$B" "s=\$(date +%s.%N); find /mnt/reclamos-restored/bench -type f | head -300 | xargs cat > /dev/null; e=\$(date +%s.%N); awk -v s=\$s -v e=\$e 'BEGIN{printf \"Leer 300 archivos del volumen restaurado: %.2f s\n\", e-s}'"

TOTAL=$(secs "$T0" "$T3")
{
  echo "=========== RESUMEN T4 (tiempo de recuperación) ==========="
  echo "S3  : EC2-B lee de inmediato (sin pasos de recuperación)."
  echo "EBS : snapshot $(secs "$T0" "$T1") s + restore/attach $(secs "$T1" "$T2") s + montaje $(secs "$T2" "$T3") s = ${TOTAL} s"
  echo "RTO objetivo del proyecto (RNF-11): ${RTO_OBJETIVO} s"
  awk -v t="$TOTAL" -v o="$RTO_OBJETIVO" 'BEGIN{ if (t<=o) print "Resultado: cumple el RTO con este volumen, pero con pasos y orquestación manual/automatizada."; else print "Resultado: NO cumple el RTO." }'
  echo "Nota: el snapshot refleja el instante en que se tomó (RPO = tiempo desde el último snapshot)."
} | tee "$ROOT/evidence/logs/03_resumen_rto.txt"
