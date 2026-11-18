#!/usr/bin/env bash
# 04 - Teste de falha: derruba e trava a API e o monitor e mostra a recuperação automática.
# Uso: sudo ./scripts/04-teste-falha.sh
set -uo pipefail
source "$(dirname "$0")/../lib/comum.sh"
exigir_root

pid() { systemctl show -p MainPID --value "$1"; }
saude() { curl -fs -m 3 "http://localhost:$APP_PORTA/health" || echo "SEM RESPOSTA"; }

esperar_api() {
    for i in $(seq 1 60); do
        if curl -fs -m 2 "http://localhost:$APP_PORTA/health" >/dev/null; then
            log INFO "API recuperada em ~$((i*2))s (PID $(pid safecity-api))"; return 0
        fi
        sleep 2
    done
    log ERRO "API NÃO se recuperou"; return 1
}

log INFO "----- Teste 1: processo da API morto (kill -9) -----"
log INFO "Antes: PID $(pid safecity-api), /health=$(saude)"
kill -9 "$(pid safecity-api)"
log INFO "Processo morto. /health=$(saude)"
esperar_api   # systemd (Restart=always) sobe de novo

log INFO "----- Teste 2: API travada (SIGSTOP, processo vivo mas sem responder) -----"
systemctl kill -s SIGSTOP safecity-api
log INFO "API congelada. /health=$(saude)  -> o monitor deve detectar e reiniciar"
esperar_api   # monitor.sh detecta 2 falhas e faz restart

log INFO "----- Teste 3: monitor morto (kill -9) -----"
antes=$(pid safecity-monitor)
kill -9 "$antes"; sleep 5
log INFO "Monitor: PID $antes -> $(pid safecity-monitor) ($(systemctl is-active safecity-monitor))"

log INFO "----- Teste 4: CPU no limite por 25s (alerta) -----"
for _ in $(seq "$(nproc)"); do timeout 25 sh -c 'while :; do :; done' & done
wait
grep ALERTA "$LOG_DIR/monitor.log" | tail -5

log INFO "Teste de falha concluído. Evidências em $LOG_DIR"
