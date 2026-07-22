#!/usr/bin/env bash
#
# install-instantclient.sh
# Instala o Oracle Instant Client (Basic + SQL*Plus) em Linux x86_64.
#
# - Baixa os zips oficiais da Oracle (não requer login).
# - Extrai para um diretório de instalação.
# - Configura PATH e bibliotecas (ldconfig ou LD_LIBRARY_PATH).
# - Verifica a instalação com `sqlplus -V`.
#
# Uso:
#   ./install-instantclient.sh                 # instala em /opt/oracle (usa sudo)
#   INSTALL_DIR="$HOME/oracle" ./install-instantclient.sh   # instala local, sem sudo
#
# Variáveis de ambiente opcionais:
#   INSTALL_DIR   Diretório base da instalação (padrão: /opt/oracle)
#   IC_VERSION    Versão específica, ex: 21.13.0.0.0dbru (padrão: latest)
#
set -euo pipefail

# --------------------------------------------------------------------------- #
# Configuração
# --------------------------------------------------------------------------- #
INSTALL_DIR="${INSTALL_DIR:-/opt/oracle}"
IC_VERSION="${IC_VERSION:-latest}"
BASE_URL="https://download.oracle.com/otn_software/linux/instantclient"

if [[ "$IC_VERSION" == "latest" ]]; then
  BASIC_ZIP="instantclient-basic-linuxx64.zip"
  SQLPLUS_ZIP="instantclient-sqlplus-linuxx64.zip"
else
  BASIC_ZIP="instantclient-basic-linux.x64-${IC_VERSION}.zip"
  SQLPLUS_ZIP="instantclient-sqlplus-linux.x64-${IC_VERSION}.zip"
  BASE_URL="${BASE_URL}/${IC_VERSION%%.*}00"  # ex: 21 -> .../2100 (ajuste se necessário)
fi

# --------------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------------- #
log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[erro]\033[0m %s\n' "$*" >&2; exit 1; }

# Decide se precisamos e podemos usar sudo.
SUDO=""
if [[ "$EUID" -ne 0 ]]; then
  if [[ -w "$(dirname "$INSTALL_DIR")" ]] && [[ "$INSTALL_DIR" == "$HOME"* ]]; then
    SUDO=""   # instalação local no HOME, sem privilégios
  elif command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    die "Precisa de root/sudo para instalar em $INSTALL_DIR (ou defina INSTALL_DIR=\$HOME/oracle)."
  fi
fi

# --------------------------------------------------------------------------- #
# Pré-requisitos
# --------------------------------------------------------------------------- #
log "Verificando pré-requisitos (curl, unzip, libaio)..."

command -v curl  >/dev/null 2>&1 || die "curl não encontrado. Instale-o e rode novamente."
command -v unzip >/dev/null 2>&1 || die "unzip não encontrado. Instale-o e rode novamente."

# libaio é necessária pelo OCI. Tenta detectar; se ausente, avisa como instalar.
if ! ldconfig -p 2>/dev/null | grep -q 'libaio\.so'; then
  warn "Biblioteca libaio não detectada. Instale conforme sua distro:"
  warn "  Debian/Ubuntu : sudo apt-get install -y libaio1   (ou libaio1t64 no Ubuntu 24.04+)"
  warn "  RHEL/Rocky/OL : sudo dnf install -y libaio"
  warn "  Alpine        : sudo apk add libaio"
fi

# --------------------------------------------------------------------------- #
# Download
# --------------------------------------------------------------------------- #
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

download() {
  local file="$1"
  log "Baixando ${file}..."
  curl -fSL --retry 3 -o "${TMPDIR}/${file}" "${BASE_URL}/${file}" \
    || die "Falha ao baixar ${BASE_URL}/${file}"
}

download "$BASIC_ZIP"
download "$SQLPLUS_ZIP"

# --------------------------------------------------------------------------- #
# Instalação
# --------------------------------------------------------------------------- #
log "Criando diretório de instalação: ${INSTALL_DIR}"
$SUDO mkdir -p "$INSTALL_DIR"

log "Extraindo pacotes..."
$SUDO unzip -oq "${TMPDIR}/${BASIC_ZIP}"   -d "$INSTALL_DIR"
$SUDO unzip -oq "${TMPDIR}/${SQLPLUS_ZIP}" -d "$INSTALL_DIR"

# Descobre o diretório extraído (ex: instantclient_23_5).
IC_HOME="$(find "$INSTALL_DIR" -maxdepth 1 -type d -name 'instantclient_*' | sort -V | tail -n1)"
[[ -n "$IC_HOME" ]] || die "Não encontrei o diretório instantclient_* em ${INSTALL_DIR}."
log "Instant Client instalado em: ${IC_HOME}"

# INSTANT_CLIENT_HOME é a pasta REAL da instalação (detectada acima).
# Todas as configurações abaixo derivam dela — nada é hardcoded.
INSTANT_CLIENT_HOME="$IC_HOME"

# --------------------------------------------------------------------------- #
# Configuração de ambiente (INSTANT_CLIENT_HOME + LD_LIBRARY_PATH)
# --------------------------------------------------------------------------- #
if [[ -n "$SUDO" || "$EUID" -eq 0 ]]; then
  # Instalação de sistema: registra as libs no ldconfig e exporta as variáveis.
  log "Registrando bibliotecas no ldconfig..."
  echo "$INSTANT_CLIENT_HOME" | $SUDO tee /etc/ld.so.conf.d/oracle-instantclient.conf >/dev/null
  $SUDO ldconfig

  log "Exportando variáveis em /etc/profile.d/oracle-instantclient.sh..."
  $SUDO tee /etc/profile.d/oracle-instantclient.sh >/dev/null <<EOF
export INSTANT_CLIENT_HOME="${INSTANT_CLIENT_HOME}"
export ORACLE_HOME="${INSTANT_CLIENT_HOME}"
export LD_LIBRARY_PATH="${INSTANT_CLIENT_HOME}:\${LD_LIBRARY_PATH:-}"
export PATH="${INSTANT_CLIENT_HOME}:\$PATH"
EOF
  ENV_TARGET="/etc/profile.d/oracle-instantclient.sh"
  PROFILE_MSG="Abra um novo shell (ou rode: source ${ENV_TARGET})"
else
  # Instalação local: exporta as variáveis via arquivo de ambiente.
  ENV_TARGET="${INSTANT_CLIENT_HOME}/env.sh"
  log "Instalação local — gerando ${ENV_TARGET}..."
  cat > "$ENV_TARGET" <<EOF
export INSTANT_CLIENT_HOME="${INSTANT_CLIENT_HOME}"
export ORACLE_HOME="${INSTANT_CLIENT_HOME}"
export LD_LIBRARY_PATH="${INSTANT_CLIENT_HOME}:\${LD_LIBRARY_PATH:-}"
export PATH="${INSTANT_CLIENT_HOME}:\$PATH"
EOF
  PROFILE_MSG="Adicione ao seu ~/.bashrc:  source ${ENV_TARGET}"
fi

# --------------------------------------------------------------------------- #
# Symlinks
#
# Cria links em /usr/lib para as libs do Oracle a partir de INSTANT_CLIENT_HOME,
# detectando a versão dos .so automaticamente (libclntsh.so.19.1, .21.1, .23.1…).
# Os últimos links (libnsl/libresolv/ld-linux) são compatibilidade para imagens
# slim/distroless — só são criados se o alvo estiver faltando (nunca sobrescreve).
# --------------------------------------------------------------------------- #
if [[ -n "$SUDO" || "$EUID" -eq 0 ]]; then
  log "Criando symlinks das bibliotecas em /usr/lib..."

  # Link "genérico" -> versão específica encontrada dentro do Instant Client.
  link_lib() {
    local pattern="$1" target="$2"
    local src
    src="$(find "$INSTANT_CLIENT_HOME" -maxdepth 1 -name "$pattern" | sort -V | tail -n1)"
    if [[ -n "$src" ]]; then
      $SUDO ln -sf "$src" "$target"
      SYMLINKS_CREATED+=("$target -> $src")
    else
      warn "Não encontrei '$pattern' em $INSTANT_CLIENT_HOME (symlink $target ignorado)."
    fi
  }

  SYMLINKS_CREATED=()
  link_lib 'libclntsh.so.*' /usr/lib/libclntsh.so
  link_lib 'libocci.so.*'   /usr/lib/libocci.so
  link_lib 'libociicus.so'  /usr/lib/libociicus.so
  link_lib 'libnnz*.so'     /usr/lib/libnnz.so

  # Compatibilidade de sistema (imagens minimalistas): só cria se faltar o alvo.
  compat_link() {
    local src="$1" target="$2"
    if [[ -e "$src" && ! -e "$target" ]]; then
      $SUDO ln -s "$src" "$target"
      SYMLINKS_CREATED+=("$target -> $src (compat)")
    fi
  }

  compat_link /usr/lib/libnsl.so.2        /usr/lib/libnsl.so.1
  compat_link /lib/libc.so.6              /usr/lib/libresolv.so.2
  compat_link /lib64/ld-linux-x86-64.so.2 /usr/lib/ld-linux-x86-64.so.2

  $SUDO ldconfig
else
  warn "Sem privilégios de root — symlinks em /usr/lib foram ignorados"
  warn "(LD_LIBRARY_PATH já cobre o carregamento das libs no modo local)."
  SYMLINKS_CREATED=()
fi

# --------------------------------------------------------------------------- #
# Verificação
# --------------------------------------------------------------------------- #
log "Verificando instalação..."
VERIFY_OK=false
SQLPLUS_VERSION="$(LD_LIBRARY_PATH="${INSTANT_CLIENT_HOME}:${LD_LIBRARY_PATH:-}" \
  "${INSTANT_CLIENT_HOME}/sqlplus" -V 2>/dev/null | grep -i 'Release' || true)"
if [[ -n "$SQLPLUS_VERSION" ]]; then
  VERIFY_OK=true
else
  warn "sqlplus foi instalado, mas a verificação falhou — provavelmente falta a libaio (veja avisos acima)."
fi

# --------------------------------------------------------------------------- #
# Resumo da instalação
# --------------------------------------------------------------------------- #
echo
echo "==================== RESUMO DA INSTALAÇÃO ===================="
if $VERIFY_OK; then
  printf 'Status              : \033[1;32mOK\033[0m\n'
else
  printf 'Status              : \033[1;31mCOM AVISOS\033[0m (veja mensagens acima)\n'
fi
echo   "Componentes         : Basic + SQL*Plus"
echo   "Versão (sqlplus)    : ${SQLPLUS_VERSION:-não verificada}"
echo   "INSTANT_CLIENT_HOME : ${INSTANT_CLIENT_HOME}"
echo   "LD_LIBRARY_PATH     : ${INSTANT_CLIENT_HOME}:\$LD_LIBRARY_PATH"
echo   "PATH (sqlplus)      : ${INSTANT_CLIENT_HOME}/sqlplus"
echo   "Env exportado em    : ${ENV_TARGET}"
if [[ "${#SYMLINKS_CREATED[@]}" -gt 0 ]]; then
  echo "Symlinks criados    :"
  for l in "${SYMLINKS_CREATED[@]}"; do echo "                      - $l"; done
else
  echo "Symlinks criados    : nenhum"
fi
echo   "============================================================="
echo
log "Próximos passos:"
echo "   $PROFILE_MSG"
echo "   Depois teste:  sqlplus usuario/senha@//host:1521/servico"
