# Migração de PC — Ubuntu

> **Vai migrar agora?** O [PASSO-A-PASSO.md](PASSO-A-PASSO.md) tem a ordem
> completa, comando por comando, com o que conferir em cada etapa.
> Este README explica *como as peças funcionam*; aquele diz *o que fazer*.

Pacote para levar **este** PC (`cristhian@IdeaPad-Slim-3-15IRH10`) para outro:
configs de terminal, VS Code, pastas, dados, históricos e apps.

Transporte-neutro: os scripts funcionam por rede (SSH/rsync) ou HD externo.
A escolha só é feita na hora de rodar o `02`.

---

## Ordem de execução

| # | Script | Onde | O que faz |
|---|---|---|---|
| 1 | `01-inventario.sh` | PC **antigo** | Anota apps, versões e config do GNOME. Não copia dado. |
| 2 | `02-empacotar.sh` | PC **antigo** | Copia a home aplicando `exclude.txt`. Incremental. |
| 3 | `03-segredos.sh` | PC **antigo** | Tar cifrado (AES-256) com chaves e credenciais. |
| 4 | `04-restaurar.sh` | PC **novo** | Instala apps, devolve a home, restaura GNOME e zsh. |

## Estado de cada app (verificado no dry-run)

| App | Onde mora o dado | Status |
|---|---|---|
| **Obsidian** | `.config/obsidian` + 3 vaults | os 3 vaults vão inteiros, com `.obsidian` |
| **Brave** | `snap/brave/674/…/Default` | histórico, cookies, senhas, extensões — **exige a etapa `snaps-dados`** |
| **Chrome** | `.config/google-chrome` | histórico, senhas, cookies, favoritos, `Profile 1` |
| **Firefox** | `snap/firefox/common/.mozilla` | `places.sqlite`, `logins.json`, `key4.db`, extensões |
| **VS Code** | `.config/Code/User` | settings, keybindings, snippets; extensões pela lista |
| **Slack** | `.var/app/com.slack.Slack` | sessão logada (`Cookies` + `Local Storage`) |
| **Spotify** | `snap/spotify/99/.config` | login e preferências (620 KB); 12 GB de cache ficam |
| **DBeaver** | `snap/dbeaver-ce/549` | conexões — **exige `snaps-dados`** |
| **Postman** | `snap/postman/360` | coleções — **exige `snaps-dados`** |
| **Remmina** | `snap/remmina/7392` | conexões — **exige `snaps-dados`** |
| **Claude Desktop** | `snap/claude-ai-desktop/40` | **exige `snaps-dados`** |
| **GitHub Desktop** | `.var/app/io.github.shiftey.Desktop` | 70 arquivos de config |
| **Bitwarden** | `.config/Bitwarden` | vai no **pacote cifrado** (`03`) |

Duas observações que valem saber de antemão:

- **O Brave não tem favoritos salvos.** Não existe arquivo `Bookmarks` no
  perfil, só um `BookmarkMergedSurfaceOrdering` de 4 bytes. Não é o
  `exclude.txt` cortando — conferido com rsync direto no perfil. Se você
  esperava favoritos, eles não existem nesta máquina.
- **Só existe o perfil `Default` no Brave.** Nada de `Profile 1` como no
  Chrome.

Comece sempre simulando — não copia nada:

```bash
cd ~/migracao
./01-inventario.sh
./02-empacotar.sh --teste
```

---

## O que vai e o que não vai

A home tem **50 GB**, mas boa parte é lixo que o PC novo refaz sozinho.
O `exclude.txt` corta **40,7 GB**, medido:

| Excluído | Tamanho | Por quê |
|---|---|---|
| cache de música do Spotify | 12 GB | `.cache/`; login e prefs continuam vindo |
| `.cache` | 5,4 GB | cache de sistema |
| **17 repos git de `Documentos`** | ~4 GB | você clona no PC novo |
| cache dentro dos snaps | 2,9 GB | Brave 2,1 GB + Firefox 704 MB |
| `.var/app/com.visualstudio.code` | 2,3 GB | **2ª instalação do VS Code, sem uso** |
| caches do `.config/Code` | 1,9 GB | settings/keybindings/snippets preservados |
| `.vscode/extensions` | 1,7 GB | reinstaladas pela lista no `04` |
| `.nvm` `.pyenv` `.bun` `.dotnet` | 1,4 GB | reinstalados nas mesmas versões |
| revisões antigas de snap | ~1,5 GB | duplicata; o `02` detecta a atual sozinho |
| `Android/Sdk` | 619 MB | Android Studio rebaixa |

**O que é preservado** (verificado item por item no dry-run): os 3 vaults do
Obsidian, `.zsh_history` e `.bash_history`, `.zshrc`, `.gitconfig`,
`.config/Code/User`, `kitty`, `lazygit`, `fastfetch`, `gh`,
`.pam_environment`, fontes, temas Orchis, config do GNOME, perfis dos
navegadores, `Imagens`, `Downloads`, `fairapp-backups`, `fairhub-dumps`,
e as pastas soltas de `Documentos` (`estudos`, `baixadalabs`, PDFs).

Resultado medido: **5,8 GB** transferidos em vez de 50.

> **Repos:** a exclusão é feita repo por repo, pelo `.git` encontrado —
> nunca pela pasta `Documentos` inteira. Por isso os vaults do Obsidian
> (`memory-os`, `Obsidian Projetos`, `Pessoal/Faculdade`), que não são
> repos, continuam vindo normalmente.
>
> Consequência a considerar: os 16 arquivos `.env` são gitignored, então
> clonar **não** os traz de volta. Eles continuam no pacote cifrado do
> `03-segredos.sh` por segurança — se você já tem essas senhas em outro
> lugar, remova a seção "Coletando .env" do script.

> O `--teste` calcula com `rsync --dry-run`, não com `du`. Isso é
> deliberado: `du --exclude-from` ignora a ancoragem no início do padrão
> (o `/` de `/.cache`) e reporta um número muito maior, porque não exclui
> nada. Só o rsync usa o mesmo motor de exclusão da cópia real.

---

## Segredos ficam fora do pacote comum

Estes estão no `exclude.txt` **de propósito** e viajam só pelo
`03-segredos.sh`, cifrados com AES-256:

- `.ssh` (chaves `id_ed25519` e `explosaobike`), `.gnupg`, `.aws`
- `.cf-pages-token`, `.config/gh/hosts.yml` (token OAuth do GitHub)
- `.docker/config.json`, `.docker/.token_seed`
- `.claude/.credentials.json`, `.claude/daemon/control.key`, `.claude/sessions/*.key`
- `bwdata`, `.config/Bitwarden`
- `Documentos/secret acess key *.txt`
- `Downloads/*.key` e `*.ovpn` — a chave e o config do OpenVPN da ChinaLink
- **os 16 arquivos `.env` dos repos** — senha de banco, `SECRET_KEY` do
  Django, chave de API

Motivo: chave privada não viaja em tar aberto, e nada disso pode encostar
em repositório git — nem privado, porque histórico de git não se apaga.

Os `.env.example`, `.env.hml.example` e afins **não** são tratados como
segredo: são template versionado e seguem no pacote comum. A separação usa
regras de `--filter` no `02` (variável `FILTRO_ENV`), porque
`--exclude-from` não aceita negação.

Verificado no dry-run: **0** segredos no pacote aberto, **16** `.env`
recolhidos pelo pacote cifrado, **13** `.env.example` preservados.

O `03` decifra o pacote de volta e confere o conteúdo antes de terminar.
Guarde a senha no Bitwarden **antes** de rodar — não há recuperação.

---

## Achados deste PC

**1. Trabalho não pushado — e agora os repos NÃO viajam.**

Como você vai clonar no PC novo, o que só existe localmente **se perde**:

| Repo | Pendência |
|---|---|
| `Chinalink-SupplierControl` | **5 commits não pushados** (feat-330) + 12 arquivos modificados, incl. 2 testes não rastreados |
| `Chinalink-TLDV` | `docs/estrutura.md` modificado |
| `Chinalink-FairHub` | `backend/entities/models/crm.py` modificado |
| `automacao-aladdin` | `src/services/whatsappService.js` modificado |
| `ecommerce-explosao` | `public/assets/js/bundle.js` modificado |

**Faça o push antes de formatar o PC antigo.** O
`inventario/repos-git.txt` tem o estado de todos os 13 repos com o remote
de cada um. Isso é a única coisa nesta migração que não tem volta.

**2. Credenciais soltas fora de lugar.** Nenhuma foi aberta; todas vão no
pacote cifrado. Vale tratar cada uma depois da migração:

- `Documentos/secret acess key *.txt` — mover pro Bitwarden e apagar o `.txt`.
- `Downloads/Chinalink-UDP4-1194-*.key` e `*.ovpn` — chave de VPN em
  `Downloads`, que é pasta de arquivo descartável.
- `ChinaLink-FairApp` **não tem `.env` no `.gitignore`** (`git check-ignore`
  confirma). FairHub e TLDV têm. Um `git add -A` distraído nesse repo
  commita o `.env` — é o cenário do `Seguranca-Secrets-Hardcoded.md`.
  Corrigir isso não faz parte da migração, mas é barato.

**3. VS Code instalado 3×** — snap (`/snap/bin/code`, o que você usa),
flatpak (2,3 GB, sem uso) e o perfil `.config/Code`. O `exclude.txt` leva
só o snap. Pra migrar o flatpak em vez disso, comente a linha
`/.var/app/com.visualstudio.code`.

**4. Linha morta no `.bashrc` e `.profile`.** Ambos têm um
`. "/tmp/claude-1000/.../uv-bin/env"` de uma sessão antiga. O caminho não
existe mais nem aqui, e daria erro a cada shell no PC novo. A etapa
`limpeza` do `04` remove (com backup).

**5. `nvim/` no repo `configura-ubuntu` está vazio** — e não existe
`~/.config/nvim` nesta máquina. Não há config de nvim para migrar.

**6. Dois symlinks `current` de snap estão quebrados.**
`claude-ai-desktop` aponta para a revisão 33 e `firefox` para a 8664 —
nenhuma das duas existe mais. O `02` detecta e guarda a revisão de maior
número (40 e 8763). Sem esse tratamento, 205 MB de dado do Claude Desktop
seriam descartados silenciosamente.

**7. Perfis de snap são atrelados à revisão.** É o achado mais importante
para a sua pergunta sobre o Brave — ver a seção seguinte.

---

## Por que o histórico do Brave precisa de um passo extra

O perfil do Brave **não** fica em `snap/brave/common` (que aqui é só 2,1 GB
de cache). Ele mora em:

```
snap/brave/674/.config/BraveSoftware/Brave-Browser/Default/History
```

O `674` é o número da revisão instalada, e `snap/brave/current` é um
symlink para ela. No PC novo o snapd instala **outro** número e cria o
symlink dele.

Duas consequências, ambas tratadas:

1. `snap/*/current` está no `exclude.txt`. Se o symlink viajasse, ele
   sobrescreveria o do PC novo apontando para uma revisão inexistente, e o
   Brave abriria em branco.
2. A etapa **`snaps-dados`** do `04` move o conteúdo de `674` para dentro
   da revisão nova, e guarda o original como `.migrado-674`.

Vale para `dbeaver-ce` (conexões), `postman` (coleções), `remmina`
(conexões) e `claude-ai-desktop` também. O Firefox é a exceção: usa
`common/.mozilla`, que é independente de revisão.

**Se você rodar o `04` por etapas, não pule `snaps-dados`** — sem ela o
histórico do Brave fica no disco mas invisível para o app. Confira o
histórico antes de apagar as pastas `.migrado-*`.

---

## HD externo em exFAT/NTFS — modo `--tar`

`rsync -aHAX` precisa de filesystem Linux para guardar permissão, dono e
symlink. Se o destino for exFAT ou NTFS, use o modo `--tar`, que carrega
tudo isso dentro do próprio arquivo:

```bash
# PC antigo
./02-empacotar.sh --tar /media/cristhian/PENDRIVE

# PC novo
tar --numeric-owner -xf /media/cristhian/PENDRIVE/home-*.tar.zst -C "$HOME"
cd ~/dotfiles/migracao        # veio dentro do próprio pacote
./04-restaurar.sh "$HOME" apt snaps flatpaks snaps-dados limpeza \
     zsh dconf vscode runtimes fontes
```

Note que a etapa `home` é omitida: o `tar` já colocou os arquivos no lugar.

O modo usa zstd se estiver instalado (bem mais rápido que gzip nesse
volume), verifica o arquivo relendo as entradas, e aborta se o destino for
FAT32 — que não aceita arquivo acima de 4 GB.

> **Não** rode `tar --exclude-from=exclude.txt` na mão. Os formatos de
> padrão do tar e do rsync são diferentes: o tar ignora a ancoragem no
> início (`/.cache`), então nada seria excluído e os 12 GB de cache do
> Spotify entrariam no arquivo. Verificado — o tar inclui `.cache/` onde o
> rsync exclui.
>
> O modo `--tar` evita isso não traduzindo padrão nenhum: pede a lista de
> arquivos ao rsync, que é quem entende o `exclude.txt`, e entrega pronta
> ao tar com `--no-recursion`.

---

## Os dois PCs não precisam estar juntos

Nada aqui exige as duas máquinas ligadas ao mesmo tempo ou na mesma rede.
O `01`, `02` e `03` rodam sozinhos no PC antigo e produzem arquivos; o `04`
lê esses arquivos no PC novo, dias depois se for o caso.

A única coisa que **precisa** do PC antigo é gerar o pacote. Depois disso
ele pode ficar onde está.

### PC antigo — fazer antes de sair de perto dele

```bash
cd ~/dotfiles/migracao
./01-inventario.sh                              # 1. inventário
git -C ~/dotfiles add -A && git -C ~/dotfiles commit -m "inventario" \
  && git -C ~/dotfiles push                     # 2. inventário pro GitHub
./02-empacotar.sh --teste                       # 3. confira a lista
./02-empacotar.sh --tar /media/cristhian/PENDRIVE   # 4. o pacote (5,8 GB)
./03-segredos.sh                                # 5. chaves, cifradas
```

E o que não é script: **push dos commits pendentes** nos repos
(`inventario/repos-git.txt` lista quais). Isso não viaja no pacote.

### PC novo — depois, sem pressa

```bash
git clone https://github.com/alvesscristhian/configura-ubuntu.git ~/dotfiles
tar --numeric-owner -xf /media/.../home-*.tar.zst -C "$HOME"
cd ~/dotfiles/migracao
./04-restaurar.sh "$HOME" apt snaps flatpaks snaps-dados limpeza \
     zsh dconf vscode runtimes fontes
gpg --decrypt segredos-*.tar.gz.gpg | tar -xzf - -C "$HOME"
```

Depois relogar e seguir o checklist final que o `04` imprime.

**Só formate o PC antigo depois de conferir tudo no novo** — histórico do
Brave, vaults do Obsidian, `.zsh_history`, e os repos clonados.

O `04` aceita etapas individuais — `./04-restaurar.sh --etapas` lista todas.

---

## Relação com o repo `configura-ubuntu`

Este pacote é a **migração** (one-shot, inclui dados e segredos).
O repo `configura-ubuntu` é o **dotfiles** (versionado, só config em texto).

Hoje o repo tem 1 arquivo (`bash/.bashrc`, que é o padrão do Ubuntu e nem é
o seu shell — você usa zsh). Vale popular depois com `.zshrc`, `.gitconfig`,
`kitty.conf`, `Code/User/*.json`, `lazygit`, `fastfetch` — nunca com dados
nem segredos.
