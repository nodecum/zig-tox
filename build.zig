const std = @import("std");

const APPS = .{
    "key",
};

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

    const libsodium_dep = b.dependency(
        "libsodium",
        .{
            .target = target,
            .optimize = optimize,
            .static = true,
            .shared = false,
        },
    );

    const c_libsodium_lib = libsodium_dep.artifact("sodium");

    const tox = b.addModule("tox", .{
        .source_file = .{ .path = "src/tox.zig" },
    });

    const sodium = b.addModule("sodium", .{
        .source_file = .{ .path = "src/sodium.zig" },
    });

    const tox_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tox.zig" },
        .target = target,
        .optimize = optimize,
    });
    tox_tests.addModule("sodium", sodium);

    tox_tests.linkLibrary(c_libsodium_lib);
    const run_tox_tests = b.addRunArtifact(tox_tests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tox_tests.step);

    const all_apps_step = b.step("apps", "Build apps");
    inline for (APPS) |app_name| {
        const app = b.addExecutable(.{
            .name = app_name,
            .root_source_file = .{
                .path = "apps" ++ std.fs.path.sep_str ++ app_name ++ ".zig",
            },
            .target = target,
            .optimize = optimize,
        });
        app.addModule("sodium", sodium);
        app.addModule("tox", tox);

        app.linkLibrary(c_libsodium_lib);

        var run = b.addRunArtifact(app);
        if (b.args) |args| run.addArgs(args);
        b.step(
            "run-" ++ app_name,
            "Run the " ++ app_name ++ " app",
        ).dependOn(&run.step);

        all_apps_step.dependOn(&app.step);
    }
}
