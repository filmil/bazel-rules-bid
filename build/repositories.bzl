# Copyright (C) 2020 Google Inc.
#
# This file has been licensed under Apache 2.0 license.  Please see the LICENSE
# file at the root of the repository.

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def bazel_bid_repositories():

    maybe(
        git_repository,
        name = "bazel_bats",
        remote = "https://github.com/filmil/bazel-bats",
        commit = "535f03ff9effd12694ff80d252375813e7ba9ae1",
        shallow_since = "1667200603 -0700",
    )

    # Find a way to remove this and take the repo from below.
    maybe(
        http_archive,
        name = "rules_pkg",
        urls = [
            "https://mirror.bazel.build/github.com/bazelbuild/rules_pkg/releases/download/0.9.1/rules_pkg-0.9.1.tar.gz",
            "https://github.com/bazelbuild/rules_pkg/releases/download/0.9.1/rules_pkg-0.9.1.tar.gz",
        ],
        sha256 = "8f9ee2dc10c1ae514ee599a8b42ed99fa262b757058f65ad3c384289ff70c4b8",
    )

    maybe(
        git_repository,
        name = "gotopt2",
        remote = "https://github.com/filmil/gotopt2",
        commit = "21c007a22bc51ec580510e5bed4f997f84362e0b",
    )

