#! /usr/bin/env bash
# Copyright (C) 2020 Google Inc.

# vim: filetype=bash

function resolve_gotopt2() {
    _gotopt2_binary="$(rlocation rules_multitool++multitool+multitool/tools/gotopt2/gotopt2)"
    if [[ "${_gotopt2_binary}" == "" ]]; then
      _gotopt2_binary="$(rlocation rules_multitool~~multitool~multitool/tools/gotopt2/gotopt2)"
    fi
    if [[ ! -f "${_gotopt2_binary}" ]]; then
      echo "gotopt2 binary not found; exiting"
      exit 240
    fi
    echo "${_gotopt2_binary}"
}
