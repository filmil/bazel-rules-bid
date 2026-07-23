#! /usr/bin/env bash
# Copyright (C) 2020 Google Inc.

# This file has been licensed under Apache 2.0 license.  Please see the LICENSE
# file at the root of the repository.
#
#

# Runs a command line in the docker container.
#
# Example use:
#
#    ./docker_run.sh --dir-reference=some_file_which_is_a_reference \
#                    --container=some-container:tag \
#                        command arg1 arg2 arg3

# This magic was copied from runfiles by consulting:
#   https://stackoverflow.com/questions/53472993/how-do-i-make-a-bazel-sh-binary-target-depend-on-other-binary-targets

# --- begin runfiles.bash initialization ---
# Copy-pasted from Bazel's Bash runfiles library (tools/bash/runfiles/runfiles.bash).
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
set -eo pipefail

source "$(rlocation fshlib/log.bash)"
source "$(rlocation rules_bid/build/resolve_workspace.bash)"
source "$(rlocation rules_bid/build/docker_run_flags.bash)"

if [[ "${DEBUG}" == "true" ]]; then
  env | log::prefix "[env] "
  set -x
fi

# We don't want the script to exit on parse_args error, because we want to
# handle the --help exit code (11) specifically.
# Since parse_args calls 'exit 11' on --help, and it's a function, we must
# call it in a subshell to catch the exit code without exiting the script.
set +e
_parse_args_output=$(parse_args "${@}")
_parse_args_exit_code=$?
set -e

if [[ "${_parse_args_exit_code}" == "11" ]]; then
  # Help was requested and printed to stderr.
  exit 0
fi

if [[ "${_parse_args_exit_code}" != "0" ]]; then
  exit "${_parse_args_exit_code}"
fi

eval "${_parse_args_output}"

if [[ ${gotopt2_container} == "" ]]; then
  log::error "Flag --container=... is required"
  exit 2
fi
if [[ ${gotopt2_dir_reference} == "" ]]; then
  log::error "Flag --dir-reference=... is required"
  exit 3
fi

# These tricks are used to figure out what the real source and build root
# directories are, so that they could be made available to the running
# container command.

# This is the output directory (needs to be mounted writable).
readonly _output_dir="$(realpath $(dirname ${gotopt2_dir_reference}))"

readonly _run_dir="${PWD}"

# The Bazel output base, derived from the invariant execroot layout rather
# than from any assumption about where the output tree lives on disk. A
# build action always runs with its working directory set to the execroot,
# whose absolute path is
#     <output_base>/execroot/<workspace_name>
# Everything Bazel controls -- this execroot, the bazel-out tree beneath
# it, and external repositories under <output_base>/external -- lives under
# the output base, so mounting it exposes every input-symlink target and
# every declared output, writable, in the container. This works for the
# default ~/.cache/bazel/_bazel_<user>/... layout AND for any custom
# --output_user_root / --output_base. (The previous implementation
# string-matched "/bazel/_bazel_" and "/.cache/" against $PWD and silently
# synthesised a non-existent mount path -- e.g. <execroot>/bazel -- under
# any layout that did not contain those literal segments.)
readonly _output_base="${_run_dir%%/execroot/*}"

# The real source checkout: Bazel symlinks inputs into the execroot from
# the source tree, and the container must be able to follow those symlinks
# to their real host paths. Resolve the reference file through its symlink
# and walk up to the enclosing workspace root, so the checkout is found
# wherever it happens to live.
_source_root="$(resolve_workspace "$(readlink -m "${gotopt2_dir_reference}")")" \
    || _source_root=""
if [[ -z "${_source_root}" ]]; then
  # No workspace marker found above the reference: fall back to its real
  # directory so at least the immediate source files are visible.
  _source_root="$(dirname "$(readlink -m "${gotopt2_dir_reference}")")"
fi
readonly _source_root

# Required, so that the docker command runs as your UID:GID, so that the output
# file is created with your permissions.  Otherwise it will get created as
# owned by "root:root", and bazel will complain.
readonly _uid="$(id -u)"
readonly _gid="$(id -g)"

readonly _cmdline="${gotopt2_args__[@]}"

_only_dir=""
_scratch_dir=""
if [[ "$gotopt2_scratch_dir" != "" ]]; then
  _stripped_pwd="${PWD%/}" # Strip trailing slash.
  _stripped_scratch="${gotopt2_scratch_dir#/}" # Strips heading slash.
  _scratch_dir="-v ${_stripped_pwd}/${_stripped_scratch}:rw"
  _only_dir="${_stripped_pwd}/${_stripped_scratch%:*}"
  # Sometimes scratch_dir gets created with root ownership (?)
  log::debug "Creating dir: ${_only_dir}"
  mkdir -p "${_only_dir}" || xargs log::error
  chmod a+w "${_only_dir}" || true
fi

_envs=()
if [[ "${gotopt2_envs__list}" != "" ]]; then
  for one_env in ${gotopt2_envs__list[@]}; do
    _envs+=("-e" "${one_env}")
  done
fi

_mounts=()
if [[ "${gotopt2_mounts__list}" != "" ]]; then
  for one_mount in ${gotopt2_mounts__list[@]}; do
    _mounts+=("-v" "${one_mount}")
  done
fi

_freeargs=()
if [[ "${gotopt2_freeargs__list}" != "" ]]; then
  for one in ${gotopt2_freeargs__list[@]}; do
    _freeargs+=("${one}")
  done
fi

# ---- Container runtime detection and adaptation ----------------------
# Bazel actions run with a scrubbed environment ("env -").  Bash falls
# back to a built-in default PATH for its own command lookups, but child
# processes inherit the empty environment; rootless podman in particular
# execs helpers (conmon, nsenter, crun) that need PATH, and locates its
# state via HOME and XDG_RUNTIME_DIR.  Restore conventional values when
# they are missing; keep them when the caller provided them.
export PATH="${PATH:-/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
if [[ -z "${HOME:-}" ]]; then
  export HOME="$(getent passwd "$(id -u)" | cut -d: -f6)"
fi
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Prefer `docker` when present (it may legitimately be a shim for
# another runtime); fall back to `podman` on docker-less hosts.
if command -v docker >/dev/null 2>&1; then
  _container_cli="docker"
elif command -v podman >/dev/null 2>&1; then
  _container_cli="podman"
else
  echo "docker_run.sh: neither docker nor podman found in PATH" >&2
  exit 1
fi

# The two CLIs speak different flag dialects.  Rootless podman needs
# --userns=keep-id so output files land owned by the invoking user; the
# real docker CLI rejects that podman-only flag outright ("--userns:
# invalid USER mode") -- e.g. in CI setups where jobs get a docker CLI
# pointed at a podman socket.  Detect the flavor and adapt the free
# arguments, so callers do not need to know which runtime is installed.
if "${_container_cli}" --version 2>/dev/null | grep -qi podman; then
  _cli_flavor="podman"
else
  _cli_flavor="docker"
fi

_adapted_freeargs=()
for one in "${_freeargs[@]}"; do
  if [[ "${_cli_flavor}" == "docker" && \
        "${one}" == --userns=keep-id* ]]; then
    log::debug "dropping podman-only flag for docker CLI: ${one}"
    continue
  fi
  _adapted_freeargs+=("${one}")
done
_freeargs=("${_adapted_freeargs[@]}")
if [[ "${_cli_flavor}" == "podman" ]]; then
  case " ${_freeargs[*]-} " in
    *" --userns=keep-id"*) ;;
    *) _freeargs+=("--userns=keep-id") ;;
  esac
fi
# -----------------------------------------------------------------------

# Provide tools binaries here.
readonly _tools_dir="$(mktemp -d --tmpdir=${_output_dir} tools-XXXXXX)"
if [[ "${#gotopt2_tools__list[@]}" != 0 ]]; then
  cp ${gotopt2_tools__list[@]} "${_tools_dir}"
fi

if [[ "${gotopt2_src_dir_hint}" != "" ]]; then
  readonly _src_dir="$(resolve_workspace ${gotopt2_src_dir_hint})"
  if [[ "${_src_dir}" != "" ]]; then
    _freeargs+=("-v" "${_src_dir}:${_src_dir}:ro")
  fi
fi

# This is a special concession to the new bazel runner.
readonly _github_runner_special="/home/runner/.bazel"
if [[ -d "${_github_runner_special}" ]]; then
  _freeargs+=(
    "-v"
    "${_github_runner_special}:${_github_runner_special}:rw"
  )
fi

# Mount the source tree only when it is not already covered by the output
# base mount, so podman/docker never sees two overlapping -v targets (an
# identical destination mounted twice is an error).
_source_mount=()
case "${_source_root}/" in
  "${_output_base}/"*) : ;;  # already inside the output base mount
  *) _source_mount=(-v "${_source_root}:${_source_root}:rw") ;;
esac

# XXX: Does this slow things down too much?
sync
"${_container_cli}" run --rm --interactive \
  -u "${_uid}:${_gid}" \
  -v "${_output_base}:${_output_base}:rw" \
  "${_source_mount[@]}" \
  -v "${_tools_dir}:/tools:ro" \
  ${_mounts[*]} \
  ${_envs[*]} \
  ${_scratch_dir} \
  -w "${_run_dir}" \
  ${_freeargs[*]} \
  "${gotopt2_container}" \
    bash -c "${_cmdline}"

if [[ "${_only_dir}" != "" ]]; then
  log::debug "Setting ownership: ${_only_dir}"
  chmod a+w "${_only_dir}"
fi

# vim: filetype=bash
