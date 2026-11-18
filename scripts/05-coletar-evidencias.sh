#!/usr/bin/env bash
# 05 - Coleta as evidências técnicas (saídas de comandos e logs) na pasta evidencias/.
# Uso: sudo ./scripts/05-coletar-evidencias.sh            (só coleta)
#      sudo ./scripts/05-coletar-evidencias.sh --com-teste (roda também o teste de falha)
set -uo pipefail
source "$(dirname "$0")/../lib/comum.sh"
exigir_root

DEST="$RAIZ/evidencias"
mkdir -p "$DEST"

salvar() {  # salvar arquivo "comando"
    local arquivo="$1"; shift
    { echo "\$ $*"; echo; bash -c "$*" 2>&1; } > "$DEST/$arquivo"
    log INFO "evidencias/$arquivo"
}

salvar 01-rede-dns.txt       "hostnamectl; echo; hostname -I; echo; grep safecity /etc/hosts; echo; resolvectl dns; echo; ufw status verbose"
salvar 02-servicos.txt       "systemctl status safecity-api safecity-monitor --no-pager"
salvar 03-api-health.txt     "curl -s -w '\nHTTP %{http_code}\n' http://localhost:$APP_PORTA/health; echo; curl -s http://localhost:$APP_PORTA/api/zonas | head -c 600"
salvar 04-dependencias.txt   "dotnet --info | head -20; echo; cat /etc/safecity/safecity.env; echo; ls -l $APP_DIR/app | head -15"

if [[ "${1:-}" == "--com-teste" ]]; then
    salvar 05-teste-falha.txt "bash $RAIZ/scripts/04-teste-falha.sh"
fi

salvar 06-monitor-log.txt    "tail -60 $LOG_DIR/monitor.log; echo; echo '--- ALERTAS ---'; grep ALERTA $LOG_DIR/monitor.log | tail -20"
salvar 07-auditoria-log.txt  "cat $LOG_DIR/auditoria.log"
salvar 08-auditd.txt         "ausearch -k safecity -i 2>/dev/null | tail -40"
salvar 09-journal.txt        "journalctl -t safecity -n 40 --no-pager; echo; journalctl -u safecity-api -n 20 --no-pager"

chown -R "${SUDO_USER:-root}:" "$DEST"
log INFO "Evidências salvas em $DEST"
