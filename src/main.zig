//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.
//!
//! A simple ZeroMQ REQ client in Zig that connects to a REP server,
//! sends a message, and waits for a reply.

const std = @import("std");
const zmq = @import("zmq.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Create context (similar to zmq_ctx_new)
    const ctx = try zmq.Context.init(allocator);
    defer ctx.deinit();

    // Create REQ socket (similar to zmq_socket)
    const sock = try ctx.socket(.REQ);
    defer sock.close();

    // Connect to REP server endpoint (similar to zmq_connect)
    // Note: Use `zig build run-rep` to start the REP server
    try sock.connect("tcp://127.0.0.1:42123");

    // Send message (similar to zmq_send)
    const message = "Hello ZeroMQ";
    try sock.send(message, .{});
    std.debug.print("\nSent: {s}\n", .{message});

    // Receive message (similar to zmq_recv)
    var buffer: [512]u8 = undefined;
    std.debug.print("Waiting for reply...\n", .{});

    const len = sock.recv(&buffer, 0) catch |err| {
        std.debug.print("Error receiving: {any}\n", .{err});
        std.debug.print("\nThe server did not send a response.\n", .{});
        return err;
    };

    std.debug.print("\n✓ SUCCESS! Received {d} bytes: {s}\n", .{ len, buffer[0..len] });
}
