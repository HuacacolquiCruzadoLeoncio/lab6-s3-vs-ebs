#!/usr/bin/env bash
# Paso 2 (T1-T3): la MISMA carga contra S3 y contra EBS, y S3 también desde la otra AZ.
# Variables opcionales: RUNS SMALL LARGE LARGE_MB THREADS
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
exec > >(tee "$ROOT/evidence/logs/02_benchmark.log") 2>&1

BUCKET=$(out bucket_name); A=$(out instance_a_id); B=$(out instance_b_id)
RUNS="${RUNS:-3}"; SMALL="${SMALL:-1000}"; LARGE="${LARGE:-20}"; LARGE_MB="${LARGE_MB:-50}"; THREADS="${THREADS:-1,10,50}"
BENCH="python3 /opt/lab6/benchmark.py --runs $RUNS --small-count $SMALL --large-count $LARGE --large-size-mb $LARGE_MB --threads $THREADS --out /opt/lab6/results"

echo "################ Parámetros: runs=$RUNS small=$SMALL x 5KB large=$LARGE x ${LARGE_MB}MB hilos=$THREADS"
echo "################ EC2-A -> S3"
ssm_run "$A" "$BENCH --target s3 --bucket $BUCKET --prefix bench/a --label ec2a-s3 --region $REGION"
echo "################ EC2-A -> EBS (volumen local montado)"
ssm_run "$A" "$BENCH --target ebs --path /mnt/reclamos-ebs/bench --label ec2a-ebs"
echo "################ EC2-B (otra AZ) -> S3"
ssm_run "$B" "$BENCH --target s3 --bucket $BUCKET --prefix bench/b --label ec2b-s3 --region $REGION"

echo "################ fio sobre EBS: 4 KiB aleatorio 70/30, 30 s (muestra el tope de IOPS del volumen)"
ssm_run "$A" "fio --name=ebs-randrw --directory=/mnt/reclamos-ebs --size=1G --bs=4k --rw=randrw --rwmixread=70 --iodepth=32 --ioengine=libaio --direct=1 --runtime=30 --time_based --group_reporting | grep -E 'IOPS=|bw=' ; rm -f /mnt/reclamos-ebs/ebs-randrw*"

echo "################ Recolectando resultados"
ssm_run "$A" "aws s3 cp /opt/lab6/results s3://$BUCKET/results/ec2-a/ --recursive --region $REGION --only-show-errors"
ssm_run "$B" "aws s3 cp /opt/lab6/results s3://$BUCKET/results/ec2-b/ --recursive --region $REGION --only-show-errors"
aws s3 sync "s3://$BUCKET/results" "$ROOT/results" --only-show-errors
python3 "$ROOT/scripts/summarize.py"
