load("@bazel_rules_bid//build:rules.bzl", "run_docker_cmd")

_CONTAINER = "ubuntu:22.04"

def _impl(ctx):
    out_file = ctx.actions.declare_file("{}.txt".format(ctx.attr.name))
    log_file = ctx.actions.declare_file("{}.log".format(ctx.attr.name))
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
    args += [
        "2>&1 >{log} || ( cat {log} && exit 1)".format(
        log=log_file.path)]

    ctx.actions.run_shell(
        mnemonic = "GEN",
        progress_message = "Generating: {}".format(
            out_file.short_path),
        inputs = [script],
        outputs = [out_file, log_file],
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
