#! /bin/bash

# Copyright (C) 2020 Google Inc.
#
# This file has been licensed under Apache 2.0 license.  Please see the LICENSE
# file at the root of the repository.

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
set -eo pipefail
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

# This is seriously weird: should I be guessing the OS and architecture to get
# at a binary that I want to use?
readonly _gotopt_binary="$(rlocation \
  gotopt2/cmd/gotopt2/gotopt2_/gotopt2)"

# Exit quickly if the binary isn't found. This may happen if the binary location
# moves internally in bazel.
if [ -x "$(command -v ${_gotopt2_binary})" ]; then
  echo "gotopt2 binary not found"
  exit 240
fi

GOTOPT2_OUTPUT=$($_gotopt_binary "${@}" <<EOF
flags:
- name: "container"
  type: string
  help: "The name of the container to run"
- name: "dir-reference"
  type: string
  help: "Some file in the current directory, e.g. the first file of inputs, for figuring out directories"
- name: "cd-to-dir-reference"
  type: bool
  help: "If set, the script will CD into the reference directory before executing the command."
- name: "scratch-dir"
  type: string
  help: "A docker expression host_dir:container_dir that will be mounted read-write"
- name : "source-dir"
  type: string
  help: "The absolute path to the source dir, used for mounting source files."
EOF
)
if [[ "$?" == "11" ]]; then
  # When --help option is used, gotopt2 exits with code 11.
  exit 1
fi

# Evaluate the output of the call to gotopt2, shell vars assignment is here.
eval "${GOTOPT2_OUTPUT}"

if [[ ${gotopt2_container} == "" ]]; then
  echo "Flag --container=... is required"
  exit 2
fi
if [[ ${gotopt2_dir_reference} == "" ]]; then
  echo "Flag --dir-reference=... is required"
  exit 3
fi

# These tricks are used to figure out what the real source and build root
# directories are, so that they could be made available to the running
# container command.

# Try to follow the symlinks of the input file as far as we can.  Once we're
# done, the directory that we're left with is the directory we need to mount
# in, i.e. the actual path to the source directory.
readonly _real_source_dir="$(dirname $(readlink -m ${gotopt2_dir_reference}))"

# This is the output directory (needs to be mounted writable).
readonly _output_dir="$(realpath $(dirname ${gotopt2_dir_reference}))"

# Figure out the bazel build root: using the knowledge that the build root
# seems to have the string "/_bazel_" at the beginning of the directory that
# is the user build root directory.
readonly _build_root="${PWD%%/_bazel_*}"

### HACK! HACK! HACK!
# User's home dir is usually here somewhere. We're assuming that the source
# code is checked out here.  If not, there will be... trouble.
#
# I think I can fix this, but it will take a bit of time.
readonly _home_dir="${_build_root%%.cache/*}"

# Required, so that the docker command runs as your UID:GID, so that the output
# file is created with your permissions.  Otherwise it will get created as
# owned by "root:root", and bazel will complain that the target didn't
readonly _uid="$(id -u)"
readonly _gid="$(id -g)"

readonly _cmdline="${gotopt2_args__[@]}"

_reference_dir="${PWD}"
if [[ "${gotopt2_cd_to_dir_reference}" == "true" ]]; then
  _reference_dir="${_output_dir}"
fi

_scratch_dir=""
if [[ "$gotopt2_scratch_dir" != "" ]]; then
  _scratch_dir="-v ${PWD}/${gotopt2_scratch_dir}:rw"
fi

_source_dir=""
if [[ "$gotopt2_source_dir" != "" ]]; then
  _source_dir ="-v ${gotopt2_source_dir}:${gotopt2_source_dir}"
fi

_xdg_dir="${_output_dir}/_xdg"

_runtime_dir="${_xdg_dir}/run/user"
mkdir -p "${_runtime_dir}"

_local_data_dir="${_xdg_dir}/local/data"
mkdir -p "${_local_data_dir}"

XDG_RUNTIME_DIR="${_runtime_dir}" \
XDG_DATA_HOME="${_local_data_dir}" \
/usr/bin/podman run --log-level=debug \
  --rm --interactive \
  -u "${_uid}:${_gid}" \
  -v "${_home_dir}:${_home_dir}:rw" \
  -v "${_real_source_dir}:${_real_source_dir}:ro" \
  -v "${_reference_dir}:/src" \
  ${_source_dir} \
  ${_scratch_dir} \
  -w "/src" \
  "${gotopt2_container}" \
    bash -c "${_cmdline}"

