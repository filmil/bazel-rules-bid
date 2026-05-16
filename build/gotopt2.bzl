def gotopt2_generate_bash(name, src, out):
    native.genrule(
        name = name,
        srcs = [src],
        outs = [out],
        tools = ["@gotopt2//cmd/gotopt2-generator"],
        cmd = "$(location @gotopt2//cmd/gotopt2-generator) < $< > $@",
    )
