load("@bazel_rules_bid//build:rules.bzl", "run_docker_cmd")

_CONTAINER = "ubuntu:22.04"

def _impl(ctx):
    out_file = ctx.actions.declare_file("{}.txt".format(ctx.attr.name))
    docker_run = ctx.executable._docker_run
    script = ctx.executable._script
    mounts = {
        "/tmp/.X11-unix": "/tmp/.X11-unix:ro",
    }

    docker_runner = run_docker_cmd(
        container=_CONTAINER,
        script_path=docker_run.path,
        dir_reference=out_file.path,
        #source_dir=out_file.dirname,
        mounts=",".join([
            "{}:{}".format(k, v) for (k,v) in mounts.items()]),
        freeargs=[
          "--net=host",
          "-e", "HOME=/work",
        ],
    )
    args = [docker_runner]
    args += [script.path, out_file.path]
    #args += ["cat $(readlink -m bazel-out/k8-opt-exec-ST-d57f47055a04/bin/runme)"]
    #args += ["$(readlink -m bazel-out/k8-opt-exec-ST-d57f47055a04/bin/runme)"]

    ctx.actions.run_shell(
        inputs = [script],
        outputs = [out_file],
        tools = [script, docker_run],
        command = " ".join(args)
    )

    return [
        DefaultInfo(files = depset([out_file]))
    ]


genfile = rule(
    implementation = _impl,
    attrs = {
        "_script": attr.label(
            default = Label("//:runme"),
            executable = True,
            cfg = "host",
        ),
        "_docker_run": attr.label(
            default = Label("@bazel_rules_bid//build:docker_run"),
            executable = True,
            cfg = "host",
        ),
    },

)
