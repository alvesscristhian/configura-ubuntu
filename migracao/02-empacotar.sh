#!/usr/bin/env bash
# ============================================================
# 02 - EMPACOTAR / TRANSFERIR   >>> RODAR NO PC ANTIGO <<<
#
# Copia a home aplicando exclude.txt. Transporte-neutro: o destino
# pode ser uma pasta local (HD externo) ou um host remoto via SSH.
#
# Uso:
#   ./02-empacotar.sh --teste                     # simula, nao copia nada
#   ./02-empacotar.sh /media/cristhian/HD/migra   # HD externo
#   ./02-empacotar.sh cristhian@192.168.0.42:/home/cristhian/migra
#
# Flags:
#   --teste     dry-run: mostra o que copiaria e o tamanho total
#   --sim       executa de verdade (sem isso, pede confirmacao)
#
# E incremental: rodar de novo copia so o que mudou. Pode rodar
# hoje pra adiantar e de novo amanha antes de desligar o PC antigo.
# ============================================================
set -uo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXCLUDE="$AQUI/exclude.txt"
DINAMICO="$AQUI/.exclude-dinamico.txt"

log()  { printf '\033[1;34m>>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31mXX\033[0m %s\n' "$*" >&2; }

TESTE=0; SIM=0; DESTINO=""
for a in "$@"; do
  case "$a" in
    --teste|--dry-run) TESTE=1 ;;
    --sim|--yes)       SIM=1 ;;
    -*)  err "flag desconhecida: $a"; exit 2 ;;
    *)   DESTINO="$a" ;;
  esac
done

command -v rsync >/dev/null || { err "rsync nao instalado: sudo apt install rsync"; exit 1; }
[ -f "$EXCLUDE" ] || { err "exclude.txt nao encontrado em $AQUI"; exit 1; }

if [ $TESTE -eq 0 ] && [ -z "$DESTINO" ]; then
  err "Falta o destino. Ex: ./02-empacotar.sh /media/cristhian/HD/migra"
  err "Ou simule primeiro:  ./02-empacotar.sh --teste"
  exit 2
fi

# ------------------------------------------------------------
# Exclusoes dinamicas: revisoes ANTIGAS de snap.
# ~/snap/<app>/current e um symlink pra revisao ativa (ex: 674).
# As outras (672, 258...) sao dado de versao anterior, duplicado.
# No PC novo o snapd cria numeros proprios, entao copiar as antigas
# e desperdicio. Aqui descobrimos qual e a atual e excluimos o resto.
# ------------------------------------------------------------
: > "$DINAMICO"
if [ -d "$HOME/snap" ]; then
  for app in "$HOME/snap"/*; do
    [ -d "$app" ] || continue
    nome=$(basename "$app")

    # revisoes existentes, em ordem de versao
    revs=()
    for rev in "$app"/*; do
      base=$(basename "$rev")
      [ -d "$rev" ] || continue
      case "$base" in [0-9]*) revs+=("$base") ;; esac
    done
    [ ${#revs[@]} -gt 0 ] || continue

    # Qual revisao guardar? Normalmente a que 'current' aponta.
    #
    # MAS o symlink pode estar QUEBRADO - neste PC, claude-ai-desktop
    # aponta pra 33 e firefox pra 8664, revisoes que nao existem mais.
    # A versao anterior deste script excluia TODAS as revisoes nesses
    # casos, jogando fora 205 MB de dado do Claude Desktop.
    # Sem alvo valido, guarda a revisao de maior numero (a mais recente).
    atual=""
    if [ -L "$app/current" ]; then
      alvo=$(basename "$(readlink "$app/current")")
      [ -d "$app/$alvo" ] && atual="$alvo"
    fi
    if [ -z "$atual" ]; then
      atual=$(printf '%s\n' "${revs[@]}" | sort -V | tail -1)
      warn "  snap/$nome: 'current' quebrado - guardando a revisao $atual"
    fi

    for base in "${revs[@]}"; do
      [ "$base" = "$atual" ] && continue
      echo "/snap/$nome/$base" >> "$DINAMICO"
    done
  done
fi
n_din=$(wc -l < "$DINAMICO")
[ "$n_din" -gt 0 ] && log "Excluindo $n_din revisao(oes) antiga(s) de snap (dado duplicado)"

# ------------------------------------------------------------
# Repos git de Documentos: voce clona no PC novo, entao nao viajam.
#
# Os vaults do Obsidian e as pastas soltas de Documentos NAO sao
# repos e continuam vindo - a exclusao e feita repo por repo, pelo
# .git encontrado, nunca pela pasta Documentos inteira.
# ------------------------------------------------------------
n_repo=0
while IFS= read -r g; do
  d=$(dirname "$g")
  echo "/${d#$HOME/}" >> "$DINAMICO"
  n_repo=$((n_repo+1))
done < <(find "$HOME/Documentos" -maxdepth 4 -name .git -type d 2>/dev/null | sort)
[ "$n_repo" -gt 0 ] && log "Excluindo $n_repo repo(s) git de Documentos (voce clona depois)"

# ------------------------------------------------------------
# Montagem do rsync
#   -a  preserva permissao, dono, timestamp, symlink
#   -H  preserva hardlink (importante: snap e npm usam muito)
#   -X -A  xattrs e ACLs
#   --numeric-ids  nao tenta mapear nome de usuario entre maquinas
#   --info=progress2  uma barra de progresso pro total, nao por arquivo
# ------------------------------------------------------------
# Os .env nao precisam de tratamento aqui: vivem dentro dos repos de
# Documentos, que sao excluidos inteiros (voce clona no PC novo).
# O 03-segredos.sh ainda os recolhe - veja a nota no topo dele.
RSYNC=(
  rsync -aHAX --numeric-ids
  --partial --info=progress2 --human-readable
  --exclude-from="$EXCLUDE"
  --exclude-from="$DINAMICO"
)

# ------------------------------------------------------------
# estimar - quanto vai ser copiado, de fato.
#
# NAO usar `du --exclude-from` aqui: du ignora a ancoragem no inicio
# do padrao (o "/" de "/.cache"), entao ele nao exclui nada e o numero
# sai absurdamente maior. O unico calculo confiavel e o proprio rsync
# em --dry-run, que usa exatamente o mesmo motor de exclusao da copia.
#
# Escreve em $EST_TOTAL (bytes) e $EST_LISTA (arquivo tmp: bytes<TAB>pasta)
# ------------------------------------------------------------
EST_TOTAL=0
EST_LISTA="$(mktemp)"
trap 'rm -f "$EST_LISTA" "$DINAMICO"' EXIT

estimar() {
  local saida
  saida=$(rsync -aHAX --numeric-ids --dry-run \
            --exclude-from="$EXCLUDE" --exclude-from="$DINAMICO" \
            --out-format='%l %n' \
            "$HOME/" "${1:-/tmp/destino-inexistente}/" 2>/dev/null \
          | awk '
              # %n de diretorio termina em "/" - nao somar o inode do dir
              /\/$/ { next }
              { n=$1; $1=""; sub(/^ /,"")
                split($0, p, "/")
                topo = (p[2]=="" ? "(arquivos na raiz)" : p[1])
                soma[topo] += n; total += n }
              END { printf "TOTAL\t%.0f\n", total
                    for (k in soma) printf "%.0f\t%s\n", soma[k], k }')
  EST_TOTAL=$(printf '%s\n' "$saida" | awk -F'\t' '$1=="TOTAL"{print $2; exit}')
  printf '%s\n' "$saida" | awk -F'\t' '$1!="TOTAL"' | sort -rn > "$EST_LISTA"
  [ -n "$EST_TOTAL" ] || EST_TOTAL=0
}

gb() { awk -v b="$1" 'BEGIN{ printf "%.1f GB", b/1073741824 }'; }

# SSH ou local?
if [[ "$DESTINO" == *:* ]] && [[ "$DESTINO" != /* ]]; then
  log "Modo: SSH -> $DESTINO"
  RSYNC+=( -e "ssh -o Compression=no" --compress )
  warn "Confirme antes que o PC novo aceita ssh: ssh ${DESTINO%%:*} true"
elif [ -n "$DESTINO" ]; then
  log "Modo: local -> $DESTINO"
  mkdir -p "$DESTINO" 2>/dev/null || { err "nao consegui criar $DESTINO"; exit 1; }
  # checagem de espaco: o destino cabe?
  log "Calculando o payload real (rsync --dry-run)..."
  estimar "$DESTINO"
  livre=$(df -PB1 "$DESTINO" | tail -1 | awk '{print $4}')
  log "Payload: $(gb "$EST_TOTAL") | livre no destino: $(gb "$livre")"
  if [ "$EST_TOTAL" -gt "$livre" ]; then
    err "Destino nao tem espaco. Faltam ~$(gb $((EST_TOTAL - livre)))."
    exit 1
  fi
  # aviso de filesystem: exFAT/NTFS nao guardam permissao nem symlink Unix
  fstype=$(findmnt -n -o FSTYPE --target "$DESTINO" 2>/dev/null || echo "?")
  case "$fstype" in
    ext4|xfs|btrfs|zfs) : ;;
    *) warn "Destino e '$fstype': nao preserva permissao/symlink/dono do Linux."
       warn "Pra HD externo nesse formato, use o modo TAR (veja README secao 4)." ;;
  esac
fi

# ------------------------------------------------------------
# Dry-run
# ------------------------------------------------------------
if [ $TESTE -eq 1 ]; then
  log "SIMULACAO - nada sera copiado."
  echo
  log "Calculando (rsync --dry-run, mesmo motor de exclusao da copia real)..."
  estimar
  home_total=$(du -sb "$HOME" 2>/dev/null | cut -f1)
  echo
  log "Home hoje:            $(gb "${home_total:-0}")"
  log "Vai ser copiado:      $(gb "$EST_TOTAL")"
  log "exclude.txt corta:    $(gb $(( ${home_total:-0} - EST_TOTAL )) )"
  echo
  log "Maiores itens que VAO ser copiados:"
  awk -F'\t' 'NR<=22 { printf "     %8.1f GB  %s\n", $1/1073741824, $2 }' "$EST_LISTA"
  echo
  log "Confira a lista acima. Algo que nao deveria ir? Edite exclude.txt"
  log "e rode a simulacao de novo."
  exit 0
fi

# ------------------------------------------------------------
# Confirmacao
# ------------------------------------------------------------
if [ $SIM -eq 0 ]; then
  [ "$EST_TOTAL" -gt 0 ] || { log "Calculando o payload..."; estimar "$DESTINO"; }
  echo
  warn "Vai copiar $(gb "$EST_TOTAL") de $HOME para $DESTINO"
  warn "Segredos (.ssh/.gnupg/.aws/bwdata) NAO vao aqui - use o 03-segredos.sh."
  read -r -p "Continuar? [s/N] " r
  [[ "$r" =~ ^[sS]$ ]] || { log "abortado"; exit 0; }
fi

# ------------------------------------------------------------
# Copia
# ------------------------------------------------------------
log "Copiando... (pode rodar de novo depois; e incremental)"
"${RSYNC[@]}" "$HOME/" "$DESTINO/"
rc=$?
rm -f "$DINAMICO"

if [ $rc -eq 0 ]; then
  log "Copia concluida sem erro."
  echo
  log "Proximos passos:"
  echo "     1. ./03-segredos.sh          (pacote cifrado das chaves)"
  echo "     2. no PC novo: ./04-restaurar.sh $DESTINO"
elif [ $rc -eq 24 ]; then
  warn "rc=24: alguns arquivos mudaram durante a copia (normal se voce"
  warn "estava usando o PC). Rode de novo pra pegar o que faltou."
else
  err "rsync terminou com codigo $rc - revise o log acima."
  exit $rc
fi
