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

    std.debug.print("=== ZeroMQ REP Server Example ===\n", .{});

    // Create context
    const ctx = try zmq.Context.init(allocator);
    defer ctx.deinit();

    // Create REP socket
    const sock = try ctx.socket(.REP);
    defer sock.close();

    // Bind to endpoint (server mode)
    std.debug.print("Binding to tcp://*:42123...\n", .{});
    try sock.bind("tcp://*:42123");

    // Wait for client to connect
    std.debug.print("Waiting for client to connect...\n", .{});
    try sock.accept();

    std.debug.print("Client connected! Ready to receive requests...\n\n", .{});

    // Request-reply loop
    var buffer: [512]u8 = undefined;
    var count: usize = 0;

    while (count < 10) : (count += 1) {
        // Receive request
        std.debug.print("[{d}] Waiting for request...\n", .{count});
        const len = sock.recv(&buffer, 0) catch |err| {
            std.debug.print("Client disconnected during recv: {any}\n", .{err});
            break;
        };
        std.debug.print("[{d}] Received request ({d} bytes): {s}\n", .{ count, len, buffer[0..len] });

        // Process request (just echo it back with a prefix)
        var reply_buf: [512]u8 = undefined;
        const reply = try std.fmt.bufPrint(&reply_buf, "Reply to: {s}", .{buffer[0..len]});

        // Send reply
        sock.send(reply, .{}) catch |err| {
            std.debug.print("Client disconnected during send: {any}\n", .{err});
            break;
        };
        std.debug.print("[{d}] Sent reply: {s}\n\n", .{ count, reply });

        // Small delay between replies
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    std.debug.print("Server shutting down after {d} requests.\n", .{count});
}
