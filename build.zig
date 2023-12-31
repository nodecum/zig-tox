const std = @import("std");
const Build = std.Build;

const APPS = .{
    "key",
};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const c_toxcore_dep = b.dependency(
        "c-toxcore",
        .{
            .target = target,
            .optimize = optimize,
            .static = true,
            .shared = false,
        },
    );
    const c_toxcore_lib = c_toxcore_dep.artifact("toxcore");
    const tox = b.addModule("tox", .{
        .root_source_file = .{ .path = "src/tox.zig" },
    });

    const tox_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tox.zig" },
        .target = target,
        .optimize = optimize,
    });
    tox_tests.linkLibrary(c_toxcore_lib);
    tox_tests.addIncludePath(c_toxcore_dep.path("."));

    b.installArtifact(tox_tests);

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
        app.root_module.addImport("tox", tox);

        var run = b.addRunArtifact(app);
        if (b.args) |args| run.addArgs(args);
        b.step(
            "run-" ++ app_name,
            "Run the " ++ app_name ++ " app",
        ).dependOn(&run.step);

        all_apps_step.dependOn(&app.step);
    }
}
