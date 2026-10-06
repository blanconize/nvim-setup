# dotfiles

Terminal-only development setup for macOS and Linux: **Neovim + tmux + Claude Code**
instead of VS Code. Tuned for our stack — Next.js/React 19/TypeScript with
pnpm, Vitest and Playwright; Python with PDM.

Forked from [nikolalsvk/dotfiles](https://github.com/nikolalsvk/dotfiles),
by now almost entirely rewritten.

## Install

```bash
git clone git@github.com:blanconize/nvim-setup.git
cd nvim-setup && ./install.sh
```

Clone it wherever you like — the symlinks point at the clone, so the
location does not matter, only that it stays put. Prerequisites: `git`
(on a Mac: Xcode Command Line Tools), and on Linux `curl` plus `sudo`
rights. Supported: macOS, and Linux distributions with **apt** (Debian,
Ubuntu, Mint …), **dnf** (Fedora; RHEL, Rocky, Alma via EPEL) or **pacman** (Arch family),
on x86_64 or aarch64 — desktop, server and WSL2 alike.
`install.sh` is idempotent and pins nothing — every installer fetches the
current version. On macOS it

- installs Homebrew if missing, then `zsh`, `ripgrep`, `fzf`, `neovim`,
  `tmux`, `git-delta`, `lazygit`, `gh`, `zoxide`, `jq`, `node`, `pnpm`,
  `pdm`,
- installs iTerm2 and `JetBrainsMono Nerd Font` (casks),
- installs [oh-my-zsh](https://ohmyz.sh), the
  [honukai](https://github.com/oskarkrawczyk/honukai-iterm-zsh) theme and
  sets `ZSH_THEME` in `~/.zshrc`,
- installs Claude Code via the native installer (`~/.local/bin/claude`,
  self-updating),
- makes iTerm2 the default terminal and generates the iTerm2 profile
  (see below),
- symlinks every config file into `$HOME` (existing files are moved to
  `<file>.bak`) — including `~/.config/nvim` and `~/.claude`,
- makes sure `~/.zshrc` sources `~/.zsh-aliases` and `~/.zsh-tools`,
- installs Neovim plugins (lazy.nvim), Treesitter parsers and language
  servers (Mason).

On Linux it instead

- installs the basics with the native package manager (`sudo`): zsh, git,
  ripgrep, tmux, jq, lsof, zoxide, a C compiler for Treesitter, python3,
  and `gh` (on Debian/Ubuntu from GitHub's apt repository),
- installs what distros ship too old or not at all from upstream into
  `~/.local` (no root): Neovim ≥ 0.11, fzf ≥ 0.48, lazygit, delta,
  tree-sitter, Node LTS (only if the distro's is < 20 or lacks npm), pnpm,
  pdm — and puts `~/.local/bin` on the `PATH` via `~/.zshenv` and
  `~/.profile`,
- installs JetBrainsMono Nerd Font into `~/.local/share/fonts` only when it
  runs inside a graphical session (not over ssh, not on WSL — there the
  font belongs on the client),
- makes zsh the login shell (`chsh`); log in again afterwards.

Everything else (oh-my-zsh, theme, Claude Code, symlinks, Neovim tooling)
is the same on both. Git credentials: `~/.gitconfig-os` links to
`.gitconfig-macos` (keychain) or `.gitconfig-linux`
(`gh auth git-credential`, works headless).

Because everything is symlinked, edits in this repo take effect immediately.

Afterwards, once per machine: `gh auth login`, and run `claude` once to log
in (it installs the plugins listed in `claude/settings.json` on first start).
Put machine-local secrets in `~/.zsh-secrets` (`chmod 600`, sourced by
`.zsh-tools`) — in particular `export CONTEXT7_API_KEY="…"` so the Context7
MCP plugin (current framework docs) runs on our plan instead of the anonymous
rate limit; restart Claude Code after setting it.
Not synced on purpose: `~/.claude/projects/` (sessions, auto-memory) and
`settings.local.json`. Git identity lives in `.gitconfig` /
`.gitconfig-aviam` — change those if this is not your machine.

### Terminal app

Use a true-colour terminal — Apple Terminal is not one, and the Neovim
theme needs 24-bit colour. [`iterm2/profile.sh`](iterm2/profile.sh)
(run by `install.sh`) turns
[`iterm2/honukai.itermcolors`](iterm2/honukai.itermcolors) into an iTerm2
*dynamic profile* named `honukai` with the Nerd Font, and makes it the
default profile. iTerm2 picks the profile up live; setting it as default
only works while iTerm2 is closed — otherwise pick it under Settings →
Profiles → Other Actions → Set as Default. Colour changes go into the
`.itermcolors` file, then re-run `install.sh`.

On a Linux desktop pick any true-colour terminal (e.g. Ghostty, WezTerm,
Kitty, GNOME Terminal) and set the font to *JetBrainsMono Nerd Font Mono*;
the iTerm2 profile is macOS-only.

## Daily workflow

```bash
dev path/to/some-repo
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
| `.gitconfig` | Aliases (`st`, `lg`, `undo`, `psf`, `cln`, …), delta pager, zdiff3 conflicts, rebase-on-pull, credential helper per OS via `~/.gitconfig-os`. Repos under the work directory named in the `includeIf` (default `~/Development/aviam/`) get the work e-mail via `.gitconfig-aviam` — adjust both to your own layout and identity. |
| `.gitignore_global` | Ignore rules for every repo. |
| `claude/CLAUDE.md` | Global Claude Code rules shared by all repos (TDD, TS/React rules, code limits). Repo `AGENTS.md` files add specifics. |
| `claude/settings.json` | Claude Code user settings: permission allow/deny list and the hooks below. |
| `claude/hooks/guard-bash.sh` | PreToolUse: blocks `db:push`/`db:reset`/`db:seed`/`migrate:apply`, prisma/drizzle push & reset, destructive `psql`, `git --no-verify`. |
| `claude/hooks/format-file.sh` | PostToolUse: runs the project's Prettier (or ruff) on every file Claude edits. |
| `install.sh`, `install/` | Installer: `lib.sh` helpers, `macos.sh` (Homebrew/iTerm2), `linux.sh` + `linux-pkg.sh` (apt/dnf/pacman) + `upstream.sh` (tools into `~/.local`). |
| `test/` | `unit.sh` (helpers, no network), `lint.sh` (shellcheck), `linux.sh` (installs in Ubuntu/Debian/Fedora/Rocky/Arch containers and verifies; needs Docker, e.g. Colima). |
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
