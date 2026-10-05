# Linux-Support für `install.sh` — Design

Stand: 2026-10-05 · Status: freigegeben (Gespräch), Spec zur Review

## Ziel

`git clone … && ./install.sh` richtet das Setup (Neovim + tmux + Claude Code,
zsh, Configs) auf Linux genauso ein wie heute auf macOS — auf Desktop-Rechnern
ebenso wie auf Servern/WSL2. Der macOS-Pfad verhält sich danach unverändert.

**Erfolgskriterien**

- `./install.sh` läuft auf Ubuntu 24.04, Debian 13, Fedora (aktuell) und Arch
  ohne manuelle Nacharbeit durch (abgesehen von `sudo`-Passwort,
  `gh auth login`, `claude`-Login).
- Danach: `nvim` ≥ 0.11, `fzf` ≥ 0.48, alle Symlinks gesetzt, zsh ist
  Login-Shell, `nvim --headless "+Lazy! sync" +qa` fehlerfrei, Mason-Pakete
  installiert.
- Zweiter Lauf ist idempotent (nur „already …“-Meldungen) — auf Linux und macOS.

## Rahmenbedingungen

- Unterstützte Paketmanager: **apt** (Debian/Ubuntu und Derivate), **dnf**
  (Fedora/RHEL-Familie), **pacman** (Arch und Derivate). Erkennung über `ID`
  und `ID_LIKE` aus `/etc/os-release`; alles andere bricht mit klarer Meldung ab.
- Architekturen: x86_64 und aarch64.
- Nichts wird gepinnt — wie bisher holt jeder Installer die aktuelle Version.
- `sudo` nur für native Pakete und `chsh`; alles Upstream landet ohne Root in
  `~/.local`.

## Nicht im Umfang

- Installation oder Konfiguration einer Linux-Terminal-App (inkl.
  Honukai-Farben dafür). Es gibt nur einen Hinweis auf true-colour.
- Weitere Paketmanager (zypper, apk, nix …).
- Änderungen an `nvim/`, `.tmux.conf`, `claude/` — diese sind bereits
  plattformneutral.

## Architektur

```
install.sh            Einstieg: OS erkennen, Module laden, gemeinsamen Ablauf ausführen
install/lib.sh        Helfer: info/ok/warn, link, ensure_line, set_zsh_theme (portabel),
                      version_ge, ensure_min_version
install/macos.sh      platform_packages, platform_gui, platform_finish (heutiger Mac-Code)
install/linux.sh      platform_packages, platform_gui, platform_finish für Linux
install/linux-pkg.sh  Paketmanager-Erkennung + Namens-Tabelle (apt/dnf/pacman)
install/upstream.sh   Downloads nach ~/.local (neovim, fzf, lazygit, delta,
                      tree-sitter, node, pnpm, pdm)
```

Jedes Plattform-Modul definiert dieselben drei Funktionen; `install.sh` ruft
sie in fester Reihenfolge auf:

1. `platform_packages` — CLI-Tooling installieren
2. gemeinsam: oh-my-zsh, honukai + `ZSH_THEME`, Claude Code
3. `platform_gui` — Fonts/Terminal (Mac: iTerm2, Nerd Font, `duti`, Profil;
   Linux: Nerd Font nur bei GUI-Session)
4. gemeinsam: Symlinks, Git-OS-Include, `.zshrc`-Zeilen, Neovim-Plugins,
   Treesitter, Mason
5. `platform_finish` — Abschlussmeldung (Linux: plus `chsh` auf zsh)

Der macOS-Code wird nur verschoben, nicht umgeschrieben. Einzige inhaltliche
Änderung dort: `sed -i ''` in `set_zsh_theme` wird durch „in Temp-Datei
schreiben, dann `mv`“ ersetzt (funktioniert mit BSD- und GNU-sed).

## Linux: Pakete in zwei Schichten

### Schicht 1 — nativ (mit sudo)

Logische Namen → Paketnamen je Manager:

| logisch | apt | dnf | pacman |
|---|---|---|---|
| zsh, git, curl, unzip, tar, jq, tmux, lsof | gleichnamig | gleichnamig | gleichnamig |
| ripgrep | ripgrep | ripgrep | ripgrep |
| zoxide | zoxide | zoxide | zoxide |
| C-Toolchain (Treesitter) | build-essential | gcc make | base-devel |
| python3 | python3 python3-venv | python3 | python |
| gh | gh (offizielles GitHub-apt-Repo) | gh | github-cli |
| fontconfig (nur GUI) | fontconfig | fontconfig | fontconfig |

Ein Durchlauf pro Manager (`apt-get update && apt-get install -y …`,
`dnf install -y …`, `pacman -S --needed --noconfirm …`); bereits installierte
Pakete werden vom Manager selbst übersprungen.

### Schicht 2 — Upstream nach `~/.local` (ohne sudo)

`ensure_min_version <bin> <min-version> <install-fn>`: Ist das Binary
vorhanden und neu genug, passiert nichts; sonst wird `install-fn` aufgerufen.
Nicht-versionskritische Tools ohne Distro-Paket nutzen Mindestversion `0`.

| Tool | Mindestversion | Quelle |
|---|---|---|
| neovim | 0.11 | offizieller Release-Tarball → `~/.local/opt/nvim`, Link `~/.local/bin/nvim` |
| fzf | 0.48 (`fzf --zsh`) | GitHub-Release-Binary → `~/.local/bin` |
| lazygit | 0 | GitHub-Release-Binary |
| delta | 0 | GitHub-Release-Binary |
| tree-sitter | 0 | GitHub-Release-Binary (`tree-sitter-cli`) |
| node | 20 | offizieller LTS-Tarball → `~/.local/opt/node` |
| pnpm | 0 | offizieller Standalone-Installer (`get.pnpm.io`) |
| pdm | 0 | offizieller Installer (`pdm-project.org/install-pdm.py`) |

`~/.local/bin` wird über `ensure_line` in `~/.zprofile` (und `~/.profile`
für den ersten Login vor `chsh`) auf den `PATH` gesetzt; für `~/.local/opt/node/bin`
gilt dasselbe. Versionsauflösung „latest“ über die GitHub-Release-Redirects
(`…/releases/latest/download/<asset>`), wo Asset-Namen versionslos sind;
sonst über die Releases-API mit `jq`.

### Login-Shell

`platform_finish` setzt zsh per `chsh -s "$(command -v zsh)"`, wenn
`$SHELL` nicht schon zsh ist (fehlt der Pfad in `/etc/shells`, wird er mit
sudo ergänzt).

## Desktop vs. Server/WSL

GUI-Session = `$DISPLAY` oder `$WAYLAND_DISPLAY` gesetzt **und** kein WSL
(`/proc/version` enthält nicht `microsoft`). Nur dann:

- JetBrainsMono Nerd Font (GitHub-Release-Zip von `ryanoasis/nerd-fonts`) nach
  `~/.local/share/fonts/JetBrainsMonoNerdFont`, danach `fc-cache -f`.
- Hinweis: true-colour-Terminal mit „JetBrainsMono Nerd Font Mono“ verwenden.

Ohne GUI-Session wird beides übersprungen (Font und Farben gehören auf den Client).

## Git-Credentials

- `.gitconfig`: Block `[credential] helper = osxkeychain` entfällt, stattdessen
  `[include] path = ~/.gitconfig-os`.
- Neu `.gitconfig-macos` (`helper = osxkeychain`) und `.gitconfig-linux`
  (`helper = !gh auth git-credential`, funktioniert headless).
- `install.sh` linkt die passende Datei nach `~/.gitconfig-os`.

## Fehlerbehandlung

- `set -euo pipefail` bleibt; jeder Download mit `curl -fsSL`, Abbruch mit
  verständlicher Meldung bei fehlendem Asset für die Architektur.
- Unbekannte Distro/Architektur → Abbruch vor jeder Änderung.
- Läuft das Skript als root (z. B. Container), wird `sudo` weggelassen.

## Tests

- **shellcheck** über `install.sh`, `install/*.sh`, `test/*.sh`
  (lokal via `brew install shellcheck`).
- **`test/linux.sh`**: startet pro Image (`ubuntu:24.04`, `debian:13`,
  `fedora:latest`, `archlinux:latest`) einen Container, legt einen Nicht-root-
  User mit passwortlosem sudo an, kopiert das Repo hinein, führt
  `./install.sh` headless aus, dann `test/verify.sh`, dann `./install.sh`
  ein zweites Mal (Idempotenz: keine „installing“-/„backing up“-Zeilen).
- **`test/verify.sh`** prüft: nvim ≥ 0.11, fzf ≥ 0.48, alle erwarteten
  Symlinks zeigen ins Repo, `~/.gitconfig-os` passt zum OS, Login-Shell ist
  zsh, `nvim --headless "+Lazy! sync" +qa` mit Exit 0, Mason-Paketverzeichnisse
  vorhanden.
- Voraussetzung lokal: eine Docker-Runtime (z. B. OrbStack oder Colima) — auf
  diesem Mac aktuell nicht installiert.
- **macOS**: `./install.sh` erneut auf diesem Mac; erwartet nur „already …“-
  Meldungen, `git config credential.helper` liefert weiterhin `osxkeychain`.

## Dokumentation

README: Abschnitt „Install“ um Linux ergänzen (unterstützte Distros, sudo-
Bedarf, was nach `~/.local` geht, Desktop vs. headless, neues
`~/.gitconfig-os`), Tabelle „What's inside“ um `install/` und `test/`.
