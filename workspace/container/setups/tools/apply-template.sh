#!/usr/bin/env bash
# Render a template with Bash variable expansion.
# - Template: file path or '-' (stdin)
# - Output: stdout (default) or -o <target> (atomic when file)
# Safety: refuses unescaped $(...), backticks, or arithmetic $((...)) in template.
set -euo pipefail

usage() {
  echo "Usage: $0 [-o target_file] [template_file|-]" >&2
  exit 1
}

out=""
tmpl=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output) out=${2:?}; shift 2 ;;
    -h|--help) usage ;;
    -) tmpl="-" ; shift ;;
    *) tmpl="$1"; shift ;;
  esac
done

# Read template content (file or stdin)
if [[ -z "${tmpl:-}" || "$tmpl" == "-" ]]; then
  template_content=$(cat)
else
  [[ -f "$tmpl" ]] || { echo "Template not found: $tmpl" >&2; exit 1; }
  template_content=$(<"$tmpl")
fi

# Safety checks (allow \$(...) as literal, but block unescaped forms)
if grep -qE '(^|[^\\])\$\(|`|(^|[^\\])\$\(\(' <<<"$template_content"; then
  echo "Refusing: template contains command/arithmetic substitution (\$(...), \`...\`, or \$((...)))." >&2
  exit 2
fi

# Choose a unique heredoc delimiter to avoid collisions
DELIM="__RT_$(date +%s%N)__"

render() {
  # NOTE: $template_content is inserted literally into the heredoc.
  # Variable and default expansions happen when eval processes the heredoc.
  eval "cat <<$DELIM
$template_content
$DELIM
"
}

# Output to stdout or atomically into a file
if [[ -z "${out:-}" ]]; then
  render
else
  # expand leading ~ in target (common footgun when quoted)
  case $out in "~"|"~/"*) out=${out/#\~/$HOME} ;; esac
  dir=$(dirname -- "$out"); base=$(basename -- "$out")
  mkdir -p -- "$dir"
  tmp=$(mktemp -p "$dir" ".$base.XXXXXX") || { echo "mktemp failed" >&2; exit 1; }
  trap 'rm -f -- "$tmp"' EXIT
  render > "$tmp"
  mv -f -- "$tmp" "$out"
  trap - EXIT
fi
