const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "pheap-runtime",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addIncludePath(b.path("c"));
    exe.addIncludePath(b.path("kernels"));

    exe.linkSystemLibrary("crypto");
    
    if (target.result.os.tag == .linux) {
        exe.linkSystemLibrary("pthread");
        exe.linkSystemLibrary("dl");
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the application");
    run_step.dependOn(&run_cmd.step);

    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.linkLibC();
    lib_tests.addIncludePath(b.path("c"));
    lib_tests.addIncludePath(b.path("kernels"));
    lib_tests.linkSystemLibrary("crypto");

    const run_lib_unit_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const cli_tool = b.addExecutable(.{
        .name = "pheap-tool",
        .root_source_file = b.path("tools/inspect.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_tool.linkLibC();
    cli_tool.addIncludePath(b.path("c"));
    cli_tool.linkSystemLibrary("crypto");
    b.installArtifact(cli_tool);

    const repair_tool = b.addExecutable(.{
        .name = "pheap-repair",
        .root_source_file = b.path("tools/repair.zig"),
        .target = target,
        .optimize = optimize,
    });
    repair_tool.linkLibC();
    repair_tool.addIncludePath(b.path("c"));
    repair_tool.linkSystemLibrary("crypto");
    b.installArtifact(repair_tool);

    const benchmark_tool = b.addExecutable(.{
        .name = "pheap-bench",
        .root_source_file = b.path("src/benchmark.zig"),
        .target = target,
        .optimize = optimize,
    });
    benchmark_tool.linkLibC();
    benchmark_tool.addIncludePath(b.path("c"));
    benchmark_tool.linkSystemLibrary("crypto");
    b.installArtifact(benchmark_tool);

    const crash_test = b.addExecutable(.{
        .name = "pheap-crash-test",
        .root_source_file = b.path("test/crash_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    crash_test.linkLibC();
    crash_test.addIncludePath(b.path("c"));
    crash_test.linkSystemLibrary("crypto");
    b.installArtifact(crash_test);
}
