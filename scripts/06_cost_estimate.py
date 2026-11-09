#!/usr/bin/env python3
"""
Prueba T6 - modelo de costo mensual S3 vs EBS para los adjuntos del sistema de reclamos.

  python3 scripts/06_cost_estimate.py --prices scripts/prices.json

Supuestos (cámbialos y justifícalos en el PDF):
  - EBS cobra el tamaño APROVISIONADO: se deja holgura (por defecto 30 %) porque crece pero no se reduce.
  - EBS necesita al menos una EC2 encendida 24x7 (--ec2-count) y snapshots.
  - S3 cobra lo usado + peticiones.
"""
import argparse
import json
import os

ap = argparse.ArgumentParser()
ap.add_argument("--prices", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "prices.example.json"))
ap.add_argument("--sizes-gb", default="100,1000,10000")
ap.add_argument("--headroom", type=float, default=0.30, help="holgura de EBS (0.30 = 30 %)")
ap.add_argument("--ec2-count", type=int, default=1)
ap.add_argument("--snapshot-ratio", type=float, default=1.0, help="GB de snapshot por GB usado (incremental ~1.0-1.2)")
ap.add_argument("--puts-month", type=int, default=100_000, help="p. ej. 50 000 reclamos x 2 adjuntos")
ap.add_argument("--gets-month", type=int, default=500_000)
a = ap.parse_args()

p = json.load(open(a.prices))
print(f"Precios: {a.prices}\n{p.get('_nota', '')}\n")
print("| Datos (GB) | S3 almacenamiento | S3 peticiones | **S3 total** | EBS provisionado (GB) | EBS volumen | EBS snapshots | EC2 | **EBS total** | EBS / S3 |")
print("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
for gb in [int(x) for x in a.sizes_gb.split(",")]:
    s3_sto = gb * p["s3_gb_month"]
    s3_req = a.puts_month / 1000 * p["s3_put_per_1k"] + a.gets_month / 1000 * p["s3_get_per_1k"]
    s3 = s3_sto + s3_req
    prov = gb / (1 - a.headroom)
    ebs_vol = prov * p["ebs_gp3_gb_month"]
    ebs_snap = gb * a.snapshot_ratio * p["ebs_snapshot_gb_month"]
    ec2 = a.ec2_count * p["ec2_t3_micro_hour"] * 730
    ebs = ebs_vol + ebs_snap + ec2
    print(f"| {gb} | ${s3_sto:,.2f} | ${s3_req:,.2f} | **${s3:,.2f}** | {prov:,.0f} | ${ebs_vol:,.2f} | ${ebs_snap:,.2f} | ${ec2:,.2f} | **${ebs:,.2f}** | {ebs/s3:.1f}x |")
print("\nNota: EBS gp3 admite hasta 16 TiB por volumen; con 10 TB habría que vigilar ese tope.")
