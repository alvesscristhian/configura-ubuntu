#!/usr/bin/env bash
# ============================================================
# 01 - INVENTARIO   >>> RODAR NO PC ANTIGO (este) <<<
#
# Nao copia dado nenhum. Só anota o que esta instalado e como o
# sistema esta configurado, pra o PC novo poder reconstruir.
# Saida: ./inventario/
#
# Uso:  ./01-inventario.sh
# ============================================================
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$AQUI/inventario"
mkdir -p "$OUT"

log() { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }

log "Inventariando em $OUT"

# ---- identidade da maquina de origem ------------------------
{
  echo "# Gerado em: $(date -Is)"
  echo "# Host: $(hostname)"
  echo "# Usuario: $USER"
  echo "# Shell: $SHELL"
  echo
  echo "## SO"
  lsb_release -a 2>/dev/null
  echo
  echo "## Kernel"
  uname -a
  echo
  echo "## Sessao grafica"
  echo "XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-?}  XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-?}"
  gnome-shell --version 2>/dev/null
} > "$OUT/sistema.txt"
log "sistema.txt"

# ---- pacotes apt --------------------------------------------
# showmanual = so o que voce pediu explicitamente. As dependencias
# o apt resolve sozinho no PC novo.
apt-mark showmanual 2>/dev/null | sort > "$OUT/apt-manual.txt"
log "apt-manual.txt ($(wc -l < "$OUT/apt-manual.txt") pacotes)"

# repositorios de terceiros (PPAs) - sem eles metade dos pacotes acima nao acha
{
  echo "# --- /etc/apt/sources.list.d/ ---"
  for f in /etc/apt/sources.list.d/*; do
    [ -e "$f" ] || continue
    echo; echo "### $f"; cat "$f" 2>/dev/null
  done
  echo; echo "# --- /etc/apt/sources.list ---"
  cat /etc/apt/sources.list 2>/dev/null
} > "$OUT/apt-repositorios.txt"
log "apt-repositorios.txt"

# chaves dos repos de terceiros (nao sao segredo - sao chaves publicas)
ls -1 /etc/apt/keyrings /etc/apt/trusted.gpg.d 2>/dev/null | sort -u > "$OUT/apt-keyrings.txt"

# ---- snaps ---------------------------------------------------
if command -v snap >/dev/null; then
  # nome + canal + se e classic; bases (core*) o snapd traz sozinho.
  #
  # `snap list` TRUNCA a coluna Tracking com "…" quando o canal tem branch
  # (o firefox usa latest/stable/ubuntu-XX.XX). Passar esse "…" pro
  # --channel faz o install falhar, entao o canal real vem do `snap info`
  # e, se ainda vier sujo, cai pra <track>/<risk> que sempre existe.
  : > "$OUT/snap.txt"
  IGNORAR='^(core|core18|core20|core22|core24|bare|snapd|gtk-common-themes|gnome-3-28-1804|gnome-42-2204|gnome-46-2404|mesa-2404|snapd-desktop-integration|snapd-search-provider|desktop-security-center|prompting-client|firmware-updater|snap-store)$'
  # colunas do `snap list`: Name Version Rev Tracking Publisher Notes
  while read -r nome _ _ _ _ notas; do
    [ -n "$nome" ] || continue
    [[ "$nome" =~ $IGNORAR ]] && continue

    canal=$(snap info "$nome" 2>/dev/null | awk '/^ *tracking: /{print $2; exit}')
    LIMPO='^[a-z0-9][a-z0-9./_-]*$'
    # sem "…" e sem nada fora de [a-z0-9./_-]; senao cai pra track/risk
    if [ -z "$canal" ] || ! [[ "$canal" =~ $LIMPO ]]; then
      canal=$(printf '%s' "$canal" | cut -d/ -f1-2)
      [[ "$canal" =~ $LIMPO ]] || canal="latest/stable"
    fi
    printf '%s\t%s\t%s\n' "$nome" "$canal" "${notas:--}" >> "$OUT/snap.txt"
  done < <(snap list 2>/dev/null | tail -n +2)
  snap list --all > "$OUT/snap-completo.txt" 2>/dev/null
  log "snap.txt ($(wc -l < "$OUT/snap.txt") apps)"
else
  warn "snap ausente"
fi

# ---- flatpaks ------------------------------------------------
if command -v flatpak >/dev/null; then
  flatpak list --app --columns=application,origin 2>/dev/null > "$OUT/flatpak.txt"
  flatpak remotes --columns=name,url 2>/dev/null > "$OUT/flatpak-remotes.txt"
  log "flatpak.txt ($(wc -l < "$OUT/flatpak.txt") apps)"
fi

# ---- extensoes do VS Code -----------------------------------
if command -v code >/dev/null; then
  code --list-extensions 2>/dev/null | sort > "$OUT/vscode-extensions.txt"
  log "vscode-extensions.txt ($(wc -l < "$OUT/vscode-extensions.txt") extensoes)"
else
  warn "comando 'code' nao encontrado - pulando extensoes"
fi

# ---- extensoes do GNOME + tema ------------------------------
if command -v gnome-extensions >/dev/null; then
  gnome-extensions list --enabled 2>/dev/null > "$OUT/gnome-extensions.txt"
  log "gnome-extensions.txt ($(wc -l < "$OUT/gnome-extensions.txt") ativas)"
fi

# dconf = TODA a configuracao do GNOME (atalhos, tema, dock, teclado,
# monitores, comportamento do nautilus...). E o arquivo que mais
# devolve "a cara do PC antigo" de uma vez.
if command -v dconf >/dev/null; then
  dconf dump / > "$OUT/dconf.ini" 2>/dev/null
  log "dconf.ini ($(wc -c < "$OUT/dconf.ini") bytes)"
fi

# ---- runtimes / versoes -------------------------------------
{
  echo "# Versoes em uso no PC antigo - o 04-restaurar.sh reinstala estas."
  echo
  echo "## pyenv"
  ls -1 "$HOME/.pyenv/versions" 2>/dev/null || echo "(pyenv ausente)"
  echo "global: $(cat "$HOME/.pyenv/version" 2>/dev/null || echo '?')"
  echo
  echo "## nvm / node"
  ls -1 "$HOME/.nvm/versions/node" 2>/dev/null || echo "(nvm ausente)"
  echo "default: $(cat "$HOME/.nvm/alias/default" 2>/dev/null || echo '?')"
  echo
  echo "## binarios no PATH"
  for b in python3 node npm pnpm yarn bun go rustc java docker docker-compose gh git uv poetry; do
    if command -v "$b" >/dev/null 2>&1; then
      printf '%-16s %s\n' "$b" "$("$b" --version 2>&1 | head -1)"
    fi
  done
} > "$OUT/runtimes.txt"
log "runtimes.txt"

# ---- pacotes globais de linguagem ---------------------------
{
  echo "## npm -g"
  npm ls -g --depth=0 2>/dev/null | tail -n +2
  echo
  echo "## pipx"
  pipx list --short 2>/dev/null
  echo
  echo "## uv tools"
  uv tool list 2>/dev/null
  echo
  echo "## cargo"
  ls -1 "$HOME/.cargo/bin" 2>/dev/null
} > "$OUT/pacotes-globais.txt"
log "pacotes-globais.txt"

# ---- fontes e temas -----------------------------------------
{
  echo "## ~/.fonts"; ls -1 "$HOME/.fonts" 2>/dev/null
  echo; echo "## ~/.local/share/fonts"; ls -1 "$HOME/.local/share/fonts" 2>/dev/null
  echo; echo "## ~/.themes"; ls -1 "$HOME/.themes" 2>/dev/null
  echo; echo "## ~/.icons + ~/.local/share/icons"
  ls -1 "$HOME/.icons" "$HOME/.local/share/icons" 2>/dev/null
} > "$OUT/fontes-temas.txt"
log "fontes-temas.txt"

# ---- oh-my-zsh: tema e plugins customizados -----------------
{
  echo "# Plugins/temas custom do oh-my-zsh sao repos git separados."
  echo "# O 04-restaurar.sh clona cada um destes."
  echo
  for d in "$HOME/.oh-my-zsh/custom/plugins"/* "$HOME/.oh-my-zsh/custom/themes"/*; do
    [ -d "$d" ] || continue
    # So repo git PROPRIO. Sem o teste de .git, `git -C` sobe a arvore e
    # devolve o remote do .oh-my-zsh pai - foi o que aconteceu com
    # plugins/example, que e template do proprio oh-my-zsh e nao um repo.
    if [ ! -e "$d/.git" ]; then
      echo "# ignorado (nao e repo git proprio): $(basename "$d")"
      continue
    fi
    url=$(git -C "$d" remote get-url origin 2>/dev/null || echo "SEM-REMOTE")
    echo "$(basename "$(dirname "$d")")/$(basename "$d")	$url"
  done
} > "$OUT/omz-custom.txt"
log "omz-custom.txt"

# ---- repos git: mapa (referencia, os repos vao copiados) ----
{
  echo "# Mapa dos repos git. Voce escolheu levar os repos COPIADOS"
  echo "# (com .git e alteracoes locais), entao isto e so conferencia:"
  echo "# se algo se perder, esta lista diz de onde reclonar."
  echo
  printf '%-58s %-62s %s\n' "CAMINHO" "REMOTE" "PENDENCIAS"
  while IFS= read -r g; do
    d=$(dirname "$g")
    r=$(git -C "$d" remote get-url origin 2>/dev/null || echo "SEM-REMOTE")
    s=$(git -C "$d" status --porcelain 2>/dev/null | wc -l)
    n=$(git -C "$d" log --oneline @{u}..HEAD 2>/dev/null | wc -l)
    printf '%-58s %-62s mod:%-4s nao-pushado:%s\n' "${d#$HOME/}" "$r" "$s" "$n"
  done < <(find "$HOME/Documentos" -maxdepth 4 -name .git -type d 2>/dev/null | sort)
} > "$OUT/repos-git.txt"
log "repos-git.txt"

# ---- crontab e servicos de usuario --------------------------
crontab -l > "$OUT/crontab.txt" 2>/dev/null || echo "(sem crontab)" > "$OUT/crontab.txt"
systemctl --user list-unit-files --state=enabled > "$OUT/systemd-user.txt" 2>/dev/null

# ---- impressoras / rede wifi (nomes, sem senha) -------------
lpstat -p 2>/dev/null > "$OUT/impressoras.txt" || true
nmcli -t -f NAME,TYPE connection show 2>/dev/null > "$OUT/redes.txt" || true

echo
log "Inventario pronto:"
ls -lh "$OUT" | tail -n +2 | awk '{printf "     %-28s %s\n", $9, $5}'
echo
warn "apt-repositorios.txt pode estar incompleto se /etc/apt/sources.list.d exigir root."
warn "Nesse caso rode: sudo ./01-inventario.sh"
