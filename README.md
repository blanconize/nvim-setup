# dotfiles

Terminal-only development setup for macOS: **Neovim + tmux + Claude Code**
instead of VS Code. Tuned for our stack — Next.js/React 19/TypeScript with
pnpm, Vitest and Playwright; Python with PDM.

Forked from [nikolalsvk/dotfiles](https://github.com/nikolalsvk/dotfiles),
by now almost entirely rewritten.

## Install

```bash
git clone <this repo> ~/Development/bnize/dotfiles
cd ~/Development/bnize/dotfiles && ./install.sh
```

`install.sh` is idempotent. It

- installs `zsh`, `ripgrep`, `fzf`, `neovim`, `tmux`, `git-delta`, `lazygit`,
  `gh` and `zoxide` via Homebrew if missing,
- installs [oh-my-zsh](https://ohmyz.sh) and the
  [honukai](https://github.com/oskarkrawczyk/honukai-iterm-zsh) theme,
- symlinks every config file into `$HOME` (existing files are moved to
  `<file>.bak`) — including `~/.config/nvim` and `~/.claude`,
- makes sure `~/.zshrc` sources `~/.zsh-aliases` and `~/.zsh-tools`,
- installs Neovim plugins (lazy.nvim), Treesitter parsers and language
  servers (Mason).

Because everything is symlinked, edits in this repo take effect immediately.

### Terminal app

Use a true-colour terminal — Apple Terminal is not one, and the Neovim
theme needs 24-bit colour. iTerm2 (`brew install --cask iterm2`) with the
colour preset in [`iterm2/honukai.itermcolors`](iterm2/honukai.itermcolors):
`open iterm2/honukai.itermcolors` imports it, then pick it under
Settings → Profiles → Colors → Color Presets. Font: `JetBrainsMono Nerd
Font` (`brew install --cask font-jetbrains-mono-nerd-font`) so plugin icons
render. Make it the default via menu **iTerm2 → Make iTerm2 Default Term**.

## Daily workflow

```bash
dev ~/Development/aviam/aviam-billing
```

opens (or re-attaches) a tmux session named after the repo: Neovim on the
left, Claude Code on the right, a second window with a plain shell. tmux
prefix is `Ctrl-a`; `|` / `-` split, `h j k l` move between panes.

`claude` is a shell function: it starts the CLI with `--ide`, warns when a
session already runs in the same repo, and offers `--continue` for the last
one. Inside Neovim, [claudecode.nvim](https://github.com/coder/claudecode.nvim)
speaks the IDE protocol: Claude sees the current buffer and visual selection
(`<leader>ks` to send, `<leader>kb` to add the buffer), and its proposed
changes open as Neovim diff buffers — `<leader>ka` accepts, `<leader>kd`
rejects. Claude itself stays in the tmux pane (`provider = "none"`), so no
embedded terminal.

Files Claude writes directly are reloaded automatically (`autoread` + tmux
`focus-events`). Review with `<leader>gd` (Diffview) or `lg` (lazygit);
`git diff` uses delta.

### Memory budget

Neovim ~30 MB, tmux + shells ~40 MB, tsserver 60–500 MB, one Claude session
300–600 MB. The ESLint language server (~380 MB resident) is replaced by
`nvim-lint` + `eslint_d` on save; the Tailwind language server (~600 MB) is
installed but only started on demand with `:TailwindOn` / `<leader>kt`.
Quit the Claude desktop app and VS Code — together ~2.2 GB of Electron.

## What's inside

| Path | Purpose |
|---|---|
| `nvim/init.lua` | Neovim: lazy.nvim, Treesitter, LSP via Mason (ts_ls, basedpyright, json, html, css, lua, bash, yaml; tailwind on demand), blink.cmp completion, conform (Prettier/ruff/stylua on save), nvim-lint (eslint_d/ruff), organize-imports on save for TS, fzf-lua, gitsigns/fugitive/diffview, vim-test (Vitest/pytest), oil.nvim, claudecode.nvim. |
| `.tmux.conf` | Prefix `Ctrl-a`, vi keys, mouse, focus-events, path-preserving splits. |
| `.zsh-tools` | `EDITOR=nvim`, fzf + zoxide shell integration, the `dev` function. |
| `.zsh-aliases` | pnpm shortcuts (`pd`, `pt`, `pv`, …), `g`, `lg`, `dc`, `k`, `kill_port <port>`. |
| `.gitconfig` | Aliases (`st`, `lg`, `undo`, `psf`, `cln`, …), delta pager, zdiff3 conflicts, rebase-on-pull, osxkeychain. Repos under `~/Development/aviam/` get the work e-mail via `includeIf` → `.gitconfig-aviam`. |
| `.gitignore_global` | Ignore rules for every repo. |
| `claude/CLAUDE.md` | Global Claude Code rules shared by all repos (TDD, TS/React rules, code limits). Repo `AGENTS.md` files add specifics. |
| `claude/settings.json` | Claude Code user settings: permission allow/deny list and the hooks below. |
| `claude/hooks/guard-bash.sh` | PreToolUse: blocks `db:push`/`db:reset`/`db:seed`/`migrate:apply`, prisma/drizzle push & reset, destructive `psql`, `git --no-verify`. |
| `claude/hooks/format-file.sh` | PostToolUse: runs the project's Prettier (or ruff) on every file Claude edits. |
| `skeletons/` | Templates loaded into new `*.tsx`, `*.test.tsx`, `*.sh`, `*.html` and blog-post `*.md` files. |

## Neovim cheat sheet

Leader is `<Space>`.

| Keys | Action |
|---|---|
| `<C-p>` / `<C-g>` | fzf: git files / live grep |
| `<leader>a` / `<leader>A` | grep prompt / grep word under cursor |
| `<leader>l` | buffers |
| `<leader>d` / `<leader>D` | diagnostics: file / workspace |
| `-` or `<leader>e` | file explorer (oil) |
| `gd` `gy` `gi` `gr` `K` | definition / type / implementation / references / hover |
| `<leader>rn` | rename symbol |
| `<leader>c` / `<leader>qf` / `<leader>o` | code action / quick fix / organize imports |
| `<leader>f` | format (also runs on save; `:FormatToggle` to pause) |
| `<leader>ks` (visual) / `<leader>kb` | send selection / add buffer to Claude |
| `<leader>ka` / `<leader>kd` / `<leader>kx` | accept / reject / close Claude diffs |
| `<leader>ki` / `<leader>kt` | Claude connection status / start Tailwind LSP |
| `<leader>;` / `<leader>'` / `<leader>t` | test nearest / file / last (Vitest, pytest) |
| `<leader>g` / `<leader>gs` / `<leader>gd` / `<leader>gh` / `<leader>gb` | blame / status / diff working tree / file history / open on GitHub |
| `]h` / `[h` / `<leader>hp` / `<leader>hr` | next / previous changed hunk / preview it / revert it |
| `<leader>\` / `<leader>/` | vertical / horizontal split; `<C-h/j/k/l>` move |
| `<leader>w` / `<leader>q` / `<leader>x` | save / quit / save & quit |
| `<leader>1` / `<leader>2` | sync plugins / edit config |
| `<leader>tn` | toggle relative numbers |
| `<Esc><Esc>` | leave terminal insert mode |

`:Mason` manages language servers, `:Lazy` plugins, `:checkhealth` diagnoses.

## License

MIT – see [LICENSE](LICENSE).
