#!/usr/bin/env bash
# 03 - Instala o monitor como serviço systemd (reinicia sozinho se cair).
set -euo pipefail
source "$(dirname "$0")/../lib/comum.sh"
exigir_root

# Copia os scripts para um local fixo, independente de onde o repositório foi clonado.
mkdir -p "$APP_DIR/infra"
cp -r "$RAIZ/config.env" "$RAIZ/lib" "$RAIZ/scripts" "$APP_DIR/infra/"
chmod +x "$APP_DIR/infra/scripts/"*.sh

cp "$RAIZ/systemd/safecity-monitor.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now safecity-monitor >/dev/null 2>&1
systemctl restart safecity-monitor
log INFO "Monitor ativo. Acompanhe: tail -f $LOG_DIR/monitor.log"
