# Laboratorio 6 - Amazon S3 vs Amazon EBS (Grupo 6)

Curso: Infraestructura como Código · Docente: Walter Leturia Rodriguez

Comparación práctica de **Amazon S3** (almacenamiento de objetos) y **Amazon EBS** (almacenamiento de bloques),
enfocada en el proyecto *Sistema de Reclamos por Mensajería*: **los adjuntos de un reclamo** (fotos y PDFs de evidencia).
Todo se despliega con **Terraform** (sin clics) y se mide con **la misma carga** en ambos servicios.

> Este repositorio es independiente del repositorio del proyecto, como pidió el docente.

## Qué responde cada prueba

| Prueba | Pregunta | Atributo de calidad / RNF del proyecto |
|---|---|---|
| T1 | ¿Cuánto tarda guardar y leer 1 000 reclamos JSON de 5 KB? | Rendimiento (RNF-08, p95 < 2 s) |
| T2 | ¿Qué throughput se logra con 20 adjuntos de 50 MB? | Rendimiento |
| T3 | ¿Qué pasa al subir la concurrencia (1, 10, 50 hilos)? | Escalabilidad (RNF-09, 6 000 concurrentes) |
| T4 | Si se cae la AZ a, ¿cómo accede la AZ b a los datos y en cuánto tiempo? | Disponibilidad y recuperabilidad (RNF-02, RNF-11: RTO 1 h) |
| T5 | ¿Cómo crece la capacidad? ¿Se puede reducir? | Escalabilidad / costo |
| T6 | Borrado accidental: ¿cómo y en cuánto se recupera? | Integridad y recuperabilidad (RPO) |
| T7 | Costo mensual con 100 GB, 1 TB y 10 TB | Costos |

## Diseño del experimento

Diagrama único en [`docs/diagrama.mmd`](docs/diagrama.mmd) (Mermaid; exportar a PNG en <https://mermaid.live>).

```
Carril A (S3):   EC2-A ─PutObject/GetObject─► Gateway Endpoint ─► S3 (regional, multi-AZ) ◄─ EC2-B (otra AZ)
Carril B (EBS):  EC2-A ─write+fsync/read────► EBS gp3 10 GiB (AZ a)   ✗ EC2-B no puede adjuntarlo (ZoneMismatch)
                                              └─snapshot─► restore en AZ b ─► EC2-B
```

- **S3 se usa en su rol natural:** repositorio de adjuntos accesible por API desde varios consumidores y varias AZ.
- **EBS se usa en su rol natural:** disco de UNA instancia, con sistema de archivos ext4.
- **EC2 es el complemento obligatorio de EBS** (un volumen no se usa solo). EC2-B es el segundo consumidor que expone la diferencia entre servicio regional y zonal.
- **Equidad:** mismos datos, mismo tipo de instancia, `fsync` en EBS, lecturas en frío en EBS (se descarta la caché de página), 3 corridas y mediana.
- **Sin clics:** VPC, subredes, endpoint, bucket, IAM, EC2, volumen, formateo/montaje (`user_data`), dashboard y restauración se declaran en `terraform/`.

## Requisitos locales

`terraform >= 1.6`, `aws cli v2` con credenciales válidas para `sa-east-1`, `jq`, `python3`. Las instancias se administran con **SSM** (no hace falta SSH ni llaves).

## Cómo ejecutarlo (en orden)

```bash
git clone <URL-DE-ESTE-REPO> && cd lab6-s3-vs-ebs
export AWS_REGION=sa-east-1

./scripts/01_deploy.sh          # terraform init/validate/plan/apply + verificación de S3 y del disco montado
./scripts/02_run_benchmark.sh   # T1-T3: benchmark S3 vs EBS (+ fio) y resumen en results/summary.md
./scripts/03_az_failover.sh     # T4: S3 desde otra AZ, ZoneMismatch, snapshot y restore (mide tiempos)
./scripts/04_resize_ebs.sh 20   # T5: ampliar 10 -> 20 GiB en caliente; intento de reducir (falla)
./scripts/05_recovery.sh        # T6: recuperación de un archivo borrado (S3 versionado vs snapshot EBS)
python3 scripts/06_cost_estimate.py --prices scripts/prices.json   # T7: costos (editar prices.json con sa-east-1)

# Cuando tengas todas las capturas:
./scripts/99_cleanup.sh         # terraform destroy + borra snapshots; verifica que no quede nada
```

Cada script guarda su salida en `evidence/logs/` (útil como evidencia). Las capturas de pantalla van en `evidence/capturas/`
(lista en [`docs/EVIDENCIAS.md`](docs/EVIDENCIAS.md)). La estructura del PDF está en [`docs/ESTRUCTURA_PDF.md`](docs/ESTRUCTURA_PDF.md).

Parámetros opcionales del benchmark: `RUNS=3 SMALL=1000 LARGE=20 LARGE_MB=50 THREADS=1,10,50 ./scripts/02_run_benchmark.sh`.

## Costo y tiempo estimados

Recursos pequeños (2 × t3.micro, un volumen de 10-20 GiB, unos GB en S3). El experimento completo toma 1-2 horas;
el costo debería ser de pocos dólares. **Verifícalo en la calculadora de AWS** y destruye todo al terminar.
El Gateway Endpoint de S3 no tiene costo. No hay NAT Gateway.

## Estructura

```
terraform/            IaC: network, s3, iam, compute (EBS+EC2), restore, monitoring, outputs, user_data
scripts/              benchmark.py, summarize.py, 01..05 + 99 (orquestación), 06_cost_estimate.py, lib.sh
docs/                 diagrama.mmd, EVIDENCIAS.md, ESTRUCTURA_PDF.md
results/              CSV del benchmark y summary.md (se llenan al ejecutar)
evidence/             logs de cada paso y carpeta de capturas
.github/workflows/    CI: fmt + validate (+ plan si se configura OIDC)
```

## Limitaciones (decláralas en el informe)

- Instancias `t3.micro` (burstable): su ancho de banda hacia EBS y hacia S3 también limita los resultados. Son medidas **orientativas**, no un benchmark de producción.
- Muestras pequeñas (3 corridas). Se reporta la mediana.
- Un volumen restaurado desde snapshot carga sus bloques de forma diferida desde S3: las primeras lecturas son más lentas (T4, paso 6).
- Los precios del script son de referencia (us-east-1); reemplázalos por los de sa-east-1 y anota la fecha.
- El estado de Terraform es local (laboratorio efímero). En un entorno de equipo se usaría backend remoto en S3.
- No asumas el resultado antes de medir: EBS suele ganar en latencia de archivos pequeños de un solo hilo, mientras que S3 suele ganar en concurrencia, disponibilidad entre AZ, operación y costo. Reporta lo que obtengas.
