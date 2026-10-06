# shellcheck shell=bash
# Minimal assertions for the installer tests: `check` passes when the command
# succeeds, `refute` when it fails.
FAILS=0

check() {
  if "${@:2}"; then printf 'ok   %s\n' "$1"; else printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); fi
}

refute() {
  if "${@:2}"; then printf 'FAIL %s\n' "$1"; FAILS=$((FAILS + 1)); else printf 'ok   %s\n' "$1"; fi
}

eq() {
  [ "$1" = "$2" ] || { printf '     expected [%s], got [%s]\n' "$2" "$1"; return 1; }
}

contains() {
  case " $1 " in *" $2 "*) return 0 ;; esac
  printf '     [%s] not in [%s]\n' "$2" "$1"
  return 1
}

finish_tests() {
  if [ "$FAILS" -eq 0 ]; then echo "all passed"; else echo "$FAILS failed"; exit 1; fi
}
