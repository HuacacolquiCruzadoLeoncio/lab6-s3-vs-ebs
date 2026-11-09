# Lista de evidencias para el PDF

Toma capturas legibles (con fecha/hora visible si es posible). Cada ítem indica qué demuestra.
Los logs de texto ya se guardan en `evidence/logs/`; las capturas van en `evidence/capturas/`.

| # | Captura | Demuestra |
|---|---|---|
| 1 | `terraform plan` (resumen "Plan: N to add") | Despliegue por IaC |
| 2 | `terraform apply` terminado + tiempo | Provisionado sin clics |
| 3 | Consola: VPC, 2 subredes (1a y 1b) y Gateway Endpoint S3 | Red y complemento de S3 |
| 4 | Consola: bucket S3 con versionado, SSE y bloqueo de acceso público | Servicio 1 configurado |
| 5 | Consola: volumen EBS gp3 10 GiB (AZ a), cifrado, adjunto a EC2-A | Servicio 2 configurado |
| 6 | EC2-A y EC2-B en AZ distintas (columna Zona de disponibilidad) | Complemento de EBS y 2.º consumidor |
| 7 | Salida de `lsblk` / `df -hT` / `blkid` en EC2-A (log de 01_deploy) | Volumen formateado y montado por `user_data` |
| 8 | Salida de 02_run_benchmark: S3 desde EC2-A | T1-T3 en S3 |
| 9 | Salida de 02_run_benchmark: EBS en EC2-A | T1-T3 en EBS |
| 10 | Salida de 02_run_benchmark: S3 desde EC2-B (otra AZ) | S3 accesible multi-AZ |
| 11 | Salida de `fio` (IOPS) | Tope de IOPS del volumen |
| 12 | `results/summary.md` | Tabla comparativa final |
| 13 | CloudWatch: dashboard (ops/bytes de EBS y NetworkOut) | Carga observada |
| 14 | 03: lectura de S3 desde EC2-B | S3 responde sin pasos extra |
| 15 | 03: error `InvalidVolume.ZoneMismatch` | EBS es zonal |
| 16 | 03: snapshot completado + tiempos + montaje en EC2-B + resumen RTO | Recuperación en otra AZ |
| 17 | 04: error al reducir + ampliación 10→20 GiB + `df -h` | Escalado de EBS (sin reducción) |
| 18 | 05: delete marker y recuperación en S3; archivo borrado y restaurado en EBS | Integridad / RPO |
| 19 | Salida de `06_cost_estimate.py` + captura de la calculadora de AWS | Costos |
| 20 | `terraform destroy` + verificación de que no quedan recursos | Limpieza |

Consejo: en la tabla de resultados del PDF incluye siempre el tipo de instancia, el número de corridas y la fecha.
