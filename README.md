# Bazel rules for "build-in-docker" (or "bid")

[![Build](https://github.com/filmil/bazel-rules-bid/actions/workflows/build.yml/badge.svg)](https://github.com/filmil/bazel-rules-bid/actions/workflows/build.yml)
[![Tag and release](https://github.com/filmil/bazel-rules-bid/actions/workflows/tag-and-release.yml/badge.svg)](https://github.com/filmil/bazel-rules-bid/actions/workflows/tag-and-release.yml)


## What is "build-in-docker" (bid)?

Bid allows you to create a build rule that runs a *single* bazel build action inside a
Docker container.

## What is bid *not*?

* Bid is *different* from https://github.com/bazelbuild/rules_docker. Those are
Bazel rules for building containers.

* Bid is also *different* from running bazel from a container described at
https://bazel.build/install/docker-container. That is a way to run the *entire* bazel
build inside a docker container.


## Why bid?

This is a refactoring of a hack I did for https://github.com/filmil/bazel-ebook.

The ebook toolchain setup was very complex. It included installing plenty of
Python, pandoc and dependencies, which are notoriously hard to get right.

I worked around the whole issue by creating a Docker container which has a
regular Debian system with all the tools installed, and writing bazel rules that
invoke that container in build steps.


## How to use bid?

Declare it in your `MODULE.bazel` file.

```python
bazel_dep(
    name = "rules_bid",
    version = "0.3.0", # Select a version.
)
rules_bid_extension = use_extension(
    "@rules_bid//:extensions.bzl", "rules_bid_extension")
use_repo(rules_bid_extension, "gotopt2")
```

See the [example][ex] in Bazel-ebook on how to use it then.
Mostly you use the rule to prepend the appropriate docker command
line and container name to what you actually want to run in the
docker container.  The script takes care that all needed
directories are made available to the docker container when it
runs.

The first time you run the rule, it may take considerable time
for your container to get downloaded. Once it is, however, you
are good to go.

[ex]: https://github.com/filmil/bazel-ebook/blob/main/build/rules.bzl#L27
