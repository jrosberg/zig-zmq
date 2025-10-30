//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "zmq_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });

    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zmq_test",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
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

    // PUB example executable
    const pub_exe = b.addExecutable(.{
        .name = "pub_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/pub_server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pub_exe.root_module.addImport("zmq", lib.root_module);
    b.installArtifact(pub_exe);

    const run_pub_cmd = b.addRunArtifact(pub_exe);
    run_pub_cmd.step.dependOn(b.getInstallStep());
    const run_pub_step = b.step("run-pub", "Run the PUB server example");
    run_pub_step.dependOn(&run_pub_cmd.step);

    // SUB example executable
    const sub_exe = b.addExecutable(.{
        .name = "sub_client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/sub_client.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sub_exe.root_module.addImport("zmq", lib.root_module);
    b.installArtifact(sub_exe);

    const run_sub_cmd = b.addRunArtifact(sub_exe);
    run_sub_cmd.step.dependOn(b.getInstallStep());
    const run_sub_step = b.step("run-sub", "Run the SUB client example");
    run_sub_step.dependOn(&run_sub_cmd.step);

    // REP example executable
    const rep_exe = b.addExecutable(.{
        .name = "rep_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/rep_server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    rep_exe.root_module.addImport("zmq", lib.root_module);
    b.installArtifact(rep_exe);

    const run_rep_cmd = b.addRunArtifact(rep_exe);
    run_rep_cmd.step.dependOn(b.getInstallStep());
    const run_rep_step = b.step("run-rep", "Run the REP server example");
    run_rep_step.dependOn(&run_rep_cmd.step);

    // Multi-connection PUB example executable
    const pub_multi_exe = b.addExecutable(.{
        .name = "pub_multi_server",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/pub_multi_server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pub_multi_exe.root_module.addImport("zmq", lib.root_module);
    b.installArtifact(pub_multi_exe);

    const run_pub_multi_cmd = b.addRunArtifact(pub_multi_exe);
    run_pub_multi_cmd.step.dependOn(b.getInstallStep());
    const run_pub_multi_step = b.step("run-pub-multi", "Run the multi-connection PUB server example");
    run_pub_multi_step.dependOn(&run_pub_multi_cmd.step);

    // Multi-connection SUB example executable
    const sub_multi_exe = b.addExecutable(.{
        .name = "sub_multi_client",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/sub_multi_client.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    sub_multi_exe.root_module.addImport("zmq", lib.root_module);
    b.installArtifact(sub_multi_exe);

    const run_sub_multi_cmd = b.addRunArtifact(sub_multi_exe);
    run_sub_multi_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_sub_multi_cmd.addArgs(args);
    }
    const run_sub_multi_step = b.step("run-sub-multi", "Run the multi-connection SUB client example");
    run_sub_multi_step.dependOn(&run_sub_multi_cmd.step);

    // Simple multi-connection example executable
    const simple_multi_exe = b.addExecutable(.{
        .name = "simple_multi",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/simple_multi.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    simple_multi_exe.root_module.addImport("zmq", lib.root_module);
    b.installArtifact(simple_multi_exe);

    const run_simple_multi_cmd = b.addRunArtifact(simple_multi_exe);
    run_simple_multi_cmd.step.dependOn(b.getInstallStep());
    const run_simple_multi_step = b.step("run-simple-multi", "Run the simple multi-connection example");
    run_simple_multi_step.dependOn(&run_simple_multi_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
