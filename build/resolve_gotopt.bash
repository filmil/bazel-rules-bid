#! /usr/bin/env bash

# Prevent double sourcing.
[[ -n "${_LIB_RULES_BID_BUILD_RESOLVE_GOTOPT:-}" ]] && return 0
_LIB_RULES_BID_BUILD_RESOLVE_GOTOPT=1

function resolve_gotopt2() {
    if ! declare -F rlocation > /dev/null; then
        echo >&2 "rlocation function is required"
        exit 254
    fi

    _gotopt2_binary="$(rlocation rules_multitool++multitool+multitool_rules_bid/tools/gotopt2/gotopt2)"
    if [[ ${_gotopt2_binary} == "" ]]; then
        # For bazel v7.x.
        _gotopt2_binary="$(rlocation rules_multitool~~multitool~multitool_rules_bid/tools/gotopt2/gotopt2)"
    fi
    if [[ ! -x "${_gotopt2_binary}" ]]; then
        echo >&2 "gotopt2 binary not found; exiting"
        exit 240
    fi
    echo "${_gotopt2_binary}"
}

# vim: ft=bash

