#!/usr/bin/env bash
# Merge JSON patch into a target file atomically using jq.
# Usage: json-merge.sh --into target.json [--with patch.json|-] [--strategy shallow|deep|replace] [--arrays replace|concat]
set -euo pipefail

into="" with="-" strategy="shallow" arrays="replace"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --into)     into=${2:?}; shift 2 ;;
    --with)     with=${2:?}; shift 2 ;;
    --strategy) strategy=${2:?}; shift 2 ;;
    --arrays)   arrays=${2:?}; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --into target.json [--with patch.json|-] [--strategy shallow|deep|replace] [--arrays replace|concat]"
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$into" ]] || { echo "--into is required" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

dir=$(dirname -- "$into"); base=$(basename -- "$into"); mkdir -p -- "$dir"

# Get patch JSON (stdin or file) into a temp file and validate
patch_tmp=$(mktemp -p "$dir" ".patch.$base.XXXXXX"); trap 'rm -f -- "$patch_tmp"' EXIT
if [[ "$with" == "-" ]]; then cat >"$patch_tmp"; else cp -- "$with" "$patch_tmp"; fi
jq -e . "$patch_tmp" >/dev/null  # validate/normalize input

# replace strategy or brand-new target → write patch as-is atomically
if [[ "$strategy" == "replace" || ! -f "$into" ]]; then
  tmp=$(mktemp -p "$dir" ".$base.XXXXXX")
  jq -e . "$patch_tmp" > "$tmp"
  mv -f -- "$tmp" "$into"; trap - EXIT; exit 0
fi

# validate base JSON
jq -e . "$into" >/dev/null

tmp=$(mktemp -p "$dir" ".$base.XXXXXX")
case "$strategy" in
  shallow) jq -s '.[0] + .[1]' "$into" "$patch_tmp" > "$tmp" ;;
  deep)
    if [[ "$arrays" == "concat" ]]; then
      jq -s '
        def deepmerge(a;b):
          if (a|type)=="object" and (b|type)=="object" then
            reduce (((a|keys_unsorted)+(b|keys_unsorted))|unique[]) as $k
              ({}; .[$k] = deepmerge(a[$k]; b[$k]))
          elif (a|type)=="array" and (b|type)=="array" then a + b
          else b end;
        deepmerge(.[0]; .[1])
      ' "$into" "$patch_tmp" > "$tmp"
    else
      jq -s '
        def deepmerge(a;b):
          if (a|type)=="object" and (b|type)=="object" then
            reduce (((a|keys_unsorted)+(b|keys_unsorted))|unique[]) as $k
              ({}; .[$k] = deepmerge(a[$k]; b[$k]))
          elif (a|type)=="array" and (b|type)=="array" then b
          else b end;
        deepmerge(.[0]; .[1])
      ' "$into" "$patch_tmp" > "$tmp"
    fi ;;
  *) echo "Unknown strategy: $strategy" >&2; rm -f -- "$tmp"; exit 1 ;;
esac
mv -f -- "$tmp" "$into"; trap - EXIT
