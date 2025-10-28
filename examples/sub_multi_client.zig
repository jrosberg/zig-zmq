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

    // Get client ID from command line args or use default
    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    _ = args.skip(); // Skip program name

    const client_id = if (args.next()) |arg|
        try std.fmt.parseInt(usize, arg, 10)
    else
        1;

    // Get topic filter from command line or use default
    const topic_filter = if (args.next()) |arg|
        arg
    else
        "";

    std.debug.print("=== ZeroMQ SUB Client #{d} - Multiple Connections Example ===\n", .{client_id});
    std.debug.print("Topic filter: '{s}' (empty = all messages)\n\n", .{topic_filter});

    // Create context
    const ctx = try zmq.Context.init(allocator);
    defer ctx.deinit();

    // Create SUB socket
    const sock = try ctx.socket(.SUB);
    defer sock.close();

    // Connect to server
    std.debug.print("Connecting to tcp://127.0.0.1:5555...\n", .{});
    try sock.connect("tcp://127.0.0.1:5555");

    // Subscribe to topic filter
    std.debug.print("Subscribing to topic: '{s}'\n", .{topic_filter});
    try sock.subscribe(topic_filter);

    std.debug.print("\n=== Ready to receive messages ===\n\n", .{});

    // Receive messages in a loop
    var buffer: [1024]u8 = undefined;
    var count: usize = 0;

    while (true) {
        const len = sock.recv(&buffer, 0) catch |err| {
            std.debug.print("Client #{d}: Receive error: {any}\n", .{ client_id, err });
            std.Thread.sleep(1 * std.time.ns_per_s);
            continue;
        };

        const message = buffer[0..len];
        count += 1;

        // Extract topic from message (topic is prefix before space)
        const space_idx = std.mem.indexOfScalar(u8, message, ' ') orelse message.len;
        const topic = message[0..space_idx];
        const content = if (space_idx < message.len) message[space_idx + 1 ..] else "";

        // Color output based on topic
        if (std.mem.eql(u8, topic, "weather")) {
            std.debug.print("\x1b[36mClient #{d} [{d}] 🌤️  {s}: {s}\x1b[0m\n", .{ client_id, count, topic, content });
        } else if (std.mem.eql(u8, topic, "news")) {
            std.debug.print("\x1b[33mClient #{d} [{d}] 📰 {s}: {s}\x1b[0m\n", .{ client_id, count, topic, content });
        } else if (std.mem.eql(u8, topic, "sports")) {
            std.debug.print("\x1b[32mClient #{d} [{d}] ⚽ {s}: {s}\x1b[0m\n", .{ client_id, count, topic, content });
        } else {
            std.debug.print("Client #{d} [{d}] Received ({d} bytes): {s}\n", .{ client_id, count, len, message });
        }

        // Show stats every 20 messages
        if (@mod(count, 20) == 0) {
            std.debug.print("\n--- Client #{d}: {d} messages received so far ---\n\n", .{ client_id, count });
        }
    }
}
