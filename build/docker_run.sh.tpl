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

# This is somewhat of a hack: we're trying to find the runfiles path of a binary
# whose location is with respect to its position in the dependency repo. So,
# strip 'external/' where it applies.
_binary_path="::GOTOPT2_BINARY::"
if [[ "${_binary_path}" == "external/"* ]]; then
    _binary_path="${_binary_path#external/}"
fi
readonly _gotopt2_binary="$(rlocation ${_binary_path})"


# Exit quickly if the binary isn't found. This may happen if the binary location
# moves internally in bazel.
if [[ ! -x "${_gotopt2_binary}" ]]; then
  echo "gotopt2 binary not found"
  exit 240
fi

GOTOPT2_OUTPUT=$($_gotopt2_binary "${@}" <<EOF
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
- name: "envs"
  type: stringlist
  help: "Comma-separated key value pairs for env variables."
- name: "mounts"
  type: stringlist
  help: "Comma-separated key value pairs for mounts."
- name: "tools"
  type: stringlist
  help: "Comma-separated list of tool files"
- name: "freeargs"
  type: stringlist
  help: "Comma-separated list of free flags to apply"
- name: "src-mount"
  type: string
  default: "/src"
  help: "The writable work directory to mount"
EOF
)
if [[ "$?" == "11" ]]; then
  # When --help option is used, gotopt2 exits with code 11.
  exit 0
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
# owned by "root:root", and bazel will complain.
readonly _uid="$(id -u)"
readonly _gid="$(id -g)"

readonly _cmdline="${gotopt2_args__[@]}"

_reference_dir="${PWD}"
if [[ "${gotopt2_cd_to_dir_reference}" == "true" ]]; then
  _reference_dir="${_output_dir}"
fi

_scratch_dir=""
_only_dir=""
if [[ "$gotopt2_scratch_dir" != "" ]]; then
  _stripped_pwd="${PWD%/}" # Strip trailing slash.
  _stripped_scratch="${gotopt2_scratch_dir#/}" # Strips heading slash.
  _scratch_dir="-v ${_stripped_pwd}/${_stripped_scratch}:rw"
  _only_dir="${_stripped_pwd}/${_stripped_scratch%:*}"
  # This apparently happens once in a while. Why? I don't know.
  if [[ ! -d "${_only_dir}" ]]; then
    mkdir -p "${_only_dir}"
  fi
  #echo --- AT BEGIN: "${_only_dir}"
  #ls -la "${_only_dir}" || echo "nothing?"
  #echo ---
fi

_source_dir=""
if [[ "$gotopt2_source_dir" != "" ]]; then
  _source_dir="-v ${gotopt2_source_dir}:${gotopt2_source_dir}"
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

# XXX: Does this slow things down too much?
sync
docker run --rm --interactive \
  -u "${_uid}:${_gid}" \
  -v "${_home_dir}:${_home_dir}:rw" \
  -v "${_real_source_dir}:${_real_source_dir}:ro" \
  -v "${_reference_dir}:${gotopt2_src_mount}" \
  -v "${_tools_dir}:/tools:ro" \
  ${_mounts[*]} \
  ${_envs[*]} \
  ${_source_dir} \
  ${_scratch_dir} \
  -w "${gotopt2_src_mount}" \
  ${_freeargs[*]} \
  "${gotopt2_container}" \
    bash -c "${_cmdline}"

#echo --- AT END  : "${_only_dir}"
#ls -la "${_only_dir}" || echo "nothing?"
#echo ---
