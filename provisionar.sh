#!/usr/bin/env bash
# Provisiona o servidor SafeCity do zero: infraestrutura -> aplicação -> monitoramento.
# Uso: sudo ./provisionar.sh
set -euo pipefail
cd "$(dirname "$0")"
source lib/comum.sh
exigir_root

log INFO "===== Provisionamento SafeCity iniciado ====="
bash scripts/01-infra.sh
bash scripts/02-app.sh
bash scripts/03-instalar-monitor.sh
log INFO "===== Provisionamento concluído ====="
log INFO "API:     http://$DOMINIO_LOCAL:$APP_PORTA/swagger"
log INFO "Saúde:   curl http://$DOMINIO_LOCAL:$APP_PORTA/health"
log INFO "Logs:    $LOG_DIR"
