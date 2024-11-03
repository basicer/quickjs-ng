const std = @import("std");

fn addDefines(c: *std.Build.Step.Compile, b: *std.Build) void {
    c.defineCMacro("CONFIG_BIGNUM", "1");
    c.defineCMacro("_GNU_SOURCE", "1");
    _ = b;
}

fn addStdLib(c: *std.Build.Step.Compile, cflags: []const []const u8) void {
    if (c.rootModuleTarget().os.tag == .wasi) {
        c.defineCMacro("_WASI_EMULATED_PROCESS_CLOCKS", "1");
        c.defineCMacro("_WASI_EMULATED_SIGNAL", "1");
        c.linkSystemLibrary("wasi-emulated-process-clocks");
        c.linkSystemLibrary("wasi-emulated-signal");
    }
    c.addCSourceFiles(.{ .files = &.{"quickjs-libc.c"}, .flags = cflags });
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const include_stdlib = b.option(bool, "stdlib", "include stdlib in library") orelse true;

    const cflags = &.{
        "-Wno-implicit-fallthrough",
        "-Wno-sign-compare",
        "-Wno-missing-field-initializers",
        "-Wno-unused-parameter",
        "-Wno-unused-but-set-variable",
        "-Wno-array-bounds",
        "-Wno-format-truncation",
        "-funsigned-char",
        "-fwrapv",
    };

    const libquickjs_source = &.{ "quickjs.c", "libregexp.c", "libunicode.c", "cutils.c", "libbf.c" };

    const libquickjs = b.addStaticLibrary(.{ .name = "quickjs", .target = target, .optimize = optimize });
    addDefines(libquickjs, b);
    libquickjs.addCSourceFiles(.{ .files = libquickjs_source, .flags = cflags });
    if (include_stdlib) {
        addStdLib(libquickjs, cflags);
    }
    libquickjs.linkLibC();
    libquickjs.installHeader(b.path("quickjs.h"), "quickjs.h");
    b.installArtifact(libquickjs);

    const qjsc = b.addExecutable(.{ .name = "qjsc", .target = target, .optimize = optimize });
    qjsc.addCSourceFiles(.{ .files = &.{"qjsc.c"}, .flags = cflags });
    qjsc.linkLibrary(libquickjs);
    addDefines(qjsc, b);
    if (!include_stdlib) {
        addStdLib(qjsc, cflags);
    }
    b.installArtifact(qjsc);

    const qjsc_host = b.addExecutable(.{
        .name = "qjsc-host",
        .target = b.host,
        .optimize = .Debug,
    });
    qjsc_host.addCSourceFiles(.{ .files = &.{"qjsc.c"}, .flags = cflags });
    qjsc_host.addCSourceFiles(.{ .files = libquickjs_source, .flags = cflags });
    addStdLib(qjsc_host, cflags);
    addDefines(qjsc_host, b);

    const gen_repl = b.addRunArtifact(qjsc_host);
    gen_repl.addArg("-o");
    const gen_repl_out = gen_repl.addOutputFileArg("repl.c");
    gen_repl.addArg("-m");
    gen_repl.addFileArg(b.path("repl.js"));

    const js = b.addWriteFiles();
    js.addCopyFileToSource(gen_repl_out, "gen/repl.c");

    const qjs = b.addExecutable(.{ .name = "qjs", .target = target, .optimize = optimize });
    qjs.addCSourceFiles(.{ .files = &.{ "qjs.c", "gen/repl.c" }, .flags = cflags });
    if (!include_stdlib) {
        addStdLib(qjs, cflags);
    }
    qjs.linkLibrary(libquickjs);
    addDefines(qjs, b);
    qjs.step.dependOn(&js.step);
    b.installArtifact(qjs);
}
