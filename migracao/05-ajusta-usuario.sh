#!/usr/bin/env bash
# ============================================================
# 05 - AJUSTA USUARIO   >>> RODAR NO PC NOVO <<<
#
# Reescreve o caminho da home dentro dos arquivos de configuracao,
# quando o usuario do PC novo tem nome diferente do antigo.
#
# Uso:
#   ./05-ajusta-usuario.sh --teste            # mostra o que mudaria
#   ./05-ajusta-usuario.sh cristhian          # <usuario-antigo>
#
# ORDEM: rode DEPOIS da etapa `home` do 04 e ANTES da etapa `dconf`.
# O dconf.ini do inventario tambem carrega o caminho antigo, e uma vez
# carregado no GNOME os favoritos do Nautilus e a pasta de capturas
# apontam pra uma home que nao existe.
# ============================================================
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV="$AQUI/inventario"

log()  { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; }

TESTE=0; ANTIGO=""; NOVO=""
for a in "$@"; do
  case "$a" in
    --teste|--dry-run) TESTE=1 ;;
    --novo=*)          NOVO="${a#--novo=}" ;;
    -*) err "flag desconhecida: $a"; exit 2 ;;
    *)  ANTIGO="$a" ;;
  esac
done

# Usuario de destino.
#
# NAO usar `id -un` puro: sob sudo ele devolve "root", e o script
# reescreveria todo caminho pra /home/root. $SUDO_USER da o usuario
# real que chamou o sudo, e tem prioridade.
if [ -z "$NOVO" ]; then
  NOVO="${SUDO_USER:-$(id -un)}"
fi
if [ "$NOVO" = "root" ]; then
  err "Usuario de destino resolveu pra 'root'. Rode SEM sudo, ou passe --novo=<usuario>."
  exit 2
fi
HOME_NOVA="/home/$NOVO"

# Se nao disseram o usuario antigo, tenta descobrir pelo .zshrc
if [ -z "$ANTIGO" ]; then
  ANTIGO=$(grep -ohE '/home/[A-Za-z0-9._-]+' "$HOME/.zshrc" "$HOME/.config/kitty/kitty.conf" 2>/dev/null \
           | sed 's|/home/||' | grep -vx "$NOVO" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
  [ -n "$ANTIGO" ] && log "Usuario antigo detectado: $ANTIGO"
fi

[ -n "$ANTIGO" ] || { err "Informe o usuario antigo. Ex: ./05-ajusta-usuario.sh cristhian"; exit 2; }
[ "$ANTIGO" != "$NOVO" ] || { ok "Usuario igual ($NOVO) - nada a ajustar."; exit 0; }

log "Trocando /home/$ANTIGO  ->  $HOME_NOVA"

# ------------------------------------------------------------
# A regra de substituicao.
#
# A pegadinha: "/home/cristhian" e PREFIXO de "/home/cristhian-alves".
# Um sed ingenuo transformaria o caminho ja correto em
# "/home/cristhian-alves-alves". Por isso o padrao aceita o sufixo
# novo como alternativa (fica idempotente) e exige "/" ou fim de
# linha depois, pra nao pegar "/home/cristhianoutro".
# ------------------------------------------------------------
REGRA="s#/home/($ANTIGO|$NOVO)(/|\$)#$HOME_NOVA\\2#g"

# ------------------------------------------------------------
# Alvos. Lista explicita, nao varredura cega da home: reescrever
# banco de dados ou cache de app quebra mais do que conserta.
# ------------------------------------------------------------
ALVOS=(
  "$HOME/.zshrc"
  "$HOME/.bashrc"
  "$HOME/.profile"
  "$HOME/.config/kitty/kitty.conf"
  "$HOME/.config/fastfetch/config.jsonc"
  "$HOME/.config/obsidian/obsidian.json"
  "$HOME/.config/gtk-3.0/bookmarks"
  "$HOME/.config/gtk-4.0/bookmarks"
  "$HOME/.config/user-dirs.dirs"
  "$HOME/.config/Code/User/settings.json"
  "$HOME/.local/share/recently-used.xbel"
  "$HOME/.config/google-chrome/Default/Preferences"
  "$HOME/.config/google-chrome/Profile 1/Preferences"
  "$HOME/.config/google-chrome/Local State"
  "$INV/dconf.ini"
)
# perfis de navegador em snap (o numero da revisao varia)
while IFS= read -r f; do ALVOS+=("$f"); done < <(
  find "$HOME/snap" -maxdepth 7 \( -name Preferences -o -name 'Local State' \) \
       -type f 2>/dev/null
)

n_mudou=0; n_pulou=0
for f in "${ALVOS[@]}"; do
  [ -f "$f" ] || continue
  # so texto: grep -I descarta binario.
  #
  # O padrao e ANCORADO com (/|$) de proposito. Sem isso,
  # "/home/cristhian" casa dentro de "/home/cristhian-alves" - o
  # arquivo ja ajustado seria contado como pendente e a segunda
  # execucao relataria mudanca que nao houve.
  grep -qIE "/home/$ANTIGO(/|\$)" "$f" 2>/dev/null || { n_pulou=$((n_pulou+1)); continue; }
  ocor=$(grep -oIE "/home/$ANTIGO(/|\$)" "$f" 2>/dev/null | wc -l)

  if [ $TESTE -eq 1 ]; then
    printf '  %-64s %s ocorrencia(s)\n' "${f#$HOME/}" "$ocor"
    grep -ohI "/home/$ANTIGO[^\"'\ ,)]*" "$f" 2>/dev/null | sort -u | head -3 | sed 's|^|        |'
  else
    cp -a "$f" "$f.antes-ajuste-usuario" 2>/dev/null
    if sed -i -E "$REGRA" "$f" 2>/dev/null; then
      ok "  ${f#$HOME/} ($ocor)"
    else
      err "  falhou: ${f#$HOME/}"
    fi
  fi
  n_mudou=$((n_mudou+1))
done

echo
if [ $TESTE -eq 1 ]; then
  log "SIMULACAO: $n_mudou arquivo(s) seriam alterados, $n_pulou sem o caminho antigo."
  log "Para aplicar: ./05-ajusta-usuario.sh $ANTIGO"
  exit 0
fi

log "$n_mudou arquivo(s) ajustados (backup em *.antes-ajuste-usuario)"

# ------------------------------------------------------------
# Verificacao
# ------------------------------------------------------------
resta=0
for f in "${ALVOS[@]}"; do
  [ -f "$f" ] || continue
  if grep -qI "/home/$ANTIGO/" "$f" 2>/dev/null; then
    warn "  ainda tem caminho antigo: ${f#$HOME/}"; resta=$((resta+1))
  fi
done
[ "$resta" -eq 0 ] && ok "Verificado: nenhum caminho antigo restante nos alvos."

cat <<EOF

------------------------------------------------------------
Ainda pode sobrar caminho antigo em lugar que NAO da pra editar
com seguranca (banco sqlite de navegador, estado de Electron).
Isso costuma aparecer como:

  - pasta de download apontando pro lugar errado  -> corrija no app
  - "projeto recente" do VS Code que nao abre     -> reabra pelo menu
  - vault do Obsidian sumido                      -> Abrir pasta como cofre

Se o Obsidian abrir vazio, os 3 vaults estao em:
  \$HOME/Documentos/memory-os
  \$HOME/Documentos/Chinalink/Obsidian Projetos
  \$HOME/Documentos/Pessoal/Faculdade

Proximo passo: a etapa dconf, que agora vai carregar os caminhos certos.
  ./04-restaurar.sh "\$HOME" dconf vscode runtimes fontes
------------------------------------------------------------
EOF
