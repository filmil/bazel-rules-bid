#! /usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks that :resolve still provides resolve_gotopt.bash and the gotopt2
# binary it finds, as rules_vivado's pnr.bash expects (issue 63): pnr.bash
# sources the file by its runfiles path, calls resolve_gotopt2, and feeds
# the binary a flag spec on stdin.

# --- begin runfiles.bash initialization ---
if [[ ! -d "${RUNFILES_DIR:-/dev/null}" && ! -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  if [[ -f "$0.runfiles_manifest" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles_manifest"
  elif [[ -f "$0.runfiles/MANIFEST" ]]; then
    export RUNFILES_MANIFEST_FILE="$0.runfiles/MANIFEST"
  elif [[ -f "$0.runfiles/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
    export RUNFILES_DIR="$0.runfiles"
  fi
fi
if [[ -f "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" ]]; then
  source "${RUNFILES_DIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
elif [[ -f "${RUNFILES_MANIFEST_FILE:-/dev/null}" ]]; then
  source "$(grep -m1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " \
            "$RUNFILES_MANIFEST_FILE" | cut -d ' ' -f 2-)"
else
  echo >&2 "ERROR: cannot find @bazel_tools//tools/bash/runfiles:runfiles.bash"
  exit 1
fi
# --- end runfiles.bash initialization ---
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
