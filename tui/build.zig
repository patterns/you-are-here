const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // Declare package dependency 
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const giza_dep = b.dependency("giza", .{
        .target = target,
        .optimize = optimize,
    });
    // Declare dependency's module with the name from its build script
    const vaxis_module = vaxis_dep.module("vaxis");
    const cairo_module = giza_dep.module("cairo");
////    const pango_module = giza_dep.module("pango");
////    const pangocairo_module = giza_dep.module("pangocairo");

    const lib = b.addStaticLibrary(.{
        .name = "mapsy",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(b.path("src"));
    lib.linkLibC();
    lib.linkLibCpp();
    lib.linkSystemLibrary("s2");
    lib.addCSourceFile(.{ .file = b.path( "src/bindings.cc" )});
    lib.root_module.addImport("cairo", cairo_module);
////    lib.root_module.addImport("pango", pango_module);
////    lib.root_module.addImport("pangocairo", pangocairo_module);
    lib.linkSystemLibrary("cairo");


    // Module
    const mapsy_mod = b.addModule("mapsy", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    mapsy_mod.addIncludePath(b.path("src"));
    mapsy_mod.addCSourceFile(.{ .file = b.path( "src/bindings.cc" )});
    mapsy_mod.addImport("cairo", cairo_module);
////    mapsy_mod.addImport("pango", pango_module);
////    mapsy_mod.addImport("pangocairo", pangocairo_module);
    mapsy_mod.linkSystemLibrary("cairo", .{});

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "mapsy",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.addIncludePath(b.path("src"));
    exe.linkLibC();
    exe.linkLibCpp();
    exe.linkSystemLibrary("s2");
    exe.root_module.addImport("mapsy", mapsy_mod);
    exe.root_module.addImport("cairo", cairo_module);
    exe.root_module.addImport("vaxis", vaxis_module);
////    exe.root_module.addImport("pango", pango_module);
////    exe.root_module.addImport("pangocairo", pangocairo_module);
    lib.linkSystemLibrary("cairo");


    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
