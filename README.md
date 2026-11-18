# SafeCity — Infraestrutura Linux (Operating Systems)

Servidor Linux provisionado **100% por Shell Script** para hospedar a **SafeCity API**
(ASP.NET Core + SQLite), o backend da nossa CitizenTech, com monitoramento como serviço,
logs de auditoria e teste de falha.

## Ficha da CitizenTech

| Item | Resposta |
| --- | --- |
| **Nome** | SafeCity — Alerta Preventivo & Resposta Rápida |
| **Cidade e bairro** | São Paulo – SP · centro expandido (Sé, República, Luz, Brás, Av. Paulista/Consolação, Pinheiros, Santo Amaro) |
| **Cidadão beneficiado** | Trabalhador, estudante ou cidadão comum que anda a pé ou de transporte público e precisa usar o celular na rua |
| **Problema, em uma frase** | Quem circula a pé ou de transporte público não sabe onde e quando o risco de ter o celular furtado é maior e, quando o furto acontece, perde os minutos decisivos sem saber o que bloquear primeiro. |
| **Como funciona** | O app usa a localização e a previsão de risco por hora (modelo de ML) para emitir alertas preventivos; o botão "Fui roubado(a)" abre um guia passo a passo; cidadãos registram relatos anônimos que aumentam o risco do local em tempo real. |
| **O que cada parte faz** | **Operating Systems (este repositório):** servidor Linux provisionado por Shell Script que hospeda a API, com monitoramento, auditoria e recuperação de falhas. **C#:** API REST com zonas, relatos e cálculo de risco. **Mobile:** app do cidadão. **IA & ML:** modelo que prevê o risco por hora. |
| **Link do repositório** | Infra: *(link deste repositório)* · API: <https://github.com/AndreyRNagata/safecity-api> |
| **Indicador de impacto** | Disponibilidade da API (tempo de recuperação após falha, medido no teste de falha) — o cidadão não fica sem alerta quando o servidor cai. |
| **ODS conectados** | **ODS 11** (11.2 e 11.7 — transporte e espaços públicos seguros), **ODS 16** (16.1 — reduzir a violência), **ODS 9** (9.c — acesso à tecnologia) |

## Integrantes

| Integrante | RM |
| --- | --- |
| Andrey Rodrigues Nagata | RM555339 |
| Henrique Soubhia | RM554493 |
| Oliver Kanai Trindade | RM554954 |
| Pedro Gutierre Cardoso de Oliveira | RM555445 |
| William Weile Feng | RM555132 |

---

## Arquitetura

```
VM Ubuntu (safecity-srv)
├── ufw ............ libera só SSH e 5080
├── auditd ......... registra alterações nos arquivos da aplicação
├── safecity-api.service ...... dotnet SafeCity.Api.dll   (Restart=always)
│       └── /var/lib/safecity/safecity.db (SQLite)
└── safecity-monitor.service .. scripts/monitor.sh        (Restart=always)
        ├── CPU / memória / disco -> ALERTA no log
        └── GET /health falhou 2x -> systemctl restart safecity-api
Logs: /var/log/safecity/*.log  +  journalctl -t safecity
```

Duas camadas de tolerância a falhas:
1. **systemd** reinicia a API ou o monitor se o **processo morrer**.
2. **monitor** reinicia a API se ela **travar** (processo vivo, mas sem responder).

## Estrutura

| Arquivo | O que faz |
| --- | --- |
| `config.env` | Todas as variáveis (hostname, DNS, IP, porta, limites). |
| `provisionar.sh` | Roda tudo em ordem: 01 → 02 → 03. |
| `scripts/01-infra.sh` | Pacotes base, hostname, DNS local (`safecity.local`), resolvedores DNS, IP fixo opcional (netplan), firewall, auditd, logrotate. |
| `scripts/02-app.sh` | Instala .NET 8, cria usuário de serviço, clona a API, compila, gera variáveis de ambiente, sobe o serviço e verifica o `/health`. |
| `scripts/03-instalar-monitor.sh` | Instala o monitor como serviço systemd. |
| `scripts/monitor.sh` | Loop de monitoramento: CPU, memória, disco e saúde da API. |
| `scripts/04-teste-falha.sh` | Teste de falha (mata/trava API e monitor, estressa CPU). |
| `scripts/05-coletar-evidencias.sh` | Salva as saídas e os logs em `evidencias/`. |
| `lib/comum.sh` | Funções de log e auditoria usadas por todos os scripts. |
| `systemd/*.service` | Unidades systemd da API e do monitor. |

## Como executar

Requisitos: VM **Ubuntu 22.04 ou 24.04** com acesso à internet e usuário com `sudo`.

```bash
git clone <este-repositorio> safecity-infra
cd safecity-infra
sudo ./provisionar.sh
```

Ao final:

```bash
curl http://safecity.local:5080/health        # Healthy
curl http://safecity.local:5080/api/zonas     # zonas de risco
```

Swagger: `http://<IP-da-VM>:5080/swagger` (o IP aparece no log do passo 01).

Para usar IP fixo, preencha `IP_ESTATICO`, `GATEWAY` e `INTERFACE` no `config.env` antes de rodar.

## Monitoramento

```bash
systemctl status safecity-api safecity-monitor
tail -f /var/log/safecity/monitor.log
```

Exemplo de log:

```
2026-11-18 13:44:45 [INFO] [monitor.sh] cpu=19% mem=56% disco=38% api=OK
2026-11-18 13:46:02 [ALERTA] [monitor.sh] CPU em 100% (limite 80%)
2026-11-18 13:47:10 [ALERTA] [monitor.sh] API sem resposta em /health (2 checagens). Reiniciando safecity-api
```

Limites configuráveis em `config.env` (`LIMITE_CPU`, `LIMITE_MEMORIA`, `LIMITE_DISCO`, `INTERVALO_SEGUNDOS`).

## Logs de auditoria

| Onde | O que registra |
| --- | --- |
| `/var/log/safecity/auditoria.log` | Início/fim (com código de saída) de cada script, **quem** executou, deploys e reinícios automáticos. |
| `/var/log/safecity/<script>.log` | Log de execução de cada script. |
| `journalctl -t safecity` | Os mesmos eventos no journal do sistema. |
| `sudo ausearch -k safecity` | auditd: alterações em `/etc/safecity`, binários da API e unidades systemd. |

```
2026-11-18 14:02:11 usuario=henrique host=safecity-srv script=02-app.sh acao="deploy versao=a1b2c3d"
2026-11-18 14:10:40 usuario=root host=safecity-srv script=monitor.sh acao="reinicio automatico safecity-api"
```

Os logs são rotacionados diariamente (7 dias) pelo logrotate.

## Teste de falha

```bash
sudo ./scripts/04-teste-falha.sh
```

| Teste | Falha simulada | Quem recupera |
| --- | --- | --- |
| 1 | `kill -9` no processo da API | systemd (`Restart=always`) |
| 2 | `SIGSTOP` na API (travada) | monitor (2 falhas no `/health` → restart) |
| 3 | `kill -9` no monitor | systemd (`Restart=always`) |
| 4 | CPU a 100% por 25 s | monitor gera `ALERTA` |

O script mostra o PID antes/depois e o tempo de recuperação.

## Evidências

Geradas na VM com `sudo ./scripts/05-coletar-evidencias.sh --com-teste`, na pasta [`evidencias/`](evidencias/):

| Arquivo | Mostra |
| --- | --- |
| `01-rede-dns.txt` | hostname, IP, DNS local, resolvedores e firewall |
| `02-servicos.txt` | serviços `safecity-api` e `safecity-monitor` ativos |
| `03-api-health.txt` | API respondendo (`/health` e `/api/zonas`) |
| `04-dependencias.txt` | .NET instalado, variáveis de ambiente e binários publicados |
| `05-teste-falha.txt` | os 4 testes de falha e o tempo de recuperação |
| `06-monitor-log.txt` | medições do monitor e alertas |
| `07-auditoria-log.txt` | log de auditoria dos scripts |
| `08-auditd.txt` | eventos do auditd |
| `09-journal.txt` | eventos no journal do systemd |
| `*.png` | prints (Swagger no navegador, terminal) |

Ambiente usado: VM Ubuntu Server no KVM/virt-manager (2 CPUs, 4 GB RAM, 25 GB), rede NAT `192.168.122.0/24`.

**Vídeo de demonstração:** *(link do YouTube)*

## Dados

A API usa apenas **dados simulados** (14 zonas e 18 relatos de exemplo). Nenhum dado pessoal real.
