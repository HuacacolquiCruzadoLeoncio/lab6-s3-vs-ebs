#!/usr/bin/env bash
# Paso 5 (T6): borrado accidental de un reclamo. Cómo se recupera con S3 (versionado) y con EBS (snapshot).
# Requiere haber ejecutado antes 03_az_failover.sh (necesita el volumen restaurado montado en EC2-B).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
exec > >(tee "$ROOT/evidence/logs/05_recovery.log") 2>&1

BUCKET=$(out bucket_name); A=$(out instance_a_id); B=$(out instance_b_id)

echo "################ S3: borrar y recuperar con versionado"
KEY=$(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix bench/a/small/ --max-items 1 --query 'Contents[0].Key' --output text)
echo "Objeto: $KEY"
T0=$(ts)
aws s3 rm "s3://$BUCKET/$KEY"
echo "-- tras borrar, GET debe fallar (NoSuchKey):"
set +e; aws s3api head-object --bucket "$BUCKET" --key "$KEY"; set -e
MARK=$(aws s3api list-object-versions --bucket "$BUCKET" --prefix "$KEY" --query 'DeleteMarkers[?IsLatest==`true`].VersionId | [0]' --output text)
echo "-- delete marker: $MARK (se elimina para recuperar el objeto)"
aws s3api delete-object --bucket "$BUCKET" --key "$KEY" --version-id "$MARK"
aws s3api head-object --bucket "$BUCKET" --key "$KEY" --query '{Tamano:ContentLength,Version:VersionId}'
T1=$(ts)
echo "Tiempo de recuperación en S3: $(secs "$T0" "$T1") s (RPO ~ 0: versiones previas)"

echo; echo "################ EBS: borrar un archivo en EC2-A y recuperarlo desde el snapshot restaurado en EC2-B"
F=$(ssm_run "$A" "find /mnt/reclamos-ebs/bench -type f -name '*.json' | head -1" | tr -d '\r\n')
REL="${F#/mnt/reclamos-ebs/}"
echo "Archivo: $F"
T2=$(ts)
ssm_run "$A" "rm -f '$F'; ls -l '$F' 2>&1 | head -1"
ssm_run "$B" "ls -l '/mnt/reclamos-restored/$REL' && aws s3 cp '/mnt/reclamos-restored/$REL' 's3://$BUCKET/recovery/restored.json' --region $REGION --only-show-errors"
ssm_run "$A" "aws s3 cp 's3://$BUCKET/recovery/restored.json' '$F' --region $REGION --only-show-errors && ls -l '$F'"
T3=$(ts)
echo "Tiempo de recuperación en EBS (con el snapshot ya restaurado): $(secs "$T2" "$T3") s"
echo "Nota: en EBS solo se recupera lo que existía al tomar el snapshot (RPO = tiempo desde el último snapshot)."
