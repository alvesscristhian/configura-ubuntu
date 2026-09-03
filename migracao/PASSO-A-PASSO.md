# Passo a passo da migração

Ordem de execução, com o que conferir em cada etapa.

Os dois PCs **não** precisam estar juntos. A parte A produz arquivos; a
parte B lê esses arquivos, dias depois se for o caso.

---

## Parte A — no PC antigo, antes de ir embora

### A1. Push do que só existe local

Isto **não viaja no pacote** — os repos serão clonados limpos no PC novo.
É a única coisa da migração sem volta.

```bash
cat ~/dotfiles/migracao/inventario/repos-git.txt
```

Repos com pendência hoje:

| Repo | O que tem |
|---|---|
| `Chinalink-SupplierControl` | **5 commits não pushados** (feat-330) + 12 arquivos modificados, incl. 2 testes não rastreados |
| `Chinalink-TLDV` | `docs/estrutura.md` |
| `Chinalink-FairHub` | `backend/entities/models/crm.py` |
| `automacao-aladdin` | `src/services/whatsappService.js` |
| `ecommerce-explosao` | `public/assets/js/bundle.js` |

Em cada um: `git status`, decidir o que commitar, `git push`.

Confira que não sobrou nada:

```bash
for d in ~/Documentos/Chinalink/*/ ~/Documentos/Pessoal/*/; do
  [ -d "$d/.git" ] || continue
  n=$(git -C "$d" status --porcelain | wc -l)
  p=$(git -C "$d" log --oneline @{u}..HEAD 2>/dev/null | wc -l)
  [ "$n" -eq 0 ] && [ "$p" -eq 0 ] || echo "PENDENTE: $d (mod:$n nao-pushado:$p)"
done
```

Silêncio = tudo salvo.

### A2. Inventário atualizado, no GitHub

```bash
cd ~/dotfiles/migracao
./01-inventario.sh
cd ~/dotfiles && git add -A && git commit -m "Atualiza inventario" && git push
```

Assim a lista de apps e a config do GNOME chegam pelo git, independente do
pendrive. Se o pendrive falhar, você ainda reconstrói a máquina.

### A3. Segredos

Precisa ser você — a senha de cifragem é interativa.

```bash
cd ~/dotfiles/migracao
rm -f segredos-*.gpg          # o pacote antigo não tem o keyrings
./03-segredos.sh
```

Guarde a senha no Bitwarden **antes** de confirmar. Sem ela o pacote é
irrecuperável. O script decifra de volta para provar que abre.

### A4. Pendrive

Precisa ser **exFAT ou ext4**. FAT32 não serve (limite de 4 GB por arquivo)
e o script aborta se detectar. 16 GB bastam para os 5,5 GB.

Plugue, e confirme o ponto de montagem real:

```bash
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL
```

Use o `MOUNTPOINT` que aparecer — não adivinhe o nome da pasta.

### A5. O pacote de dados

```bash
cd ~/dotfiles/migracao
./02-empacotar.sh --teste                        # confira a lista
./02-empacotar.sh --tar /media/cristhian/<LABEL> # ~5,5 GB
```

### A6. O pacote cifrado, à parte

O `exclude.txt` mantém o `.gpg` **fora** do tar de propósito — transporte
separado é o ponto. Copie na mão:

```bash
cp ~/dotfiles/migracao/segredos-*.gpg /media/cristhian/<LABEL>/
```

### A7. Confira o pendrive antes de desplugar

```bash
ls -lh /media/cristhian/<LABEL>/
```

Tem que ter **dois** arquivos: `home-*.tar.zst` e `segredos-*.tar.gz.gpg`.

```bash
sync && udisksctl unmount -b /dev/sdX1    # desmonte antes de tirar
```

### A8. NÃO formate o PC antigo ainda

Só depois da parte B conferida. Ele é o seu backup até lá.

---

## Parte B — no PC novo

### B1. O mínimo para começar

```bash
sudo apt update && sudo apt install -y git rsync zstd tar
```

O `zstd` é necessário para abrir o `.tar.zst`.

### B2. Extrair o pacote

```bash
tar --numeric-owner -xf /media/cristhian/<LABEL>/home-*.tar.zst -C "$HOME"
```

Isso já traz `~/dotfiles` inteiro, com o `.git` e os scripts — não precisa
clonar nada.

> Plano B, se o pendrive falhou:
> `git clone https://github.com/alvesscristhian/configura-ubuntu.git ~/dotfiles`
> Você recupera scripts, inventário e dotfiles, mas não os dados.

### B3. Instalar os apps e restaurar o sistema

```bash
cd ~/dotfiles/migracao
./04-restaurar.sh "$HOME" base apt snaps flatpaks
```

A etapa `apt` pausa e pede que você adicione os repositórios de terceiros
que reconhecer — ela não adiciona sozinha, porque cada um tem chave GPG
própria e adicionar no escuro é risco de supply-chain.

A etapa `home` fica **de fora** de toda a parte B: o `tar` já colocou os
arquivos no lugar.

### B4. Abrir os apps de snap uma vez

Antes do próximo passo, abra e feche: **Brave, DBeaver, Postman, Remmina,
Claude Desktop**.

Motivo: o snapd só cria `~/snap/<app>/<revisão>` e o symlink `current` no
primeiro uso do app. A etapa `snaps-dados` precisa desse destino existir
para mover o perfil antigo para lá.

### B5. Remapear os perfis de snap — é o que salva o histórico do Brave

```bash
./04-restaurar.sh "$HOME" snaps-dados
```

Se avisar `sem revisao ativa` para algum app, é porque ele ainda não foi
aberto — abra e rode de novo, só esta etapa.

### B6. O resto

```bash
./04-restaurar.sh "$HOME" limpeza zsh dconf vscode runtimes fontes
```

O `zsh` vai pedir sua senha (troca o shell padrão). O `runtimes` compila o
Python 3.11.15, demora alguns minutos.

### B7. Segredos

```bash
cd /media/cristhian/<LABEL>
gpg --decrypt segredos-*.tar.gz.gpg | tar -xzf - -C "$HOME"

chmod 700 ~/.ssh ~/.gnupg ~/.local/share/keyrings
chmod 600 ~/.ssh/id_ed25519 ~/.ssh/explosaobike
ssh -T git@github.com        # deve dizer seu usuário
```

### B8. Relogar

`dconf`, shell padrão, tema e extensões do GNOME só valem no próximo login.

### B9. Clonar os repos

Não digite a lista à mão. O `inventario/repos-git.txt` tem os 17 repos com
o remote de cada um, no caminho certo — gere os comandos dele:

```bash
cd ~/dotfiles/migracao

# 1. veja o que vai rodar
awk '/^Documentos\// {
       path=$1; url=$2
       if (url == "SEM-REMOTE" || url !~ /:/) next
       n=split(path,p,"/"); dir=""
       for(i=1;i<n;i++) dir=dir p[i] "/"
       sub(/\/$/,"",dir)
       print "mkdir -p ~/" dir " && git -C ~/" dir " clone " url
     }' inventario/repos-git.txt | sort -u

# 2. se estiver certo, execute
awk '/^Documentos\// {
       path=$1; url=$2
       if (url == "SEM-REMOTE" || url !~ /:/) next
       n=split(path,p,"/"); dir=""
       for(i=1;i<n;i++) dir=dir p[i] "/"
       sub(/\/$/,"",dir)
       print "mkdir -p ~/" dir " && git -C ~/" dir " clone " url
     }' inventario/repos-git.txt | sort -u | bash
```

São 11 em `Documentos/Chinalink`, e o resto em `Documentos/Pessoal`,
incluindo os de estudo em subpastas (`estudos/`, `baixadalabs/`).

O `ecommerce-explosao` é o único que não vem do GitHub — o remote é
`cristhian@34.55.97.194:/home/cristhian/ecommerce-explosao`, um repo bare
num servidor. Precisa da chave SSH já restaurada (passo B7).

Em cada projeto, as dependências não vieram de propósito:

```bash
npm install        # ou pnpm / yarn
uv sync            # ou python -m venv .venv && pip install -r requirements.txt
```

Os `.env` estão no pacote cifrado, já restaurados pelo B7 — mas nos
caminhos originais. Confira se caíram no lugar certo depois de clonar.

---

## Conferir antes de formatar o PC antigo

Marque um por um no PC novo:

- [ ] `history | head` no zsh mostra comandos antigos (`.zsh_history` veio)
- [ ] Brave abre com o histórico e as senhas salvas
- [ ] Chrome abre com favoritos e senhas
- [ ] Obsidian abre os 3 vaults: `memory-os`, `Obsidian Projetos`, `Pessoal/Faculdade`
- [ ] VS Code com o tema, keybindings e as 26 extensões
- [ ] Terminal com tema spaceship, fastfetch e a foto de fundo do kitty
- [ ] Tema Orchis e as extensões do GNOME ativas
- [ ] Slack e Spotify já logados
- [ ] DBeaver com as conexões, Postman com as coleções
- [ ] `ssh -T git@github.com` autentica
- [ ] Os 13 repos clonados, com `git status` limpo
- [ ] `~/Documentos/recuperado-lixeira-vscode/` está lá (plano de testes #63)

Só então formate o antigo.

---

## Pendências que não são da migração

- **Rotacionar as senhas de banco.** `DJANGO_SECRET_KEY`,
  `CONTROLDESK_DB_PASSWORD`, `RAVENA_LEGACY_DB_PASSWORD` e
  `CHINALINK_DB_PASSWORD` ficaram meses num `.env` deletado na lixeira do
  snap do VS Code, que quase viajou em claro.
- **`ChinaLink-FairApp` não tem `.env` no `.gitignore`.** Um `git add -A`
  distraído commita o arquivo.
- **Trocar a chave SSH do GitHub** se o pendrive passar por algum lugar
  que você não controla.
- **Instalar a JetBrains Mono Nerd Font** — o `settings.json` do VS Code
  pede e ela não existe em nenhuma das duas máquinas.
