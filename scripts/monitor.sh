#!/usr/bin/env bash
# Monitor contínuo: CPU, memória, disco e saúde da API.
# Gera ALERTA no log quando passa do limite e reinicia a API se ela parar de responder.
# Roda como serviço: safecity-monitor.service
source "$(dirname "$0")/../lib/comum.sh"

uso_cpu() {
    # Lê /proc/stat duas vezes (1 s) e calcula a % de tempo ocupado.
    local a b
    read -r _ a1 a2 a3 a4 a5 a6 a7 _ < /proc/stat
    sleep 1
    read -r _ b1 b2 b3 b4 b5 b6 b7 _ < /proc/stat
    a=$((a1+a2+a3+a4+a5+a6+a7)); b=$((b1+b2+b3+b4+b5+b6+b7))
    echo $(( 100 * ( (b-a) - (b4-a4) ) / (b-a) ))
}
uso_memoria() { free | awk '/^Mem:/ {printf "%d", ($2-$7)*100/$2}'; }
uso_disco()   { df --output=pcent / | tail -1 | tr -dc '0-9'; }

verificar() {
    local nome="$1" valor="$2" limite="$3"
    if (( valor >= limite )); then
        log ALERTA "$nome em ${valor}% (limite ${limite}%)"
    fi
}

log INFO "Monitor iniciado (intervalo ${INTERVALO_SEGUNDOS}s)"
falhas_api=0
while true; do
    cpu=$(uso_cpu); mem=$(uso_memoria); disco=$(uso_disco)

    if curl -fs -m 5 "http://localhost:$APP_PORTA/health" >/dev/null; then
        api="OK"; falhas_api=0
    else
        api="FORA"; falhas_api=$((falhas_api+1))
    fi

    log INFO "cpu=${cpu}% mem=${mem}% disco=${disco}% api=$api"
    verificar CPU     "$cpu"   "$LIMITE_CPU"
    verificar Memória "$mem"   "$LIMITE_MEMORIA"
    verificar Disco   "$disco" "$LIMITE_DISCO"

    # 2 falhas seguidas = API travada ou fora do ar -> reinicia.
    if (( falhas_api >= 2 )); then
        log ALERTA "API sem resposta em /health ($falhas_api checagens). Reiniciando safecity-api"
        auditoria "reinicio automatico safecity-api"
        systemctl restart safecity-api
        falhas_api=0
    fi

    sleep "$INTERVALO_SEGUNDOS"
done
