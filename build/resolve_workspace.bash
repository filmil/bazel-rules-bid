#! /bin/bash

# Prevent double sourcing.
[[ -n "${_LIB_RULES_BID_BUILD_RESOLVE_WORKSPACE:-}" ]] && return 0
_LIB_RULES_BID_BUILD_RESOLVE_WORKSPACE=1

# Tries to find the most likely workspace.
function resolve_workspace() {
    local target="${1:-$PWD}"
    local top_workspace=""

    # Resolve symlinks and get absolute path
    target=$(readlink -m "$target")

    # If the target is a file, start from its parent directory
    if [[ ! -d "$target" ]]; then
        local current_dir=$(dirname "$target")
    else
        local current_dir="$target"
    fi

    while true; do
        # Check for any valid Bazel workspace markers
        if [[ -a "$current_dir/WORKSPACE" || \
              -a "$current_dir/WORKSPACE.bazel" || \
              -a "$current_dir/MODULE" || \
              -a "$current_dir/MODULE.bazel" || \
              -a "$current_dir/REPO.bazel" ]]; then
            top_workspace="$current_dir"
        fi

        # Stop if we hit the root
        [[ "$current_dir" == "/" ]] && break
        current_dir=$(dirname "$current_dir")
    done

    if [[ -n "$top_workspace" ]]; then
        echo "$top_workspace"
        return 0
    else
        return 1
    fi
}

# vim: ft=bash :
