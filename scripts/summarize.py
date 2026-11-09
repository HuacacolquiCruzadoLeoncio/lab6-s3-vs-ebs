#!/usr/bin/env python3
"""Resume los CSV de results/ en tablas Markdown listas para pegar en el PDF."""
import csv
import glob
import os
import statistics
import sys

root = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "results")
rows = []
for f in glob.glob(os.path.join(root, "**", "*.csv"), recursive=True):
    with open(f, newline="") as fh:
        rows += list(csv.DictReader(fh))
if not rows:
    sys.exit("No hay CSV en results/. Ejecuta scripts/02_run_benchmark.sh primero.")

ORDER = ["small_write", "small_read", "large_write", "large_read"]
groups = {}
for r in rows:
    groups.setdefault((r["label"], r["test"], int(r["threads"])), []).append(r)


def med(rs, key):
    return statistics.median(float(x[key]) for x in rs)


out = ["## Resultados por destino (mediana de las corridas)", "",
       "| Destino | Prueba | Hilos | ops/s | MB/s | p50 (ms) | p95 (ms) | Errores |",
       "|---|---|---:|---:|---:|---:|---:|---:|"]
for (label, test, th), rs in sorted(groups.items(), key=lambda k: (k[0][0], ORDER.index(k[0][1]), k[0][2])):
    out.append(f"| {label} | {test} | {th} | {med(rs,'ops_per_s'):.1f} | {med(rs,'mb_per_s'):.1f} | "
               f"{med(rs,'p50_ms'):.1f} | {med(rs,'p95_ms'):.1f} | {sum(int(x['errors']) for x in rs)} |")

labels = {k[0] for k in groups}
if {"ec2a-s3", "ec2a-ebs"} <= labels:
    out += ["", "## Comparación directa en EC2-A (S3 vs EBS)", "",
            "| Prueba | Hilos | S3 ops/s | EBS ops/s | S3 p95 (ms) | EBS p95 (ms) | Más rápido |",
            "|---|---:|---:|---:|---:|---:|---|"]
    keys = sorted({(k[1], k[2]) for k in groups}, key=lambda k: (ORDER.index(k[0]), k[1]))
    for test, th in keys:
        s, e = groups.get(("ec2a-s3", test, th)), groups.get(("ec2a-ebs", test, th))
        if not s or not e:
            continue
        so, eo = med(s, "ops_per_s"), med(e, "ops_per_s")
        ratio = so / eo if eo else 0
        win = f"S3 ({ratio:.1f}x)" if so >= eo else f"EBS ({1/ratio:.1f}x)" if ratio else "-"
        out.append(f"| {test} | {th} | {so:.1f} | {eo:.1f} | {med(s,'p95_ms'):.1f} | {med(e,'p95_ms'):.1f} | {win} |")

text = "\n".join(out)
print(text)
with open(os.path.join(root, "summary.md"), "w") as f:
    f.write(text + "\n")
print(f"\n(guardado en {os.path.join(root, 'summary.md')})")
