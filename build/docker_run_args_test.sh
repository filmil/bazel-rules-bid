#! /usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks how docker_run.sh splits its command line (issue #61): its own
# "--" flags come first, and the command, with any options of its own,
# reaches the container unchanged. A fake "docker" on PATH records the
# arguments of "docker run", so no container runtime is needed.
set -euo pipefail

readonly DOCKER_RUN="$(realpath "$1")"

work="$(mktemp -d "${TEST_TMPDIR:-/tmp}/docker_run_args.XXXXXX")"
mkdir -p "${work}/bin"
cat > "${work}/bin/docker" <<'FAKE'
#! /usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "Docker version 0.0.0 (fake)"
  exit 0
fi
# The last argument of "docker run ... IMAGE bash -c CMD" is CMD.
printf '%s\n' "${@: -1}" > "${FAKE_DOCKER_OUT}"
FAKE
chmod +x "${work}/bin/docker"
export PATH="${work}/bin:${PATH}"
export FAKE_DOCKER_OUT="${work}/cmd.txt"
touch "${work}/ref"

fail=0
expect_cmd() {
  local name="$1" want="$2"
  shift 2
  rm -f "${FAKE_DOCKER_OUT}"
  if ! (cd "${work}" && "${DOCKER_RUN}" "$@") >"${work}/out.txt" 2>&1; then
    echo "FAIL ${name}: docker_run.sh exited nonzero:"
    cat "${work}/out.txt"
    fail=1
    return
  fi
  local got
  got="$(cat "${FAKE_DOCKER_OUT}")"
  if [[ "${got}" != "${want}" ]]; then
    echo "FAIL ${name}: container command was [${got}], want [${want}]"
    fail=1
  else
    echo "ok   ${name}"
  fi
}

own=(--container=example:tag "--dir-reference=${work}/ref")

# The issue #61 case: the wrapped command has options of its own.
expect_cmd "command options pass through" \
  "LD_LIBRARY_PATH=/x setEnvAndRunCmd.sh vivado -notrace -mode batch -source synth.tcl" \
  "${own[@]}" LD_LIBRARY_PATH=/x setEnvAndRunCmd.sh vivado -notrace -mode batch -source synth.tcl

# "--" ends the own flags, even before a command that starts with "--".
expect_cmd "double dash separates" \
  "--weird-command-word -x" \
  "${own[@]}" -- --weird-command-word -x

# A "--" option after the first command word belongs to the command.
expect_cmd "long option after command" \
  "tool --container=not-ours --verbose" \
  "${own[@]}" tool --container=not-ours --verbose

# An own flag that docker_run.sh does not know is still an error.
rm -f "${FAKE_DOCKER_OUT}"
if (cd "${work}" && "${DOCKER_RUN}" "${own[@]}" --no-such-flag=1 tool) >"${work}/out.txt" 2>&1; then
  echo "FAIL unknown own flag: docker_run.sh accepted --no-such-flag"
  fail=1
elif ! grep -q "Unknown flag: --no-such-flag" "${work}/out.txt"; then
  echo "FAIL unknown own flag: no 'Unknown flag' message:"
  cat "${work}/out.txt"
  fail=1
else
  echo "ok   unknown own flag is rejected"
fi

exit "${fail}"
