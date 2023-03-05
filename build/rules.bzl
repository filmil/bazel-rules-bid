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
def run_docker_cmd(container, script_path, dir_reference, scratch_dir=""):
    return """{script} \
--container={container} \
--dir-reference={dir_reference} \
--scratch-dir={scratch_dir}""".format(
            script=script_path,
            container=container,
            dir_reference=dir_reference,
            scratch_dir=scratch_dir,
       )

