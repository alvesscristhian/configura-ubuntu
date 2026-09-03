#!/usr/bin/env bash
# ============================================================
# 04 - RESTAURAR   >>> RODAR NO PC NOVO <<<
#
# Uso:
#   ./04-restaurar.sh <origem>              # roda todas as etapas
#   ./04-restaurar.sh <origem> apt snaps    # roda so as etapas citadas
#   ./04-restaurar.sh --etapas              # lista as etapas
#
# <origem> = a pasta gerada pelo 02-empacotar.sh
#            (HD externo montado, ou pasta recebida por rsync)
#
# Idempotente: pode rodar de novo sem estragar o que ja foi feito.
# ============================================================
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INV="$AQUI/inventario"

log()  { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32mOK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; }
pular(){ printf '\033[1;90m--\033[0m %s\n' "$*"; }

ETAPAS=(base apt snaps flatpaks home snaps-dados limpeza zsh dconf vscode runtimes fontes)

if [ "${1:-}" = "--etapas" ]; then
  echo "Etapas disponiveis:"
  echo "  base      pacotes minimos (rsync, git, zsh, curl, gpg, build-essential)"
  echo "  apt       repositorios de terceiros + pacotes apt do inventario"
  echo "  snaps     snaps do inventario"
  echo "  flatpaks  flathub + flatpaks do inventario"
  echo "  home      copia os dados/configs da origem pra home"
  echo "  snaps-dados  move o perfil das revisoes antigas de snap pra"
  echo "               revisao nova (e o que salva o historico do Brave)"
  echo "  limpeza   remove residuos que nao fazem sentido no PC novo"
  echo "  zsh       oh-my-zsh + tema spaceship + plugins, e vira o shell padrao"
  echo "  dconf     restaura configuracao do GNOME (tema, atalhos, dock)"
  echo "  vscode    reinstala as extensoes do VS Code"
  echo "  runtimes  nvm + node e pyenv + python nas versoes do PC antigo"
  echo "  fontes    atualiza cache de fontes e icones"
  exit 0
fi

ORIGEM="${1:-}"
[ -n "$ORIGEM" ] || { err "Falta a origem. Uso: ./04-restaurar.sh <pasta-de-origem>"; exit 2; }
shift || true
[ -d "$ORIGEM" ] || { err "origem nao e uma pasta: $ORIGEM"; exit 1; }

SELECIONADAS=("$@")
roda() {
  [ ${#SELECIONADAS[@]} -eq 0 ] && return 0
  local e; for e in "${SELECIONADAS[@]}"; do [ "$e" = "$1" ] && return 0; done
  return 1
}

[ "$(id -u)" -ne 0 ] || { err "NAO rode como root - isso quebraria o dono dos arquivos da home."; exit 1; }
[ -d "$INV" ] || warn "pasta inventario/ ausente - etapas apt/snaps/flatpaks/vscode vao ser puladas"

log "Origem : $ORIGEM"
log "Destino: $HOME"
log "Etapas : ${SELECIONADAS[*]:-todas}"
echo
read -r -p "Confirma? [s/N] " r
[[ "$r" =~ ^[sS]$ ]] || { log "abortado"; exit 0; }

# ============================================================
# base
# ============================================================
if roda base; then
  log "[base] pacotes minimos"
  sudo apt-get update -qq
  sudo apt-get install -y -qq \
    rsync git curl wget gnupg zsh build-essential \
    ca-certificates apt-transport-https software-properties-common \
    dconf-cli fontconfig
  ok "base"
fi

# ============================================================
# apt
# ============================================================
if roda apt && [ -f "$INV/apt-manual.txt" ]; then
  log "[apt] repositorios de terceiros"
  if [ -f "$INV/apt-repositorios.txt" ]; then
    warn "Repositorios de terceiros NAO sao adicionados automaticamente:"
    warn "cada um tem chave GPG propria e adicionar no escuro e risco de"
    warn "supply-chain. Abra o arquivo e adicione os que reconhecer:"
    warn "    less $INV/apt-repositorios.txt"
    grep -hoE 'https?://[^ ]+' "$INV/apt-repositorios.txt" 2>/dev/null \
      | sed 's|/dists/.*||' | sort -u | sed 's/^/       /'
    echo
    read -r -p "Ja adicionou os repos que queria? [s/N] " r
    [[ "$r" =~ ^[sS]$ ]] && sudo apt-get update -qq
  fi

  log "[apt] instalando pacotes do inventario"
  # instala um por um: um pacote inexistente no PC novo nao derruba o resto
  faltaram=()
  total=$(wc -l < "$INV/apt-manual.txt")
  i=0
  while IFS= read -r pkg; do
    [ -n "$pkg" ] || continue
    i=$((i+1))
    printf '\r     %d/%d %-45s' "$i" "$total" "$pkg"
    if ! sudo apt-get install -y -qq "$pkg" >/dev/null 2>&1; then
      faltaram+=("$pkg")
    fi
  done < "$INV/apt-manual.txt"
  printf '\r%*s\r' 60 ''
  if [ ${#faltaram[@]} -gt 0 ]; then
    warn "${#faltaram[@]} pacote(s) nao instalaram (repo ausente ou nome mudou):"
    printf '       %s\n' "${faltaram[@]}"
    printf '%s\n' "${faltaram[@]}" > "$AQUI/apt-faltaram.txt"
    warn "lista salva em apt-faltaram.txt"
  fi
  ok "apt"
elif roda apt; then
  pular "[apt] inventario ausente"
fi

# ============================================================
# snaps
# ============================================================
if roda snaps && [ -f "$INV/snap.txt" ]; then
  log "[snaps]"
  command -v snap >/dev/null || sudo apt-get install -y -qq snapd
  while IFS=$'\t' read -r nome canal notas; do
    [ -n "${nome:-}" ] || continue
    if snap list "$nome" >/dev/null 2>&1; then
      pular "  $nome (ja instalado)"; continue
    fi
    args=()
    [[ "${notas:-}" == *classic* ]] && args+=(--classic)
    printf '     instalando %s %s\n' "$nome" "${args[*]:-}"

    # Canal com branch de versao (ex: latest/stable/ubuntu-26.04) so
    # existe se o PC novo for a MESMA versao do Ubuntu. Tenta com o
    # canal exato e, se nao houver, cai pro canal sem branch.
    if [ -n "${canal:-}" ] && [ "$canal" != "-" ]; then
      if ! sudo snap install "$nome" --channel="$canal" "${args[@]}"; then
        base=$(printf '%s' "$canal" | cut -d/ -f1-2)
        warn "  canal '$canal' indisponivel - tentando '$base'"
        sudo snap install "$nome" --channel="$base" "${args[@]}" \
          || sudo snap install "$nome" "${args[@]}" \
          || warn "  falhou: $nome"
      fi
    else
      sudo snap install "$nome" "${args[@]}" || warn "  falhou: $nome"
    fi
  done < "$INV/snap.txt"
  ok "snaps"
elif roda snaps; then
  pular "[snaps] inventario ausente"
fi

# ============================================================
# flatpaks
# ============================================================
if roda flatpaks && [ -f "$INV/flatpak.txt" ]; then
  log "[flatpaks]"
  command -v flatpak >/dev/null || sudo apt-get install -y -qq flatpak
  flatpak remote-add --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
  while IFS=$'\t' read -r app origem; do
    [ -n "${app:-}" ] || continue
    if flatpak info "$app" >/dev/null 2>&1; then
      pular "  $app (ja instalado)"; continue
    fi
    flatpak install -y "${origem:-flathub}" "$app" || warn "  falhou: $app"
  done < "$INV/flatpak.txt"
  ok "flatpaks"
elif roda flatpaks; then
  pular "[flatpaks] inventario ausente"
fi

# ============================================================
# home  - o coracao: os dados e configs
# ============================================================
if roda home; then
  log "[home] copiando dados e configuracoes"
  warn "Feche VS Code, navegadores e Slack antes: app aberto reescreve"
  warn "o proprio perfil e a copia entra em conflito."
  read -r -p "Apps fechados? [s/N] " r
  [[ "$r" =~ ^[sS]$ ]] || { err "pare, feche os apps e rode: ./04-restaurar.sh $ORIGEM home"; exit 1; }

  # backup do que o Ubuntu novo criou, pra nao perder nada por descuido
  BKP="$HOME/.migracao-backup-$(date +%Y%m%d-%H%M%S)"
  mkdir -p "$BKP"
  for f in .bashrc .profile .zshrc .gitconfig; do
    [ -e "$HOME/$f" ] && cp -a "$HOME/$f" "$BKP/" 2>/dev/null
  done
  log "  originais do sistema salvos em ${BKP#$HOME/}/"

  rsync -aHAX --numeric-ids --info=progress2 --human-readable \
        --exclude='.migracao-backup-*' \
        "$ORIGEM/" "$HOME/"
  rc=$?
  [ $rc -eq 0 ] || [ $rc -eq 24 ] || { err "rsync rc=$rc"; exit $rc; }
  ok "home"
fi

# ============================================================
# snaps-dados - remapeia o dado das revisoes de snap
#
# ~/snap/<app>/<numero> e dado atrelado a UMA revisao. O perfil do
# Brave (historico, cookies, senhas, bookmarks) mora ali, nao em
# 'common': no PC antigo era snap/brave/674/.config/BraveSoftware/...
#
# No PC novo o snapd instala outro numero. Sem esta etapa a pasta 674
# fica orfa e o Brave abre em branco, com o historico presente no
# disco mas invisivel pro app.
#
# Firefox nao depende disto (usa common/.mozilla), mas rodar nao faz mal.
# ============================================================
if roda snaps-dados; then
  log "[snaps-dados] remapeando perfis de snap pra revisao nova"
  [ -d "$HOME/snap" ] || pular "  ~/snap ausente"

  for app_dir in "$HOME/snap"/*/; do
    [ -d "$app_dir" ] || continue
    app=$(basename "$app_dir")

    # revisao ativa no PC NOVO
    if [ -L "$app_dir/current" ]; then
      novo=$(basename "$(readlink "$app_dir/current")")
    else
      novo=""
    fi
    if [ -z "$novo" ] || [ ! -d "$app_dir/$novo" ]; then
      warn "  $app: sem revisao ativa - abra o app uma vez e rode de novo"
      continue
    fi

    # revisoes vindas do PC antigo, em ordem: a mais nova sobrescreve
    antigas=()
    for rev in "$app_dir"*/; do
      r=$(basename "$rev")
      [ "$r" = "common" ] && continue
      [ "$r" = "$novo" ] && continue
      case "$r" in [0-9]*) antigas+=("$r") ;; esac
    done
    [ ${#antigas[@]} -gt 0 ] || { pular "  $app (nada a remapear)"; continue; }

    while IFS= read -r r; do
      tam=$(du -sh "$app_dir$r" 2>/dev/null | cut -f1)
      log "  $app: revisao $r ($tam) -> $novo"
      rsync -aHAX "$app_dir$r/" "$app_dir$novo/" \
        && mv "$app_dir$r" "$app_dir.migrado-$r" \
        && ok "    movido (original guardado como .migrado-$r)" \
        || warn "    falhou em $app rev $r"
    done < <(printf '%s\n' "${antigas[@]}" | sort -V)
  done
  ok "snaps-dados"
  warn "Confira o historico do Brave antes de apagar as pastas .migrado-*"
fi

# ============================================================
# limpeza - residuos que so faziam sentido no PC antigo
# ============================================================
if roda limpeza; then
  log "[limpeza] removendo residuos"

  # Linha morta apontando pra /tmp de uma sessao antiga. Estava no
  # .bashrc e no .profile do PC antigo e daria erro a cada shell novo.
  for f in "$HOME/.bashrc" "$HOME/.profile" "$HOME/.zshrc"; do
    [ -f "$f" ] || continue
    if grep -q '/tmp/claude-1000/' "$f" 2>/dev/null; then
      cp -a "$f" "$f.antes-limpeza"
      sed -i '\|/tmp/claude-1000/|d' "$f"
      ok "  linha morta de /tmp removida de $(basename "$f") (backup: $(basename "$f").antes-limpeza)"
    fi
  done

  # crash logs da JVM
  rm -f "$HOME"/hs_err_pid*.log 2>/dev/null && pular "  crash logs da JVM removidos"

  # zcompdump carrega o hostname da maquina antiga no nome
  rm -f "$HOME"/.zcompdump* 2>/dev/null

  # monitors.xml descreve os monitores FISICOS do PC antigo; num PC
  # com outra tela isso da resolucao errada. Renomeia em vez de apagar.
  if [ -f "$HOME/.config/monitors.xml" ]; then
    mv "$HOME/.config/monitors.xml" "$HOME/.config/monitors.xml.pc-antigo"
    pular "  monitors.xml guardado como .pc-antigo (era da tela antiga)"
  fi
  rm -f "$HOME/.config/monitors.xml~" 2>/dev/null

  ok "limpeza"
fi

# ============================================================
# zsh - shell, tema e plugins
# ============================================================
if roda zsh; then
  log "[zsh] oh-my-zsh + tema + plugins"
  export RUNZSH=no CHSH=no KEEP_ZSHRC=yes

  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
  else
    pular "  oh-my-zsh ja presente"
  fi

  # Plugins/temas custom sao repos git. Se a copia da home trouxe as
  # pastas, ficam como estao; senao clona pelo inventario.
  clona() {  # clona <destino> <url>
    [ -d "$1/.git" ] && { pular "  $(basename "$1") ja presente"; return; }
    rm -rf "$1"; git clone --depth=1 "$2" "$1" >/dev/null 2>&1 \
      && ok "  clonado $(basename "$1")" || warn "  falhou clonar $(basename "$1")"
  }
  CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  if [ -f "$INV/omz-custom.txt" ]; then
    while IFS=$'\t' read -r caminho url; do
      [ -n "${caminho:-}" ] && [ "${url:-}" != "SEM-REMOTE" ] || continue
      clona "$CUSTOM/$caminho" "$url"
    done < <(grep -v '^#' "$INV/omz-custom.txt" | grep .)
  else
    clona "$CUSTOM/plugins/zsh-autosuggestions"    https://github.com/zsh-users/zsh-autosuggestions
    clona "$CUSTOM/plugins/zsh-syntax-highlighting" https://github.com/zsh-users/zsh-syntax-highlighting
    clona "$CUSTOM/themes/spaceship-prompt"         https://github.com/spaceship-prompt/spaceship-prompt
  fi
  # spaceship exige o symlink do tema
  if [ -d "$CUSTOM/themes/spaceship-prompt" ] && [ ! -e "$CUSTOM/themes/spaceship.zsh-theme" ]; then
    ln -sf "$CUSTOM/themes/spaceship-prompt/spaceship.zsh-theme" \
           "$CUSTOM/themes/spaceship.zsh-theme"
    ok "  symlink do tema spaceship"
  fi

  if [ "$SHELL" != "$(command -v zsh)" ]; then
    log "  virando zsh o shell padrao (vai pedir sua senha)"
    chsh -s "$(command -v zsh)" && ok "  shell padrao = zsh (vale no proximo login)"
  else
    pular "  zsh ja e o shell padrao"
  fi
  ok "zsh"
fi

# ============================================================
# dconf - a "cara" do GNOME
#
# ------------------------------------------------------------
# EXTENSOES DO GNOME ATIVAS NESTE PC (12)
# ------------------------------------------------------------
# Instaladas por voce, em ~/.local/share/gnome-shell/extensions.
# Os 4.3 MB VIAJAM na etapa `home`, entao NAO precisam ser baixadas
# de novo - so habilitadas, que e o que esta etapa faz:
#
#   blur-my-shell@aunetx                    transparencia/blur no shell
#   openbar@neuromorph                      customiza a barra superior
#                                           (marcada OUT OF DATE neste PC)
#   tilingshell@ferrarodomenico.com         tiling de janelas
#   Rounded_Corners@lennart-k               cantos arredondados
#   caffeine@patapon.info                   impede suspender a tela
#   user-theme@gnome-shell-extensions...    permite tema de shell custom
#                                           (necessaria pro tema Orchis)
#
# Nativas do Ubuntu, ja vem com o sistema - so habilitar:
#
#   ding@rastersoft.com                     icones na area de trabalho
#   tiling-assistant@ubuntu.com             assistente de tiling
#   ubuntu-appindicators@ubuntu.com         icones na bandeja
#   web-search-provider@ubuntu.com          busca web no overview
#   snapd-prompting@canonical.com           permissoes de snap
#   snapd-search-provider@canonical.com     busca de snaps
#
# Instalada mas INATIVA aqui (nao sera habilitada):
#   ubuntu-dock@ubuntu.com                  dock padrao do Ubuntu
# ------------------------------------------------------------
# ============================================================
if roda dconf && [ -f "$INV/dconf.ini" ]; then
  log "[dconf] restaurando configuracao do GNOME"
  dconf dump / > "$AQUI/dconf-antes-da-restauracao.ini" 2>/dev/null
  log "  estado atual salvo em dconf-antes-da-restauracao.ini (pra desfazer)"

  if dconf load / < "$INV/dconf.ini"; then
    ok "dconf (tema, atalhos, dock e teclado voltam apos relogar)"
  else
    warn "dconf load falhou - restaure com: dconf load / < $INV/dconf.ini"
  fi

  # Habilita o que ja veio na copia. `gnome-extensions enable` falha
  # se a extensao nao estiver no disco - por isso o aviso separado.
  if [ -f "$INV/gnome-extensions.txt" ] && command -v gnome-extensions >/dev/null; then
    log "  habilitando extensoes"
    faltando=()
    while IFS= read -r ext; do
      [ -n "$ext" ] || continue
      if gnome-extensions info "$ext" >/dev/null 2>&1; then
        gnome-extensions enable "$ext" 2>/dev/null \
          && ok "    $ext" || warn "    nao habilitou: $ext"
      else
        faltando+=("$ext")
      fi
    done < "$INV/gnome-extensions.txt"
    if [ ${#faltando[@]} -gt 0 ]; then
      warn "  ${#faltando[@]} extensao(oes) nao estao no disco - instale pelo"
      warn "  Extension Manager (flatpak ja instalado na etapa flatpaks):"
      printf '       %s\n' "${faltando[@]}"
    fi
  fi
elif roda dconf; then
  pular "[dconf] inventario ausente"
fi

# ============================================================
# vscode - extensoes
# ============================================================
if roda vscode && [ -f "$INV/vscode-extensions.txt" ]; then
  log "[vscode] reinstalando extensoes"
  if command -v code >/dev/null; then
    total=$(wc -l < "$INV/vscode-extensions.txt"); i=0
    while IFS= read -r ext; do
      [ -n "$ext" ] || continue
      i=$((i+1)); printf '\r     %d/%d %-45s' "$i" "$total" "$ext"
      code --install-extension "$ext" --force >/dev/null 2>&1 || warn "  falhou: $ext"
    done < "$INV/vscode-extensions.txt"
    printf '\r%*s\r' 60 ''
    ok "vscode ($total extensoes)"
  else
    warn "comando 'code' ausente - rode a etapa 'snaps' primeiro"
  fi
elif roda vscode; then
  pular "[vscode] inventario ausente"
fi

# ============================================================
# runtimes - nvm/node e pyenv/python nas versoes do PC antigo
# ============================================================
if roda runtimes; then
  log "[runtimes]"
  NODE_V=$(grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$INV/runtimes.txt" 2>/dev/null | head -1)
  PY_V=$(awk '/## pyenv/{f=1;next} /^## /{f=0} f && /^[0-9]+\.[0-9]+\.[0-9]+$/{print;exit}' "$INV/runtimes.txt" 2>/dev/null)

  if [ ! -d "$HOME/.nvm" ]; then
    log "  instalando nvm"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash >/dev/null 2>&1
  fi
  if [ -s "$HOME/.nvm/nvm.sh" ] && [ -n "${NODE_V:-}" ]; then
    # shellcheck disable=SC1091
    . "$HOME/.nvm/nvm.sh"
    nvm install "$NODE_V" >/dev/null 2>&1 && nvm alias default "$NODE_V" >/dev/null 2>&1 \
      && ok "  node $NODE_V" || warn "  falhou node $NODE_V"
  fi

  if [ ! -d "$HOME/.pyenv" ]; then
    log "  instalando pyenv (+ dependencias de build)"
    sudo apt-get install -y -qq make libssl-dev zlib1g-dev libbz2-dev \
      libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev \
      libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev
    curl -fsSL https://pyenv.run | bash >/dev/null 2>&1
  fi
  if [ -x "$HOME/.pyenv/bin/pyenv" ] && [ -n "${PY_V:-}" ]; then
    log "  compilando python $PY_V (demora alguns minutos)"
    "$HOME/.pyenv/bin/pyenv" install -s "$PY_V" \
      && "$HOME/.pyenv/bin/pyenv" global "$PY_V" \
      && ok "  python $PY_V" || warn "  falhou python $PY_V"
  fi

  command -v bun >/dev/null || { curl -fsSL https://bun.sh/install | bash >/dev/null 2>&1 && ok "  bun"; }
  ok "runtimes"
fi

# ============================================================
# fontes
# ============================================================
if roda fontes; then
  log "[fontes] atualizando caches"
  fc-cache -f >/dev/null 2>&1 && ok "  cache de fontes"
  command -v gtk-update-icon-cache >/dev/null && \
    gtk-update-icon-cache -f "$HOME/.local/share/icons" >/dev/null 2>&1 || true
  ok "fontes"
fi

# ============================================================
# Relatorio final
# ============================================================
cat <<'EOF'

============================================================
RESTAURACAO CONCLUIDA
============================================================

Falta fazer a mao (nao da pra automatizar):

  1. SEGREDOS - se ainda nao restaurou:
       gpg --decrypt segredos-*.tar.gz.gpg | tar -xzf - -C $HOME
       chmod 700 ~/.ssh ~/.gnupg
       chmod 600 ~/.ssh/id_ed25519 ~/.ssh/explosaobike
       ssh -T git@github.com          # testa

  2. RELOGAR - dconf, shell padrao e tema so aparecem no proximo login.

  3. EXTENSOES DO GNOME - as 6 instaladas por voce viajam na copia e a
     etapa `dconf` ja as habilita. Se alguma nao aparecer, relogue
     primeiro (o shell so carrega extensao nova no login). A lista
     completa esta comentada no topo da etapa `dconf` deste script.

  4. LOGINS - navegadores, Slack, Spotify, DBeaver e Postman pedem
     login de novo (2FA nao viaja entre maquinas).

  5. DEPENDENCIAS DOS REPOS - node_modules e .venv nao foram copiados
     de proposito. Em cada projeto:
        npm install        # ou pnpm/yarn
        uv sync            # ou python -m venv .venv && pip install -r requirements.txt

  6. CONFERIR AS PENDENCIAS GIT - os repos vieram copiados com as
     alteracoes locais e os commits nao pushados intactos. Confira:
        cat inventario/repos-git.txt
     E rode em cada um: git status && git log --oneline @{u}..HEAD

  7. HISTORICO DO SHELL - abra um terminal e aperte seta pra cima.
     Se o historico nao vier, confira: ls -l ~/.zsh_history

  8. monitors.xml - ficou como ~/.config/monitors.xml.pc-antigo porque
     descrevia a tela do PC antigo. Configure os monitores na mao.

============================================================
EOF
