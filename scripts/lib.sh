#!/usr/bin/env bash
# Funciones comunes. Requisitos locales: terraform, aws cli v2 (con credenciales), jq, python3.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGION="${AWS_REGION:-sa-east-1}"
export AWS_REGION="$REGION" AWS_DEFAULT_REGION="$REGION" AWS_PAGER=""
mkdir -p "$ROOT/evidence/logs" "$ROOT/results"

tf()  { terraform -chdir="$ROOT/terraform" "$@"; }
out() { tf output -raw "$1"; }
ts()  { date +%s.%N; }
secs() { awk -v a="$1" -v b="$2" 'BEGIN{printf "%.1f", b-a}'; }
nodash() { echo "${1//-/}"; }

# Espera a que la instancia aparezca "Online" en SSM
wait_ssm() {
  local iid="$1" s=""
  for _ in $(seq 1 60); do
    s=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$iid" \
        --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)
    [ "$s" = "Online" ] && return 0
    sleep 10
  done
  echo "SSM no disponible para $iid" >&2
  return 1
}

# ssm_run <instance-id> <comando...> : ejecuta un comando como root y devuelve stdout/stderr
ssm_run() {
  local iid="$1"; shift
  local cmd="$*" cid st="Pending"
  cid=$(aws ssm send-command --instance-ids "$iid" --document-name AWS-RunShellScript \
        --parameters "$(jq -cn --arg c "$cmd" '{commands:[$c],executionTimeout:["3600"]}')" \
        --query Command.CommandId --output text)
  sleep 2
  for _ in $(seq 1 1440); do
    st=$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$iid" \
         --query Status --output text 2>/dev/null || echo Pending)
    case "$st" in Success|Failed|Cancelled|TimedOut) break ;; esac
    sleep 5
  done
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$iid" \
      --query StandardOutputContent --output text
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$iid" \
      --query StandardErrorContent --output text >&2
  [ "$st" = "Success" ]
}

wait_ready() {
  ssm_run "$1" 'for i in $(seq 1 120); do [ -f /opt/lab6/READY ] && echo READY && exit 0; sleep 5; done; echo NOT_READY; exit 1'
}
