#!/usr/bin/env python3
"""
Benchmark S3 vs EBS - Laboratorio 6 (Grupo 6)

Ejecuta LA MISMA carga de trabajo contra un destino (S3 o un volumen EBS montado):
  small_write / small_read : N reclamos JSON pequeños (por defecto 1000 x 5 KB)
  large_write / large_read : M adjuntos grandes (por defecto 20 x 50 MB)

Equidad de la prueba:
  - EBS: cada escritura termina con fsync (S3 confirma recién cuando el objeto es durable).
  - EBS: antes de cada lectura se descarta la página de caché (posix_fadvise DONTNEED),
    para no medir la RAM de la instancia.
  - Mismo tamaño de datos, mismo número de hilos, mismo tipo de instancia.

Uso:
  python3 benchmark.py --target s3  --bucket MI_BUCKET --prefix bench/a --label ec2a-s3
  python3 benchmark.py --target ebs --path /mnt/reclamos-ebs/bench     --label ec2a-ebs
"""
import argparse
import csv
import datetime
import json
import os
import shutil
import socket
import statistics
import sys
import time
from concurrent.futures import ThreadPoolExecutor

CSV_FIELDS = ["label", "target", "host", "run", "test", "threads", "ops", "errors", "bytes",
              "wall_s", "ops_per_s", "mb_per_s", "mean_ms", "p50_ms", "p95_ms", "p99_ms"]


# ---------------------------------------------------------------- datos
def claim_payload(i, size):
    """Reclamo JSON de tamaño aproximado `size` bytes."""
    base = {"codigo": f"REC-2026-{i:06d}", "ciudadano": f"DNI{70000000 + i}",
            "tipo": "SERVICIO_DEFICIENTE", "estado": "REGISTRADO",
            "fecha": "2026-11-08T08:00:00Z", "descripcion": ""}
    pad = max(0, size - len(json.dumps(base)))
    base["descripcion"] = "x" * pad
    return json.dumps(base).encode()


# ---------------------------------------------------------------- destinos
class S3Backend:
    name = "s3"

    def __init__(self, bucket, prefix, region, pool):
        import boto3
        from botocore.config import Config
        self.bucket = bucket
        self.prefix = prefix.strip("/")
        self.client = boto3.client(
            "s3", region_name=region,
            config=Config(max_pool_connections=max(pool, 10),
                          retries={"max_attempts": 5, "mode": "standard"}))

    def _key(self, rel):
        return f"{self.prefix}/{rel}"

    def write(self, rel, data):
        self.client.put_object(Bucket=self.bucket, Key=self._key(rel), Body=data)

    def read(self, rel):
        body = self.client.get_object(Bucket=self.bucket, Key=self._key(rel))["Body"]
        n = 0
        for chunk in body.iter_chunks(8 * 1024 * 1024):
            n += len(chunk)
        return n

    def delete(self, rel):
        self.client.delete_object(Bucket=self.bucket, Key=self._key(rel))

    def cleanup(self):
        pag = self.client.get_paginator("list_objects_v2")
        for page in pag.paginate(Bucket=self.bucket, Prefix=self.prefix + "/"):
            for obj in page.get("Contents", []):
                self.client.delete_object(Bucket=self.bucket, Key=obj["Key"])


class EbsBackend:
    name = "ebs"

    def __init__(self, path):
        self.root = path
        os.makedirs(self.root, exist_ok=True)

    def _p(self, rel):
        return os.path.join(self.root, rel)

    def write(self, rel, data):
        p = self._p(rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb") as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())  # durabilidad comparable con S3

    def read(self, rel):
        fd = os.open(self._p(rel), os.O_RDONLY)
        try:
            try:
                os.posix_fadvise(fd, 0, 0, os.POSIX_FADV_DONTNEED)  # lectura "en frío"
            except (AttributeError, OSError):
                pass
            n = 0
            while True:
                chunk = os.read(fd, 8 * 1024 * 1024)
                if not chunk:
                    break
                n += len(chunk)
            return n
        finally:
            os.close(fd)

    def delete(self, rel):
        try:
            os.remove(self._p(rel))
        except FileNotFoundError:
            pass

    def cleanup(self):
        shutil.rmtree(self.root, ignore_errors=True)


def check_ebs_path(path, allow_root_fs):
    """Evita medir por error el disco raíz cuando el volumen EBS no está montado."""
    probe = os.path.abspath(path)
    while not os.path.exists(probe):
        probe = os.path.dirname(probe)
    if os.stat(probe).st_dev == os.stat("/").st_dev and not allow_root_fs:
        sys.exit(f"ERROR: {path} está en el disco raíz, no en el volumen EBS de datos. "
                 f"¿Está montado? (usa --allow-root-fs solo para pruebas locales)")


# ---------------------------------------------------------------- medición
def timed(fn, *args):
    t = time.perf_counter()
    try:
        fn(*args)
        return time.perf_counter() - t, None
    except Exception as exc:  # noqa: BLE001 - se contabiliza como error de la prueba
        return time.perf_counter() - t, repr(exc)


def pct(sorted_vals, p):
    if not sorted_vals:
        return 0.0
    idx = min(len(sorted_vals) - 1, int(round(p / 100 * (len(sorted_vals) - 1))))
    return sorted_vals[idx]


def run_phase(fn, items, threads, total_bytes):
    t0 = time.perf_counter()
    if threads <= 1:
        results = [timed(fn, *it) for it in items]
    else:
        with ThreadPoolExecutor(max_workers=threads) as ex:
            results = list(ex.map(lambda it: timed(fn, *it), items))
    wall = time.perf_counter() - t0
    ok = sorted(r[0] * 1000 for r in results if r[1] is None)
    errors = [r[1] for r in results if r[1] is not None]
    if errors:
        print(f"   ! {len(errors)} errores, ejemplo: {errors[0]}", file=sys.stderr)
    return {
        "ops": len(ok), "errors": len(errors), "bytes": total_bytes, "wall_s": round(wall, 3),
        "ops_per_s": round(len(ok) / wall, 2) if wall else 0,
        "mb_per_s": round(total_bytes / 1e6 / wall, 2) if wall else 0,
        "mean_ms": round(statistics.mean(ok), 2) if ok else 0,
        "p50_ms": round(pct(ok, 50), 2), "p95_ms": round(pct(ok, 95), 2),
        "p99_ms": round(pct(ok, 99), 2),
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--target", choices=["s3", "ebs"], required=True)
    ap.add_argument("--bucket")
    ap.add_argument("--prefix", default="bench")
    ap.add_argument("--path", help="directorio dentro del volumen EBS montado")
    ap.add_argument("--region", default=os.environ.get("AWS_REGION", "sa-east-1"))
    ap.add_argument("--label", required=True, help="ej. ec2a-s3, ec2a-ebs, ec2b-s3")
    ap.add_argument("--runs", type=int, default=3)
    ap.add_argument("--small-count", type=int, default=1000)
    ap.add_argument("--small-size", type=int, default=5120, help="bytes por reclamo JSON")
    ap.add_argument("--large-count", type=int, default=20)
    ap.add_argument("--large-size-mb", type=int, default=50)
    ap.add_argument("--threads", default="1,10,50", help="niveles de concurrencia para archivos pequeños")
    ap.add_argument("--large-threads", type=int, default=1)
    ap.add_argument("--out", default="./results")
    ap.add_argument("--keep-large", action="store_true", help="no borrar adjuntos grandes entre corridas")
    ap.add_argument("--cleanup", action="store_true", help="borrar todo lo creado al terminar")
    ap.add_argument("--allow-root-fs", action="store_true")
    args = ap.parse_args()

    levels = [int(x) for x in args.threads.split(",")]
    pool = max(levels + [args.large_threads])

    if args.target == "s3":
        if not args.bucket:
            sys.exit("--bucket es obligatorio con --target s3")
        be = S3Backend(args.bucket, args.prefix, args.region, pool)
    else:
        if not args.path:
            sys.exit("--path es obligatorio con --target ebs")
        check_ebs_path(args.path, args.allow_root_fs)
        be = EbsBackend(args.path)

    small = [claim_payload(i, args.small_size) for i in range(args.small_count)]
    small_bytes = sum(len(s) for s in small)
    large_buf = os.urandom(args.large_size_mb * 1024 * 1024)
    large_bytes = len(large_buf) * args.large_count

    os.makedirs(args.out, exist_ok=True)
    host = socket.gethostname()
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    csv_path = os.path.join(args.out, f"{args.label}_{stamp}.csv")
    meta = {"label": args.label, "target": args.target, "host": host, "start": stamp,
            "args": vars(args), "python": sys.version.split()[0]}
    try:
        import boto3
        meta["boto3"] = boto3.__version__
    except ImportError:
        pass
    with open(os.path.join(args.out, f"{args.label}_{stamp}.json"), "w") as f:
        json.dump(meta, f, indent=2)

    rows = []
    print(f"== {args.label} ({args.target}) host={host} runs={args.runs} "
          f"small={args.small_count}x{args.small_size}B large={args.large_count}x{args.large_size_mb}MB threads={levels}")

    for run in range(1, args.runs + 1):
        last = run == args.runs

        def record(test, threads, stats):
            row = {"label": args.label, "target": args.target, "host": host, "run": run,
                   "test": test, "threads": threads, **stats}
            rows.append(row)
            print(f"  run{run} {test:<12} hilos={threads:<3} {stats['ops_per_s']:>9} ops/s "
                  f"{stats['mb_per_s']:>8} MB/s  p50={stats['p50_ms']}ms p95={stats['p95_ms']}ms "
                  f"err={stats['errors']}")

        for th in levels:
            keys = [f"small/r{run}/t{th}/{i:05d}.json" for i in range(args.small_count)]
            record("small_write", th, run_phase(be.write, list(zip(keys, small)), th, small_bytes))
            record("small_read", th, run_phase(be.read, [(k,) for k in keys], th, small_bytes))

        lkeys = [f"large/r{run}/f{i:03d}.bin" for i in range(args.large_count)]
        record("large_write", args.large_threads,
               run_phase(be.write, [(k, large_buf) for k in lkeys], args.large_threads, large_bytes))
        record("large_read", args.large_threads,
               run_phase(be.read, [(k,) for k in lkeys], args.large_threads, large_bytes))
        if not (last or args.keep_large):  # deja la última corrida como dataset para T4/T6
            for k in lkeys:
                be.delete(k)

    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=CSV_FIELDS)
        w.writeheader()
        w.writerows(rows)

    print("\n== Mediana de las corridas")
    groups = {}
    for r in rows:
        groups.setdefault((r["test"], r["threads"]), []).append(r)
    for (test, th), rs in groups.items():
        print(f"  {test:<12} hilos={th:<3} {statistics.median(x['ops_per_s'] for x in rs):>9.1f} ops/s "
              f"{statistics.median(x['mb_per_s'] for x in rs):>8.1f} MB/s "
              f"p50={statistics.median(x['p50_ms'] for x in rs):.1f}ms "
              f"p95={statistics.median(x['p95_ms'] for x in rs):.1f}ms")
    print(f"\nCSV: {csv_path}")

    if args.cleanup:
        be.cleanup()
        print("Datos de prueba eliminados.")


if __name__ == "__main__":
    main()
