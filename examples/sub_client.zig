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

    std.debug.print("=== ZeroMQ SUB Client Example ===\n", .{});

    // Create context
    const ctx = try zmq.Context.init(allocator);
    defer ctx.deinit();

    // Create SUB socket
    const sock = try ctx.socket(.SUB);
    defer sock.close();

    // Connect to publisher
    std.debug.print("Connecting to publisher at tcp://127.0.0.1:5555...\n", .{});
    try sock.connect("tcp://127.0.0.1:5555");

    // Subscribe to topics
    // Subscribe to all messages with empty string
    std.debug.print("Subscribing to all messages...\n", .{});
    try sock.subscribe("");

    // Alternatively, subscribe to specific topics:
    // try sock.subscribe("weather");
    // try sock.subscribe("news");

    std.debug.print("Waiting for messages... (Press Ctrl+C to exit)\n\n", .{});

    // Receive messages in a loop
    var buffer: [1024]u8 = undefined;
    var count: usize = 0;
    while (true) {
        const len = sock.recv(&buffer, 0) catch |err| {
            std.debug.print("Error receiving: {any}\n", .{err});
            break;
        };

        count += 1;
        std.debug.print("[{d}] Received ({d} bytes): {s}\n", .{ count, len, buffer[0..len] });
    }
}
