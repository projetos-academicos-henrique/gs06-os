#!/usr/bin/env bash
# 01 - Infraestrutura: pacotes base, hostname, DNS, IP, firewall e auditoria (auditd).
set -euo pipefail
source "$(dirname "$0")/../lib/comum.sh"
exigir_root

log INFO "Atualizando pacotes e instalando ferramentas base"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl git ufw auditd logrotate >/dev/null

# ---------- Hostname ----------
log INFO "Definindo hostname: $HOSTNAME_SERVIDOR"
hostnamectl set-hostname "$HOSTNAME_SERVIDOR"

# ---------- DNS local (/etc/hosts) ----------
# Remove entradas antigas do SafeCity e grava a nova (script idempotente).
sed -i '/# safecity$/d' /etc/hosts
echo "127.0.1.1 $HOSTNAME_SERVIDOR $DOMINIO_LOCAL # safecity" >> /etc/hosts
log INFO "DNS local: $DOMINIO_LOCAL -> 127.0.1.1"

# ---------- Resolvedores DNS ----------
if systemctl is-active --quiet systemd-resolved; then
    mkdir -p /etc/systemd/resolved.conf.d
    printf '[Resolve]\nDNS=%s\n' "$DNS_SERVIDORES" > /etc/systemd/resolved.conf.d/safecity.conf
    systemctl restart systemd-resolved
    log INFO "Resolvedores DNS: $DNS_SERVIDORES"
fi

# ---------- IP fixo (opcional) ----------
if [[ -n "$IP_ESTATICO" && -n "$INTERFACE" ]]; then
    log INFO "Configurando IP fixo $IP_ESTATICO em $INTERFACE"
    cat > /etc/netplan/60-safecity.yaml <<NET
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: false
      addresses: [$IP_ESTATICO]
      routes: [{to: default, via: $GATEWAY}]
      nameservers: {addresses: [${DNS_SERVIDORES// /, }]}
NET
    chmod 600 /etc/netplan/60-safecity.yaml
    netplan apply
else
    log INFO "IP fixo não definido: mantendo DHCP"
fi
log INFO "Endereços IP: $(hostname -I)"

# ---------- Firewall ----------
log INFO "Firewall: liberando SSH e porta $APP_PORTA"
ufw allow OpenSSH >/dev/null
ufw allow "$APP_PORTA/tcp" >/dev/null
ufw --force enable >/dev/null

# ---------- Auditoria do sistema (auditd) ----------
# Registra qualquer alteração nos arquivos da aplicação e nos serviços.
cat > /etc/audit/rules.d/safecity.rules <<AUD
-w /etc/systemd/system/safecity-api.service -p wa -k safecity
-w /etc/systemd/system/safecity-monitor.service -p wa -k safecity
-w /etc/safecity -p wa -k safecity
-w $APP_DIR/app -p wa -k safecity
AUD
mkdir -p /etc/safecity "$APP_DIR/app"
augenrules --load >/dev/null 2>&1 || service auditd restart
log INFO "auditd ativo (consulte com: sudo ausearch -k safecity)"

# ---------- Rotação de logs ----------
cat > /etc/logrotate.d/safecity <<ROT
$LOG_DIR/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    copytruncate
}
ROT

log INFO "Infraestrutura pronta"
