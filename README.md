# dotfiles

Personal macOS setup for Vim, Git and zsh. Forked from
[nikolalsvk/dotfiles](https://github.com/nikolalsvk/dotfiles) and trimmed down
to what I actually use.

## Install

```bash
git clone <this repo> ~/Development/bnize/dotfiles
cd ~/Development/bnize/dotfiles && ./install.sh
```

`install.sh` is idempotent. It

- installs `zsh`, `ripgrep` and `fzf` via Homebrew if missing,
- installs [oh-my-zsh](https://ohmyz.sh) and the
  [honukai](https://github.com/oskarkrawczyk/honukai-iterm-zsh) theme,
- installs [vim-plug](https://github.com/junegunn/vim-plug),
- symlinks `.vimrc`, `.gitconfig`, `.gitignore_global` and `.zsh-aliases`
  into `$HOME` (existing files are moved to `<file>.bak`),
- makes sure `~/.zshrc` sources `~/.zsh-aliases`,
- runs `:PlugInstall`.

Because the files are symlinked, edits in this repo take effect immediately.

For matching terminal colours, import
[honukai.itermcolors](https://raw.githubusercontent.com/oskarkrawczyk/honukai-iterm/master/honukai.itermcolors)
in iTerm2 → Profiles → Colors.

## What's inside

| File | Purpose |
|---|---|
| `.vimrc` | Vim config: vim-plug, CoC (tsserver, solargraph, json, prettier/eslint when present), fzf, Rails/test helpers, Copilot. Leader is `<Space>`. |
| `.gitconfig` | Git aliases (`st`, `lg`, `undo`, `psf`, `cln`, …), rebase-on-pull, `push.default=current`, macOS keychain credentials. |
| `.gitignore_global` | Ignore rules that apply to every repo (`.DS_Store`, editor files, …). |
| `.zsh-aliases` | Rails, git, docker/kubectl shortcuts, `kill_port <port>`, fzf `cd` preview. |
| `skeletons/` | File templates that Vim loads into new `*.tsx`, `*.test.tsx`, `*.sh`, `*.html` and blog-post `*.md` files. |
| `pre-commit-hook.ruby-project` | Rubocop pre-commit hook for Ruby projects. Not installed automatically – copy it to `.git/hooks/pre-commit` in the project that needs it. |

## Vim cheat sheet

| Keys | Action |
|---|---|
| `<C-p>` / `<C-g>` | fzf: git files / ripgrep content |
| `<leader>a` / `<leader>A` | `:Ack!` search / search word under cursor |
| `<leader>l` | buffer list |
| `<leader>s` / `<leader>v` | open alternate (test) file / in vertical split |
| `<leader>;` / `<leader>'` | run nearest test / test file |
| `<leader>g` | git blame |
| `<leader>w` / `<leader>q` / `<leader>x` | save / quit / save & quit |
| `<leader>1` / `<leader>2` | reload `.vimrc` + `:PlugInstall` / edit `.vimrc` |
| `gd` `gy` `gi` `gr` | CoC go to definition / type / implementation / references |
| `<leader>c` / `<leader>qf` / `<leader>f` | CoC code action / quick fix / Prettier format |

## License

MIT – see [LICENSE](LICENSE).
