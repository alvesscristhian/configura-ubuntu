# configura-ubuntu

Dotfiles e migração de máquina para Ubuntu.

Duas coisas distintas moram aqui:

| Pasta | O que é |
|---|---|
| pacotes na raiz (`zsh/`, `kitty/`, …) | **dotfiles** — config em texto, versionada, aplicada com GNU Stow |
| `migracao/` | **migração one-shot** — leva dados, históricos e apps de um PC para outro |

Se você só quer a config num PC que já está de pé, use os pacotes.
Se está trocando de máquina, comece pelo `migracao/README.md`.

---

## Aplicando os dotfiles

O layout é o do [GNU Stow](https://www.gnu.org/software/stow/): cada pasta na
raiz é um "pacote", e dentro dele o caminho é relativo à sua home. Então
`zsh/.zshrc` vira `~/.zshrc`, e `kitty/.config/kitty/kitty.conf` vira
`~/.config/kitty/kitty.conf`.

```bash
sudo apt install stow
git clone https://github.com/alvesscristhian/configura-ubuntu.git ~/dotfiles
cd ~/dotfiles

stow --no-folding zsh git kitty fastfetch gh vscode shell bash   # todos
stow --no-folding zsh kitty                                      # ou só alguns
```

Stow cria **symlinks**, não copia. Editar `~/.zshrc` edita o arquivo do repo,
e um `git diff` mostra o que você mudou — é o ponto de usar Stow.

### Use sempre `--no-folding`

Sem essa flag o Stow faz *tree folding*: como o repo é o único dono de
`~/.config/gh`, ele linka a **pasta inteira** em vez dos arquivos. Aí um
`gh auth login` grava o `hosts.yml` — que contém o token OAuth — dentro de
`~/dotfiles/gh/.config/gh/`, ou seja, no repositório. O mesmo acontece com
`~/.config/Code`, que o VS Code enche de cache e estado.

Com `--no-folding` o Stow cria diretórios de verdade e liga só os arquivos
versionados. Verificado: 12 symlinks, 8 diretórios reais, nada além dos
arquivos do repo é linkado.

O `.gitignore` na raiz é a segunda linha de defesa, caso alguém esqueça
a flag.

### Conflito com arquivo existente

Se o arquivo já existir na home, o Stow recusa em vez de sobrescrever:

```bash
mv ~/.zshrc ~/.zshrc.orig && stow --no-folding zsh
```

Existe também `stow --adopt`, que absorve o arquivo da home para o repo —
mas ele **sobrescreve a versão versionada** com a da máquina. Só use depois
de conferir com `git diff` que não perdeu nada.

Para desfazer: `stow -D zsh`.

---

## Os pacotes

| Pacote | Conteúdo |
|---|---|
| `zsh` | `.zshrc` — oh-my-zsh, tema spaceship, plugins, nvm, bun, Android SDK, fastfetch no boot do terminal |
| `bash` | `.bashrc` — praticamente o padrão do Ubuntu; o shell em uso é o zsh |
| `git` | `.gitconfig` (usuário, `gh` como credential helper, LFS, `init.defaultBranch=main`) e `.config/git/ignore` |
| `kitty` | `kitty.conf` + `background.png` (o conf referencia a imagem por caminho absoluto) |
| `fastfetch` | `config.jsonc` |
| `gh` | `config.yml` — só preferências. **O token vive em `hosts.yml`, que nunca entra aqui** |
| `vscode` | `settings.json`, `keybindings.json` e `extensions.txt` (a lista, não as extensões) |
| `shell` | `.pam_environment` (locale híbrido en_US + pt_BR) e `.selected_editor` |

### Extensões do VS Code

`extensions.txt` é uma lista, não um pacote do Stow — não faz symlink dela.
Para reinstalar as 26:

```bash
xargs -n1 code --install-extension < vscode/extensions.txt
```

---

## Dependências que os configs assumem

Os arquivos aqui não instalam nada. O que eles esperam encontrar:

```bash
# oh-my-zsh + tema e plugins que o .zshrc carrega
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
git clone https://github.com/spaceship-prompt/spaceship-prompt ~/.oh-my-zsh/custom/themes/spaceship-prompt
ln -s ~/.oh-my-zsh/custom/themes/spaceship-prompt/spaceship.zsh-theme ~/.oh-my-zsh/custom/themes/spaceship.zsh-theme
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

sudo apt install kitty fastfetch   # terminal e o fetch que o .zshrc chama
```

O `migracao/04-restaurar.sh` faz tudo isso automaticamente, na etapa `zsh`.

---

## Pendências conhecidas

Coisas que estão assim de propósito, ou que valem consertar quando der:

- **`JetBrains Mono Nerd Font` não está instalada.** O `settings.json` pede
  ela para o editor (`JetBrainsMonoNL Nerd Font`) e para o terminal
  integrado, e o VS Code cai em fallback silencioso. O `kitty.conf` já
  contorna usando `Ubuntu Sans Mono`, que existe. Para resolver, baixe de
  [nerdfonts.com](https://www.nerdfonts.com/font-downloads) e extraia em
  `~/.local/share/fonts`, depois `fc-cache -f`.

- **O `fastfetch` referencia um logo que não existe.** O `config.jsonc`
  aponta para `~/.config/fastfetch/logo.png`, ausente nesta máquina — o
  fastfetch cai no logo ASCII do Ubuntu sem reclamar. Coloque um PNG lá,
  ou remova a chave `logo.source`.

- **Caminhos absolutos com o usuário embutido.** `kitty.conf`
  (`background.png`) e `.zshrc` (linha do `bun`) escrevem
  `/home/cristhian/...`. Funciona em qualquer máquina com o mesmo nome de
  usuário; em outro, ajuste ou troque por `~`.

- **`lazygit` ficou de fora.** O `~/.config/lazygit/config.yml` desta
  máquina tem 0 bytes — nada a versionar.

- **`nvim` não está aqui.** Não existe `~/.config/nvim` nesta máquina.

---

## O que nunca entra neste repo

Mesmo sendo privado — histórico de git não se apaga:

- chaves SSH e GPG (`~/.ssh`, `~/.gnupg`)
- `~/.config/gh/hosts.yml` (token OAuth), `~/.aws`, tokens soltos
- `.env` de projeto
- dados de app (perfis de navegador, sessões, bancos locais)

Essas coisas viajam pelo `migracao/03-segredos.sh`, cifradas com AES-256.
