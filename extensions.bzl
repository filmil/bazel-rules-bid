load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
load("@bazel_tools//tools/build_defs/repo:git.bzl", "git_repository", "new_git_repository")
load("@bazel_tools//tools/build_defs/repo:utils.bzl", "maybe")

def _bazel_rules_bid_extension_impl(_ctx):
    maybe(
        http_archive,
        name = "gotopt2",
        integrity = "sha256-qFQjgqh4fnHet1UkV38bExd64Yk582iBUi9OrClJGJo=",
        urls = [
            "https://github.com/filmil/gotopt2/releases/download/v1.3.1/gotopt2-linux-amd64.zip",
        ],
        strip_prefix = "gotopt2",
        build_file_content = """package(default_visibility = ["//visibility:public"])
    filegroup(
        name = "bin",
        srcs = [ "gotopt2", ],
    )
    """
    )


bazel_rules_bid_extension = module_extension(
    implementation = _bazel_rules_bid_extension_impl,
)
