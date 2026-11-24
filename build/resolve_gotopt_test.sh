#! /usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks that :resolve still provides resolve_gotopt.bash and the gotopt2
# binary it finds, as rules_vivado's pnr.bash expects (issue 63): pnr.bash
# sources the file by its runfiles path, calls resolve_gotopt2, and feeds
# the binary a flag spec on stdin.

# --- begin runfiles.bash initialization v3 ---
# Copy-pasted from the Bazel Bash runfiles library v3.
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  { echo>&2 "ERROR: cannot find $f"; exit 1; }; f=; set -e
# --- end runfiles.bash initialization v3 ---
set -euo pipefail

# The same line as rules_vivado's build/vivado/pnr.bash.
source "$(rlocation rules_bid/build/resolve_gotopt.bash)"

gotopt2="$(resolve_gotopt2)"
if [[ ! -x "${gotopt2}" ]]; then
  echo "FAIL: resolve_gotopt2 gave [${gotopt2}], not an executable"
  exit 1
fi

# Parse one flag the way pnr.bash does: the spec on stdin, the args after.
out="$("${gotopt2}" --work_dir=/tmp/x <<'SPEC'
flags:
- name: "work_dir"
  type: string
  help: "A test flag"
SPEC
)"
# pnr.bash evaluates this output; do the same and check the variable.
eval "${out}"
if [[ "${gotopt2_work_dir:-}" != "/tmp/x" ]]; then
  echo "FAIL: gotopt2_work_dir is [${gotopt2_work_dir:-}], want [/tmp/x]; output: ${out}"
  exit 1
fi
echo "ok: resolve_gotopt2 found ${gotopt2}, and it parses flags"
