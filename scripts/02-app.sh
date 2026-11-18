#!/usr/bin/env bash
# 02 - Aplicação: instala o .NET, baixa a SafeCity API, compila e sobe como serviço systemd.
set -euo pipefail
source "$(dirname "$0")/../lib/comum.sh"
exigir_root

export DEBIAN_FRONTEND=noninteractive DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1

# ---------- Dependências ----------
# Pega a versão mais nova do SDK disponível no apt (ex.: dotnet-sdk-8.0, dotnet-sdk-10.0).
# A API roda em qualquer .NET >= 7 (RollForward=Major no projeto).
sdk_disponivel() {
    apt-cache search --names-only '^dotnet-sdk-[0-9]+\.[0-9]+$' | awk '{print $1}' | sort -V | tail -1
}

if ! command -v dotnet >/dev/null; then
    pacote="$(sdk_disponivel)"
    if [[ -z "$pacote" ]]; then
        log INFO "SDK .NET não encontrado: habilitando repositório universe"
        apt-get install -y -qq software-properties-common >/dev/null
        add-apt-repository -y universe >/dev/null
        apt-get update -qq
        pacote="$(sdk_disponivel)"
    fi

    if [[ -n "$pacote" ]]; then
        log INFO "Instalando $pacote (apt)"
        apt-get install -y -qq "$pacote" >/dev/null
    else
        # Plano B: instalador oficial da Microsoft.
        log INFO "Instalando .NET 8 pelo script oficial da Microsoft"
        curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
        bash /tmp/dotnet-install.sh --channel 8.0 --install-dir /usr/share/dotnet >/dev/null
        ln -sf /usr/share/dotnet/dotnet /usr/bin/dotnet
    fi
fi
log INFO "dotnet $(dotnet --version)"

# ---------- Usuário de serviço (sem login) ----------
if ! id "$APP_USUARIO" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$APP_USUARIO"
    log INFO "Usuário de serviço criado: $APP_USUARIO"
fi
mkdir -p "$APP_DIR" "$DADOS_DIR" "$LOG_DIR" /etc/safecity

# ---------- Código-fonte ----------
if [[ -d "$APP_DIR/src/.git" ]]; then
    log INFO "Atualizando código ($REPO_BRANCH)"
    git -C "$APP_DIR/src" pull -q
else
    log INFO "Clonando $REPO_URL"
    git clone -q --branch "$REPO_BRANCH" "$REPO_URL" "$APP_DIR/src"
fi
log INFO "Versão: $(git -C "$APP_DIR/src" log -1 --format='%h %s')"

# ---------- Build ----------
log INFO "Compilando (dotnet publish)"
dotnet publish "$APP_DIR/src/src/SafeCity.Api" -c Release -o "$APP_DIR/app" --nologo -v q
auditoria "deploy versao=$(git -C "$APP_DIR/src" log -1 --format=%h)"

# ---------- Variáveis de ambiente da aplicação ----------
cat > /etc/safecity/safecity.env <<ENV
ASPNETCORE_ENVIRONMENT=Production
ASPNETCORE_URLS=http://0.0.0.0:$APP_PORTA
ConnectionStrings__SafeCity=Data Source=$DADOS_DIR/safecity.db
DOTNET_CLI_TELEMETRY_OPTOUT=1
ENV

chown -R "$APP_USUARIO:$APP_USUARIO" "$APP_DIR/app" "$DADOS_DIR"

# ---------- Serviço systemd ----------
cp "$RAIZ/systemd/safecity-api.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now safecity-api >/dev/null 2>&1
systemctl restart safecity-api

# ---------- Verificação ----------
log INFO "Aguardando a API responder em /health"
for _ in $(seq 1 30); do
    if curl -fs "http://localhost:$APP_PORTA/health" >/dev/null; then
        log INFO "API no ar: http://$DOMINIO_LOCAL:$APP_PORTA/swagger"
        exit 0
    fi
    sleep 2
done
log ERRO "API não respondeu. Veja: journalctl -u safecity-api -n 50"
exit 1
