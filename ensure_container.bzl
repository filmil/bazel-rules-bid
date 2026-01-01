load("@rules_bt//:repo.bzl", "bt_file")


def _ensure_container_impl(rctx):
    image = rctx.attr.image

    # Run the docker command
    res = rctx.execute(["docker", "images", "-q", image])

    if res.return_code == 0 and res.stdout.strip():
        # Image is available locally; skip download logic
        rctx.file("WORKSPACE", "")
        rctx.file("BUILD", "exports_files(['metadata.json'])")
        rctx.file("metadata.json", '{"status": "local", "image": "%s"}' % image)
        print("Image %s found locally, skipping download." % image)
    else:
        print("Image %s not found. Proceeding with download..." % image)
        bt_file(
            name = rctx.attr.name,
            uri = rctx.attr.uri,
        )
        file_path = rctx.path(Label("{}//:file".format(rctx.attr.name)))
        res = rctx.execute(["docker", "load", "--input={}".format(file_path)])
        if res.return_code:
            fail("could not load the container: {}".format(rctx.attr.uri))

        rctx.file("WORKSPACE", "")
        rctx.file("BUILD", "exports_files(['metadata.json'])")
        rctx.file("metadata.json", '{"status": "local", "image": "%s"}' % image)


ensure_container = repository_rule(
    implementation = _ensure_container_impl,
    attrs = {
        "image": attr.string(mandatory = True),
        "uri": attr.string(mandatory = True),
    },
    local = True, # Ensures the rule can run local commands
)

