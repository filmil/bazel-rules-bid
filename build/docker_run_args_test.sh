#! /usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
#
# Checks how docker_run.sh splits its command line (issue #61): its own
# flags come first, and the command, with any options of its own, reaches
# the container unchanged. A fake "docker" on PATH records the arguments of
# "docker run", so no container runtime is needed. docker_run.sh prefers
# docker over podman whenever docker is on PATH, so the fake is always used.
set -euo pipefail

# $1 is $(rootpath :docker_run), relative to the runfiles directory, the
# working directory of the test. Keep the runfiles path (no realpath), so
# docker_run.sh finds its own runfiles the way it does in a build.
readonly DOCKER_RUN="${PWD}/$1"

work="$(mktemp -d "${TEST_TMPDIR:-/tmp}/docker_run_args.XXXXXX")"
mkdir -p "${work}/bin"
cat > "${work}/bin/docker" <<'FAKE'
#! /usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "Docker version 0.0.0 (fake)"
  exit 0
fi
if [[ "$1" != "run" ]]; then
  echo "fake docker: unexpected subcommand $1" >&2
  exit 99
fi
# "docker run ... IMAGE bash -c CMD": record IMAGE and CMD.
args=("$@")
n=${#args[@]}
printf '%s\n' "${args[n-4]}" > "${FAKE_DOCKER_OUT}.image"
printf '%s\n' "${args[n-1]}" > "${FAKE_DOCKER_OUT}"
FAKE
chmod +x "${work}/bin/docker"
export PATH="${work}/bin:${PATH}"
export FAKE_DOCKER_OUT="${work}/cmd.txt"
touch "${work}/ref"

fail=0
pass() { echo "ok   $1"; }
flunk() {
  echo "FAIL $1"
  fail=1
}

run_docker_run() {
  rm -f "${FAKE_DOCKER_OUT}" "${FAKE_DOCKER_OUT}.image"
  (cd "${work}" && "${DOCKER_RUN}" "$@") >"${work}/out.txt" 2>&1
}

# expect_cmd NAME WANT ARGS...: docker_run.sh succeeds, and the container
# gets image example:tag and command WANT.
expect_cmd() {
  local name="$1" want="$2"
  shift 2
  if ! run_docker_run "$@"; then
    flunk "${name}: docker_run.sh exited nonzero: $(cat "${work}/out.txt")"
    return
  fi
  if [[ ! -f "${FAKE_DOCKER_OUT}" ]]; then
    flunk "${name}: docker run was never called"
    return
  fi
  local got image
  got="$(cat "${FAKE_DOCKER_OUT}")"
  image="$(cat "${FAKE_DOCKER_OUT}.image")"
  if [[ "${image}" != "example:tag" ]]; then
    flunk "${name}: container image was [${image}], want [example:tag]"
  elif [[ "${got}" != "${want}" ]]; then
    flunk "${name}: container command was [${got}], want [${want}]"
  else
    pass "${name}"
  fi
}

# expect_error NAME MESSAGE ARGS...: docker_run.sh fails with MESSAGE, and
# no container runs.
expect_error() {
  local name="$1" message="$2"
  shift 2
  if run_docker_run "$@"; then
    flunk "${name}: docker_run.sh succeeded"
  elif [[ -f "${FAKE_DOCKER_OUT}" ]]; then
    flunk "${name}: a container ran despite the error"
  elif ! grep -qF -- "${message}" "${work}/out.txt"; then
    flunk "${name}: no [${message}] in: $(cat "${work}/out.txt")"
  else
    pass "${name}"
  fi
}

own=(--container=example:tag "--dir-reference=${work}/ref")

# The issue #61 case: the wrapped command has options of its own.
expect_cmd "command options pass through" \
  "LD_LIBRARY_PATH=/x setEnvAndRunCmd.sh vivado -notrace -mode batch -source synth.tcl" \
  "${own[@]}" LD_LIBRARY_PATH=/x setEnvAndRunCmd.sh vivado -notrace -mode batch -source synth.tcl

# "--" ends the own flags, even before a command word that starts with "-".
expect_cmd "double dash separates" \
  "--weird-command-word -x" \
  "${own[@]}" -- --weird-command-word -x

# Only the first "--" is ours; a later one belongs to the command.
expect_cmd "later double dash stays" \
  "tool -- --arg" \
  "${own[@]}" tool -- --arg

# An option after the command word belongs to the command, even when it
# looks like one of our own flags.
expect_cmd "long option after command" \
  "tool --container=not-ours --verbose" \
  "${own[@]}" tool --container=not-ours --verbose

# Own flags the parser does not know are errors, with one dash or two,
# and with or without a value.
expect_error "unknown own flag" "Unknown flag: --no-such-flag" \
  "${own[@]}" --no-such-flag=1 tool
expect_error "unknown own flag, no value" "Unknown flag: --no-such-flag" \
  "${own[@]}" --no-such-flag -- tool
expect_error "single-dash typo" "Unknown flag: -container=x" \
  "${own[@]}" -container=x tool

# Own flags take --name=value; a separate value is an error, not a command.
expect_error "space-separated own flag" "Unknown flag: --container" \
  --container example:tag "--dir-reference=${work}/ref" tool

# --help still prints the usage and exits 0, running nothing.
if run_docker_run --help; then
  if [[ -f "${FAKE_DOCKER_OUT}" ]]; then
    flunk "--help: a container ran"
  elif ! grep -qF -- "--container" "${work}/out.txt"; then
    flunk "--help: no usage text: $(cat "${work}/out.txt")"
  else
    pass "--help prints the usage"
  fi
else
  flunk "--help: exited nonzero: $(cat "${work}/out.txt")"
fi

exit "${fail}"
