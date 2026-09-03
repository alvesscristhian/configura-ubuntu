#!/usr/bin/env bash
# ============================================================
# 03 - SEGREDOS   >>> RODAR NO PC ANTIGO <<<
#
# Empacota chaves e credenciais num tar CIFRADO com AES-256.
# Estes arquivos ficam FORA do pacote comum de proposito:
#   - chave privada nao viaja em tar aberto;
#   - nada disso pode encostar em repositorio git, nem privado.
#
# Uso:  ./03-segredos.sh
# Saida: ./segredos-<host>-<data>.tar.gz.gpg
#
# Transporte: leve num pendrive separado, ou copie e apague o
# original depois de conferir. NAO manda por Slack/e-mail/Drive.
# ============================================================
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAIDA="$AQUI/segredos-$(hostname)-$(date +%Y%m%d).tar.gz.gpg"
LISTA="$(mktemp)"
trap 'rm -f "$LISTA"' EXIT

log()  { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; }

command -v gpg >/dev/null || { err "gpg nao instalado: sudo apt install gnupg"; exit 1; }

# ------------------------------------------------------------
# O que entra. Caminhos relativos a $HOME.
# ------------------------------------------------------------
CANDIDATOS=(
  .ssh                       # chaves id_ed25519, explosaobike, config, known_hosts
  .gnupg                     # chaveiro GPG
  .aws                       # credenciais AWS
  .cf-pages-token            # token Cloudflare Pages
  .config/gh/hosts.yml       # token OAuth do GitHub CLI
  .docker/config.json        # credenciais de registry
  .docker/.token_seed
  .config/Bitwarden          # sessao do app Bitwarden
  bwdata                     # dados do Bitwarden self-hosted
  .netrc
  .pgpass
  .my.cnf
  .claude.json               # pode conter chave de API
  .claude/.credentials.json  # credenciais do Claude Code
  .claude/daemon/control.key
  .codex/auth.json
  .local/share/keyrings      # chaveiro do GNOME: senhas salvas de app e
                             # a chave que decifra as senhas do Chrome/Brave
)

log "Selecionando arquivos sensiveis..."
: > "$LISTA"
for p in "${CANDIDATOS[@]}"; do
  if [ -e "$HOME/$p" ]; then
    echo "$p" >> "$LISTA"
    printf '     %-26s %s\n' "$p" "$(du -sh "$HOME/$p" 2>/dev/null | cut -f1)"
  fi
done

adiciona() {  # adiciona <caminho-relativo-a-HOME>
  grep -qxF "$1" "$LISTA" && return
  echo "$1" >> "$LISTA"
  printf '     %s\n' "$1"
}

# ------------------------------------------------------------
# .env dos repos.
#
# O 02-empacotar.sh EXCLUI estes do pacote aberto, entao se eles nao
# entrarem aqui nao chegam em lugar nenhum e os projetos nao sobem no
# PC novo. Guardam senha de banco, SECRET_KEY do Django e chave de API.
#
# .env.example / .sample / .template ficam FORA: sao template
# versionado no git, viajam no pacote comum.
# ------------------------------------------------------------
log "Coletando .env dos repos (senha de banco, SECRET_KEY, chave de API)..."
while IFS= read -r f; do
  case "$(basename "$f")" in
    *.example|*.sample|*.template) continue ;;
  esac
  adiciona "${f#$HOME/}"
done < <(find "$HOME/Documentos" -maxdepth 6 -name '.env*' -type f \
           -not -path '*/node_modules/*' 2>/dev/null | sort)

# ------------------------------------------------------------
# Arquivos soltos com cara de credencial
# ------------------------------------------------------------
log "Varrendo por arquivos soltos com cara de credencial..."
while IFS= read -r f; do
  adiciona "${f#$HOME/}"
done < <(find "$HOME" "$HOME/Downloads" "$HOME/Documentos" -maxdepth 2 \
           \( -iname '*secret*' -o -iname '*credential*' -o -iname '*.pem' \
              -o -iname '*.key' -o -iname '*token*' -o -iname '*.ovpn' \
              -o -iname '*.p12' -o -iname '*.pfx' -o -iname '*.kdbx' \) \
           -type f 2>/dev/null | sort -u)

if [ ! -s "$LISTA" ]; then
  warn "Nada sensivel encontrado - nada a fazer."
  exit 0
fi

echo
warn "$(wc -l < "$LISTA") item(ns) serao cifrados em: $(basename "$SAIDA")"
warn "Escolha uma senha FORTE e guarde no Bitwarden ANTES de continuar."
warn "Se perder a senha, o pacote e irrecuperavel - nao ha backdoor."
echo
read -r -p "Continuar? [s/N] " r
[[ "$r" =~ ^[sS]$ ]] || { log "abortado"; exit 0; }

# ------------------------------------------------------------
# tar -> gpg, tudo em pipe: o tar aberto nunca toca o disco.
# --symmetric = senha, sem depender de par de chaves.
# ------------------------------------------------------------
log "Cifrando (vai pedir a senha duas vezes)..."
if tar -C "$HOME" -czf - --files-from="$LISTA" 2>/dev/null \
   | gpg --symmetric --cipher-algo AES256 --s2k-digest-algo SHA512 \
         --output "$SAIDA"
then
  chmod 600 "$SAIDA"
  log "Pronto: $SAIDA ($(du -sh "$SAIDA" | cut -f1))"
else
  err "falhou ao cifrar"; rm -f "$SAIDA"; exit 1
fi

# ------------------------------------------------------------
# Verificacao: o pacote realmente abre? Testa agora, nao no PC novo.
# ------------------------------------------------------------
echo
log "Verificando o pacote (pede a senha de novo - e o teste de que abre):"
if gpg --decrypt "$SAIDA" 2>/dev/null | tar -tzf - > /dev/null; then
  log "Verificado: o pacote abre e o conteudo esta intacto."
else
  err "O PACOTE NAO ABRIU. Nao confie nele. Apague e rode de novo."
  exit 1
fi

cat <<EOF

------------------------------------------------------------
Como restaurar no PC novo:

  gpg --decrypt $(basename "$SAIDA") | tar -xzf - -C \$HOME
  chmod 700 ~/.ssh ~/.gnupg
  chmod 600 ~/.ssh/id_ed25519 ~/.ssh/explosaobike
  ssh-add ~/.ssh/id_ed25519

Depois de conferir que as chaves funcionam no PC novo
(ssh -T git@github.com), APAGUE este arquivo do meio de transporte.
------------------------------------------------------------

Lembrete: enquanto as duas maquinas tiverem a mesma chave ativa,
vale trocar a chave do GitHub depois da migracao se o pendrive
passou por qualquer lugar que voce nao controla.
EOF
