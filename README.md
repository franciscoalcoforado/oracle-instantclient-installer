# oracle-instantclient-installer

Script de instalação do **Oracle Instant Client (Basic + SQL\*Plus)** em **Linux x86_64**.

Feito para preparar máquinas externas que rodam um sistema **Node.js** acessando Oracle DB
(o `node-oracledb` em modo *thick* precisa das bibliotecas OCI que este script instala).

## O que faz

- Baixa os pacotes oficiais da Oracle (Basic + SQL\*Plus) — sem necessidade de login.
- Extrai para o diretório de instalação e detecta a versão automaticamente.
- Exporta `INSTANT_CLIENT_HOME`, `LD_LIBRARY_PATH` e `PATH`.
- Cria os symlinks das bibliotecas (`libclntsh.so`, `libocci.so`, etc.) com versão detectada dinamicamente.
- Verifica com `sqlplus -V` e imprime um **resumo da instalação** ao final.

## Como usar (no terminal Linux da máquina de destino)

```bash
# Baixar o script
curl -fsSLO https://raw.githubusercontent.com/franciscoalcoforado/oracle-instantclient-installer/main/install-instantclient.sh

# Dar permissão de execução
chmod +x install-instantclient.sh

# Instalar (padrão: /opt/oracle, usa sudo)
sudo ./install-instantclient.sh
```

### Variantes

```bash
# Instalação local no HOME (sem sudo)
INSTALL_DIR="$HOME/oracle" ./install-instantclient.sh

# Versão específica
IC_VERSION="21.13.0.0.0dbru" sudo ./install-instantclient.sh
```

## Pré-requisitos

O script verifica `curl`, `unzip` e `libaio`. Se a `libaio` faltar:

| Distro          | Comando                                                      |
|-----------------|-------------------------------------------------------------|
| Debian/Ubuntu   | `sudo apt-get install -y libaio1` (ou `libaio1t64` no 24.04+)|
| RHEL/Rocky/OL   | `sudo dnf install -y libaio`                                 |
| Alpine          | `sudo apk add libaio`                                        |

## Depois de instalar

```bash
source /etc/profile.d/oracle-instantclient.sh   # ou reabra o shell
sqlplus usuario/senha@//host:1521/servico
```
