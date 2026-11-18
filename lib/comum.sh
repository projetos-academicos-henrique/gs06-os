#!/usr/bin/env bash
# Funções comuns: carrega a configuração e grava logs de execução e de auditoria.

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
source "$RAIZ/config.env"

mkdir -p "$LOG_DIR" 2>/dev/null || true
LOG_AUDITORIA="$LOG_DIR/auditoria.log"
SCRIPT_NOME="$(basename "$0")"

# log NIVEL "mensagem"  -> tela + arquivo do script + journal (logger)
log() {
    local nivel="$1"; shift
    local linha
    linha="$(date '+%F %T') [$nivel] [$SCRIPT_NOME] $*"
    echo "$linha"
    echo "$linha" 2>/dev/null >> "$LOG_DIR/${SCRIPT_NOME%.sh}.log" || true
    logger -t safecity "[$nivel] [$SCRIPT_NOME] $*" 2>/dev/null || true
}

# auditoria "ação"  -> quem fez, o quê, quando e de onde
auditoria() {
    local quem="${SUDO_USER:-$(whoami)}"
    echo "$(date '+%F %T') usuario=$quem host=$(hostname) script=$SCRIPT_NOME acao=\"$*\"" \
        2>/dev/null >> "$LOG_AUDITORIA" || true
}

exigir_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "Execute como root: sudo $0" >&2
        exit 1
    fi
}

# Registra início e fim (com código de saída) de todo script que usa esta lib.
auditoria "inicio args=[$*]"
trap 'auditoria "fim codigo=$?"' EXIT
