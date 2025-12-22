#!/bin/bash
# Common utilities for unit tests

script_relative_path() {
  local script_abs="${1:-$0}"
  local root="${PROJECT_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
  script_abs=$(realpath "$script_abs")
  root=$(realpath "$root")
  echo "${script_abs#${root}/tests/}"
}
