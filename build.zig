const std = @import("std");
const Build = std.Build;

const APPS = .{"key"};

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tox = b.addModule("tox", .{
        .root_source_file = b.path("src/tox.zig"),
    });

    const ztest = b.addTest(.{
        .name = "test",
        .root_source_file = b.path("src/tox.zig"),
        .target = target,
        .optimize = optimize,
    });
    {
        const opt = b.addOptions();
        opt.addOption(bool, "skip_tests", false);
        ztest.root_module.addOptions("test_options", opt);
    }
    b.installArtifact(ztest);

    const run_test = b.addRunArtifact(ztest);

    const test_step = b.step("test", "test library");
    test_step.dependOn(&run_test.step);

    const ctest = b.addTest(.{
        .name = "ctest",
        .root_source_file = b.path("src/ctest.zig"),
        .target = target,
        .optimize = optimize,
    });
    if (b.lazyDependency("c-toxcore-build-with-zig", .{ .target = target, .optimize = optimize })) |c_toxcore_dep| {
        ctest.linkLibrary(c_toxcore_dep.artifact("c-toxcore"));
        ctest.addIncludePath(c_toxcore_dep.path("."));
    }
    {
        const opt = b.addOptions();
        opt.addOption(bool, "skip_tests", true);
        ctest.root_module.addOptions("test_options", opt);
    }
    b.installArtifact(ctest);

    const run_ctest = b.addRunArtifact(ctest);
    const ctest_step = b.step("ctest", "test library with c-toxcore");
    ctest_step.dependOn(&run_ctest.step);

    const all_apps_step = b.step("apps", "Build apps");
    inline for (APPS) |app_name| {
        const app = b.addExecutable(.{
            .name = app_name,
            .root_source_file = b.path("apps" ++ std.fs.path.sep_str ++ app_name ++ ".zig"),
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
