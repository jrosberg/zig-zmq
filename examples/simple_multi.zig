//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");
const zmq = @import("zmq");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("=== Simple Multiple Connections Example ===\n\n", .{});

    // Create context
    const ctx = try zmq.Context.init(allocator);
    defer ctx.deinit();

    // Create PUB socket
    const sock = try ctx.socket(.PUB);
    defer sock.close();

    // Bind to endpoint
    std.debug.print("Binding to tcp://*:5556...\n", .{});
    try sock.bind("tcp://*:5556");

    // Accept 3 connections
    std.debug.print("Accepting connections...\n", .{});
    std.debug.print("Start 3 SUB clients now within 5 seconds...\n", .{});

    // Wait for user to start clients
    std.Thread.sleep(5 * std.time.ns_per_s);

    // Accept connections
    std.debug.print("\nAccepting connection #1...\n", .{});
    try sock.accept();

    std.debug.print("Accepting connection #2...\n", .{});
    try sock.accept();

    std.debug.print("Accepting connection #3...\n", .{});
    try sock.accept();

    std.debug.print("\n{d} connections established!\n\n", .{sock.connectionCount()});

    // Send messages to all subscribers
    std.debug.print("Sending messages to all subscribers...\n\n", .{});

    var count: usize = 0;
    while (count < 20) : (count += 1) {
        var buf: [256]u8 = undefined;

        // Format message
        const msg = try std.fmt.bufPrint(&buf, "Message #{d} - Hello from PUB server!", .{count});

        // Send to ALL subscribers
        try sock.send(msg, .{});

        std.debug.print("[{d}] Broadcast to {d} subscribers: {s}\n", .{
            count,
            sock.connectionCount(),
            msg,
        });

        // Small delay
        std.Thread.sleep(500 * std.time.ns_per_ms);
    }

    std.debug.print("\n=== Done! ===\n", .{});
    std.debug.print("Final subscriber count: {d}\n", .{sock.connectionCount()});
}
