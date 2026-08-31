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

## Daily workflow

```bash
dev ~/Development/aviam/aviam-billing
```

opens (or re-attaches) a tmux session named after the repo: Neovim on the
left, Claude Code on the right, a second window with a plain shell. tmux
prefix is `Ctrl-a`; `|` / `-` split, `h j k l` move between panes.

Claude edits files on disk; Neovim reloads them automatically (`autoread` +
tmux `focus-events`). Review Claude's changes with `<leader>gd` (Diffview) or
`lg` (lazygit); `git diff` uses delta.

## What's inside

| Path | Purpose |
|---|---|
| `nvim/init.lua` | Neovim: lazy.nvim, Treesitter, LSP via Mason (ts_ls, eslint, basedpyright, json, html, css, tailwind, lua, bash, yaml), blink.cmp completion, conform (Prettier/ruff/stylua on save), organize-imports + eslint-fix on save for TS, fzf-lua, gitsigns/fugitive/diffview, vim-test (Vitest/pytest), oil.nvim. |
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
| `<leader>;` / `<leader>'` / `<leader>t` | test nearest / file / last (Vitest, pytest) |
| `<leader>g` / `<leader>gs` / `<leader>gd` / `<leader>gh` / `<leader>gb` | blame / status / diff working tree / file history / open on GitHub |
| `<leader>\` / `<leader>/` | vertical / horizontal split; `<C-h/j/k/l>` move |
| `<leader>w` / `<leader>q` / `<leader>x` | save / quit / save & quit |
| `<leader>1` / `<leader>2` | sync plugins / edit config |
| `<leader>tn` | toggle relative numbers |
| `<Esc><Esc>` | leave terminal insert mode |

`:Mason` manages language servers, `:Lazy` plugins, `:checkhealth` diagnoses.

## License

MIT – see [LICENSE](LICENSE).
