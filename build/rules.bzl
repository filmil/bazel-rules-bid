# Copyright (C) 2020 Google Inc.
#
# This file has been licensed under Apache 2.0 license.  Please see the LICENSE
# file at the root of the repository.

# Returns the docker_run script invocation command based on the
# script path and its reference directory.
#
# Params:
#   container: (string) container to run
#   script_path: (string) The full path to the script to invoke
#   dir_reference: (string) The path to a file used for figuring out
#       the reference directories (build root and repo root).
#   source_dir: (string) The absolute path of the source tree location in
#       the host's filesystem.
def run_docker_cmd(
    container,
    script_path,
    dir_reference,
    scratch_dir="",
    source_dir="",
    mounts=None,
    envs=None,
    tools=None,
    freeargs=[],
    workdir_name=None,
    source_dir_hint=None
):

    ret = """{script} \
--container={container} \
--dir-reference={dir_reference} \
--source-dir={source_dir} \
--scratch-dir={scratch_dir}""".format(
            script=script_path,
            container=container,
            dir_reference=dir_reference,
            scratch_dir=scratch_dir,
            source_dir=source_dir,
       )
    if mounts:
        ret += " --mounts={}".format(mounts)
    if envs:
        ret += " --envs={}".format(envs)
    if tools:
        ret += " --tools={}".format(tools)
    if freeargs:
        ret += " --freeargs={}".format(",".join(freeargs))
    if workdir_name:
        ret += " --src-mount={}".format(workdir_name)
    if source_dir_hint:
        ret += " --src-dir-hint={}".format(source_dir_hint)

    return ret

