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

# Linha de versão do Instant Client:
IC_VERSION=19 sudo ./install-instantclient.sh   # 19.x  (SO antigo)
IC_VERSION=21 sudo ./install-instantclient.sh   # 21.x
# (sem IC_VERSION = latest = 23.x)
```

## Erro `GLIBC_2.29 not found`

```
Error: /lib64/libm.so.6: version `GLIBC_2.29' not found
```

Significa que o SO da máquina é **antigo demais** para o Instant Client 23.x (o `latest`).
Verifique a glibc com `ldd --version` e escolha a versão compatível:

| SO de destino                       | glibc  | Use             |
|-------------------------------------|--------|-----------------|
| RHEL/CentOS/Oracle Linux 7          | 2.17   | `IC_VERSION=19` |
| Ubuntu 18.04 / Debian 9,10          | 2.24–2.27 | `IC_VERSION=19` |
| RHEL 8+ / Ubuntu 20.04+ (glibc ≥2.29)| 2.28+  | `latest` (padrão)|

```bash
# Solução para SO antigo:
IC_VERSION=19 sudo ./install-instantclient.sh
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
