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

readonly _build_root="${PWD%%/_bazel_*}"
readonly _run_dir="${PWD}"
readonly _cache_dir="${PWD%%/bazel/_bazel_*}"
readonly _output_root="${_cache_dir}/bazel"

### HACK! HACK! HACK!
# User's home dir is usually here somewhere. We're assuming that the source
# code is checked out here.  If not, there will be... trouble.
#
# I think I can fix this, but it will take a bit of time.
readonly _home_dir="${_build_root%%/.cache/*}"

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

# XXX: Does this slow things down too much?
sync
docker run --rm --interactive \
  -u "${_uid}:${_gid}" \
  -v "${_output_root}:${_output_root}:rw" \
  -v "${_home_dir}:${_home_dir}:rw" \
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
