//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");
const net = std.net;
const zmtp = @import("zmtp.zig");
const types = @import("types.zig");
const protocol = @import("protocol.zig");

const SocketType = types.SocketType;
const Greeting = protocol.Greeting;
const ZmqCommand = protocol.ZmqCommand;

/// Send flags for socket.send()
pub const SendFlags = packed struct {
    /// Non-blocking mode (ZMQ_DONTWAIT)
    dontwait: bool = false,
    /// More message parts to follow (ZMQ_SNDMORE)
    sndmore: bool = false,
    _padding: u30 = 0,

    pub const DONTWAIT: u32 = 1;
    pub const SNDMORE: u32 = 2;

    pub fn fromU32(flags: u32) SendFlags {
        return .{
            .dontwait = (flags & DONTWAIT) != 0,
            .sndmore = (flags & SNDMORE) != 0,
        };
    }

    pub fn toU32(self: SendFlags) u32 {
        var result: u32 = 0;
        if (self.dontwait) result |= DONTWAIT;
        if (self.sndmore) result |= SNDMORE;
        return result;
    }
};

/// Represents a single client connection
const Connection = struct {
    allocator: std.mem.Allocator,
    stream: net.Stream,
    frame_engine: zmtp.ZmtpFrameEngine,
    id: usize,
    // Subscription state (for PUB side): list of topics and match-all flag
    subscriptions: std.ArrayListUnmanaged([]u8),
    match_all: bool,

    pub fn init(allocator: std.mem.Allocator, stream: net.Stream, id: usize) Connection {
        return .{
            .allocator = allocator,
            .stream = stream,
            .frame_engine = zmtp.ZmtpFrameEngine.init(allocator),
            .id = id,
            .subscriptions = .{ .items = &[_][]u8{}, .capacity = 0 },
            .match_all = false,
        };
    }

    pub fn close(self: *Connection) void {
        // Free stored subscription topics
        if (self.subscriptions.capacity > 0) {
            for (self.subscriptions.items) |topic| {
                self.allocator.free(topic);
            }
            self.allocator.free(self.subscriptions.allocatedSlice());
        }
        self.stream.close();
    }
};

pub const Socket = struct {
    allocator: std.mem.Allocator,
    socket_type: SocketType,
    stream: ?net.Stream,
    server: ?net.Server,
    frame_engine: zmtp.ZmtpFrameEngine,
    // Multi-connection support
    connections: std.ArrayList(Connection),
    next_connection_id: usize,
    accept_mutex: std.Thread.Mutex,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, socket_type: SocketType) !*Self {
        const sock = try allocator.create(Self);
        sock.* = .{
            .allocator = allocator,
            .socket_type = socket_type,
            .stream = null,
            .server = null,
            .frame_engine = zmtp.ZmtpFrameEngine.init(allocator),
            .connections = .{
                .items = &[_]Connection{},
                .capacity = 0,
            },
            .next_connection_id = 0,
            .accept_mutex = .{},
        };
        return sock;
    }

    pub fn connect(self: *Self, endpoint: []const u8) !void {
        // Parse endpoint (format: tcp://host:port)
        if (!std.mem.startsWith(u8, endpoint, "tcp://")) {
            return error.InvalidEndpoint;
        }
        const addr_port = endpoint[6..];
        const colon_idx = std.mem.lastIndexOf(u8, addr_port, ":") orelse return error.InvalidEndpoint;
        const host = addr_port[0..colon_idx];
        const port = try std.fmt.parseInt(u16, addr_port[colon_idx + 1 ..], 10);

        // Connect to server
        const address = try net.Address.resolveIp(host, port);
        self.stream = try net.tcpConnectToAddress(address);

        // Send greeting
        var greet = Greeting.init();
        const greet_slice = greet.toSlice();
        var send_buf: [128]u8 = undefined;
        var writer = self.stream.?.writer(send_buf[0..]);
        _ = try writer.interface.write(greet_slice[0..]);
        try writer.interface.flush();

        // Receive greeting
        var in = [_]u8{0} ** 64;
        _ = try self.stream.?.readAtLeast(&in, Greeting.greet_size);
        const got_greeting = try Greeting.fromSlice(&in);
        std.debug.print("Received greeting: version {d}.{d}, mechanism: {s}\n", .{
            got_greeting.version.@"0",
            got_greeting.version.@"1",
            got_greeting.mechanism.asSlice(),
        });

        // Send READY command
        var cmd_ready = ZmqCommand.ready(self.socket_type);
        defer cmd_ready.deinit();
        const cmd_frame = cmd_ready.toFrame();
        var cmd_send_buf: [256]u8 = undefined;
        var cmd_writer = self.stream.?.writer(cmd_send_buf[0..]);
        _ = try cmd_writer.interface.write(cmd_frame);
        try cmd_writer.interface.flush();

        // Receive READY command - read the complete frame
        // First read the frame header to know how much to read
        _ = try self.stream.?.readAtLeast(in[0..2], 2);
        const ready_flags = in[0];
        const ready_size = in[1];

        std.debug.print("READY frame: flags=0x{x:0>2}, size={d}\n", .{ ready_flags, ready_size });

        // Read the rest of the frame
        if (ready_size > 0) {
            _ = try self.stream.?.readAtLeast(in[2 .. 2 + ready_size], ready_size);
        }

        const total_len = 2 + ready_size;
        std.debug.print("Received READY response: {d} bytes total\n", .{total_len});
        std.debug.print("Raw data: {x}\n", .{in[0..total_len]});

        const cmd_other_ready = try ZmqCommand.fromSlice(in[0..total_len]);
        if (cmd_other_ready.name == .READY) {
            std.debug.print("Connection established - stream is now clean\n", .{});
        }
    }

    pub fn bind(self: *Self, endpoint: []const u8) !void {
        // Parse endpoint (format: tcp://host:port)
        if (!std.mem.startsWith(u8, endpoint, "tcp://")) {
            return error.InvalidEndpoint;
        }
        const addr_port = endpoint[6..];
        const colon_idx = std.mem.lastIndexOf(u8, addr_port, ":") orelse return error.InvalidEndpoint;
        const host = addr_port[0..colon_idx];
        const port = try std.fmt.parseInt(u16, addr_port[colon_idx + 1 ..], 10);

        // Parse address - support * for all interfaces
        const address = if (std.mem.eql(u8, host, "*"))
            try net.Address.parseIp("0.0.0.0", port)
        else
            try net.Address.resolveIp(host, port);

        // Create server socket
        self.server = try address.listen(.{
            .reuse_address = true,
        });
        std.debug.print("Bound to {s} (listening on {any})\n", .{ endpoint, address });
    }

    pub fn accept(self: *Self) !void {
        if (self.server == null) return error.NotBound;

        std.debug.print("Waiting for incoming connection...\n", .{});

        // Accept incoming connection
        const connection = try self.server.?.accept();
        const client_stream = connection.stream;

        std.debug.print("Accepted connection from {any}\n", .{connection.address});

        // Disable Nagle's algorithm
        try std.posix.setsockopt(
            client_stream.handle,
            std.posix.IPPROTO.TCP,
            std.posix.TCP.NODELAY,
            &std.mem.toBytes(@as(c_int, 1)),
        );

        // Receive greeting from client
        // PyZMQ/ZMTP 3.1 may send greeting in a non-standard way
        // Read what we can get and validate
        var in = [_]u8{0} ** 256;
        const greeting_read = client_stream.read(in[0..Greeting.greet_size]) catch |err| {
            std.debug.print("Error reading greeting: {any}\n", .{err});
            client_stream.close();
            return err;
        };

        std.debug.print("Received {d} bytes for greeting\n", .{greeting_read});

        if (greeting_read < 10) {
            std.debug.print("Greeting too short, got {d} bytes\n", .{greeting_read});
            client_stream.close();
            return error.InvalidGreeting;
        }

        // Try to parse greeting, but be lenient
        _ = Greeting.fromSlice(&in) catch |err| {
            std.debug.print("Warning: Could not parse greeting: {any}, continuing anyway\n", .{err});
            // Continue with handshake anyway
        };

        std.debug.print("Client greeting accepted\n", .{});

        // Send greeting back to client
        var greet = Greeting.init();
        greet.as_server = true; // Mark as server
        const greet_slice = greet.toSlice();
        var send_buf: [128]u8 = undefined;
        var writer = client_stream.writer(send_buf[0..]);
        _ = try writer.interface.write(greet_slice[0..]);
        try writer.interface.flush();

        // Receive READY command from client
        // PyZMQ and other implementations may send READY in various formats
        // We'll read and accept any command frame as READY
        @memset(&in, 0);
        _ = try client_stream.readAtLeast(in[0..2], 2);
        const ready_flags = in[0];

        // Check if this is a command frame
        if (ready_flags & 0x04 == 0) {
            std.debug.print("Warning: Expected command frame, got flags=0x{x:0>2}\n", .{ready_flags});
        }

        // Determine frame length and read payload
        var payload_size: usize = 0;
        var header_size: usize = 2;

        if (ready_flags & 0x02 != 0) {
            // Long frame - read 8 byte length
            _ = try client_stream.readAtLeast(in[1..9], 8);
            payload_size = std.mem.readInt(u64, in[1..9], .big);
            header_size = 9;
        } else {
            // Short frame - 1 byte length
            payload_size = in[1];
        }

        // Read the payload (limit to reasonable size)
        if (payload_size > 0 and payload_size < 256) {
            if (header_size + payload_size <= 256) {
                _ = try client_stream.readAtLeast(in[header_size .. header_size + payload_size], payload_size);
            }
        }

        std.debug.print("Client READY received (handshake complete)\n", .{});

        // Send READY command back
        var cmd_ready = ZmqCommand.ready(self.socket_type);
        defer cmd_ready.deinit();
        const cmd_frame = cmd_ready.toFrame();
        var cmd_send_buf: [256]u8 = undefined;
        var cmd_writer = client_stream.writer(cmd_send_buf[0..]);
        _ = try cmd_writer.interface.write(cmd_frame);
        try cmd_writer.interface.flush();

        std.debug.print("Connection established - ready to communicate\n", .{});

        // Set connection to non-blocking mode ONLY for PUB sockets (for subscription harvesting)
        if (self.socket_type == .PUB) {
            const flags = try std.posix.fcntl(client_stream.handle, std.posix.F.GETFL, 0);
            const NONBLOCK: u32 = if (@hasDecl(std.posix.O, "NONBLOCK")) std.posix.O.NONBLOCK else 0x0004;
            _ = try std.posix.fcntl(client_stream.handle, std.posix.F.SETFL, flags | NONBLOCK);
        }

        // Add the connection to our list
        self.accept_mutex.lock();
        defer self.accept_mutex.unlock();

        const conn_id = self.next_connection_id;
        self.next_connection_id += 1;

        const conn = Connection.init(self.allocator, client_stream, conn_id);
        try self.connections.append(self.allocator, conn);

        // For backwards compatibility, also set the main stream to the first connection
        if (self.stream == null) {
            self.stream = client_stream;
        }

        std.debug.print("Connection #{d} added. Total connections: {d}\n", .{ conn_id, self.connections.items.len });

        // For PUB sockets, do an initial harvest of subscription messages
        if (self.socket_type == .PUB) {
            // Give the client more time to send subscription messages
            std.Thread.sleep(100 * std.time.ns_per_ms);
            const conn_ptr = &self.connections.items[self.connections.items.len - 1];
            self.harvestSubscriptions(conn_ptr) catch |err| {
                std.debug.print("Warning: Failed to harvest initial subscriptions: {any}\n", .{err});
            };
        }
    }

    pub fn send(self: *Self, data: []const u8, sendFlags: SendFlags) !void {
        if (self.stream == null) return error.NotConnected;

        std.debug.print("Sending {d} bytes: {s}\n", .{ data.len, data });

        switch (self.socket_type) {
            .REQ => try self.sendReq(data, sendFlags),
            .REP => try self.sendRep(data, sendFlags),
            .PUB => try self.sendPub(data, sendFlags),
            .SUB => try self.sendSub(data, sendFlags),
            else => try self.sendDefault(data, sendFlags),
        }
    }

    fn sendReq(self: *Self, data: []const u8, flags: SendFlags) !void {
        _ = flags;
        // Frame 1: Empty delimiter with MORE flag
        const delimiter_frame = try self.frame_engine.createMessageFrame(&[_]u8{}, true);
        defer self.allocator.free(delimiter_frame);

        // Frame 2: Data with LAST flag
        const data_frame = try self.frame_engine.createMessageFrame(data, false);
        defer self.allocator.free(data_frame);

        // Send as two frames without concatenation
        std.debug.print("REQ: Sending empty delimiter frame\n", .{});
        try self.sendRawFrame(delimiter_frame);

        std.debug.print("REQ: Sending message data frame\n", .{});
        try self.sendRawFrame(data_frame);
    }

    fn sendRep(self: *Self, data: []const u8, flags: SendFlags) !void {
        _ = flags;
        // REP also uses delimiter frame in response
        std.debug.print("REP: Sending empty delimiter frame\n", .{});
        const delimiter_frame = try self.frame_engine.createMessageFrame(&[_]u8{}, true);
        defer self.allocator.free(delimiter_frame);
        self.sendRawFrame(delimiter_frame) catch |err| {
            std.debug.print("REP: Failed to send delimiter frame: {any}\n", .{err});
            return err;
        };

        std.debug.print("REP: Sending message data frame\n", .{});
        const data_frame = try self.frame_engine.createMessageFrame(data, false);
        defer self.allocator.free(data_frame);
        self.sendRawFrame(data_frame) catch |err| {
            std.debug.print("REP: Failed to send data frame: {any}\n", .{err});
            return err;
        };
    }

    fn sendPub(self: *Self, data: []const u8, flags: SendFlags) !void {
        _ = flags;
        // PUB socket sends only to subscribers with matching subscriptions
        std.debug.print("PUB: Considering message for {d} subscriber(s)\n", .{self.connections.items.len});

        const frame = try self.frame_engine.createMessageFrame(data, false);
        defer self.allocator.free(frame);

        // Check each connection's subscriptions and deliver selectively
        self.accept_mutex.lock();
        defer self.accept_mutex.unlock();

        var i: usize = 0;
        while (i < self.connections.items.len) {
            var conn = &self.connections.items[i];

            // Harvest any pending subscription messages before sending
            self.harvestSubscriptions(conn) catch |err| {
                std.debug.print("PUB: Failed to harvest subscriptions from connection #{d}: {any}, removing\n", .{ conn.id, err });
                conn.close();
                _ = self.connections.orderedRemove(i);
                continue;
            };

            if (self.connectionWants(conn, data)) {
                std.debug.print("PUB: Sending to connection #{d}\n", .{conn.id});
                self.sendRawFrameToConnection(conn, frame) catch |err| {
                    std.debug.print("PUB: Failed to send to connection #{d}: {any}, removing\n", .{ conn.id, err });
                    conn.close();
                    _ = self.connections.orderedRemove(i);
                    continue;
                };
            } else {
                std.debug.print("PUB: Skipping connection #{d} (no matching subscription)\n", .{conn.id});
            }
            i += 1;
        }
    }

    fn sendSub(_: *Self, _: []const u8, _: SendFlags) !void {
        // SUB socket should not normally send data messages
        // Only SUBSCRIBE/CANCEL commands are sent
        std.debug.print("SUB: Warning - SUB sockets should not send data messages\n", .{});
        return error.InvalidOperation;
    }

    // Determine if a given message should be delivered to this connection
    fn connectionWants(self: *Self, conn: *Connection, msg: []const u8) bool {
        _ = self;
        if (conn.match_all) return true;
        // If no subscriptions at all, do not deliver
        if (conn.subscriptions.items.len == 0) return false;
        for (conn.subscriptions.items) |topic| {
            if (std.mem.startsWith(u8, msg, topic)) return true;
        }
        return false;
    }

    fn addSubscription(self: *Self, conn: *Connection, topic: []const u8) void {
        _ = self;
        if (topic.len == 0) {
            conn.match_all = true;
            return;
        }
        // Avoid duplicates
        for (conn.subscriptions.items) |t| {
            if (std.mem.eql(u8, t, topic)) return;
        }
        const copy = conn.allocator.dupe(u8, topic) catch return;
        conn.subscriptions.append(conn.allocator, copy) catch {
            conn.allocator.free(copy);
            return;
        };
    }

    fn removeSubscription(self: *Self, conn: *Connection, topic: []const u8) void {
        _ = self;
        if (topic.len == 0) {
            // Unsubscribe from all (match_all off)
            conn.match_all = false;
            return;
        }
        var i: usize = 0;
        while (i < conn.subscriptions.items.len) {
            const t = conn.subscriptions.items[i];
            if (std.mem.eql(u8, t, topic)) {
                conn.allocator.free(t);
                _ = conn.subscriptions.orderedRemove(i);
                return;
            }
            i += 1;
        }
    }

    // Non-blocking harvest of subscription frames from a subscriber connection
    fn harvestSubscriptions(self: *Self, conn: *Connection) !void {
        std.debug.print("PUB: Harvesting subscriptions from connection #{d}...\n", .{conn.id});
        // Try to read as many subscription frames as available without blocking
        var harvested: usize = 0;
        while (true) {
            const frame = conn.frame_engine.parseFrame(conn.stream) catch |err| {
                // WouldBlock or end-of-stream -> stop harvesting
                // Map common non-blocking errors to break condition
                if (err == error.WouldBlock or err == error.InputOutput) {
                    std.debug.print("PUB: Harvested {d} subscription frame(s) from connection #{d}\n", .{ harvested, conn.id });
                    return; // stop without error
                }
                // Connection closed or other fatal errors propagate up
                std.debug.print("PUB: Harvest error for connection #{d}: {any}\n", .{ conn.id, err });
                return err;
            };
            defer self.allocator.free(frame.data);
            harvested += 1;

            // Subscription messages are regular message frames with first byte 0x01 or 0x00
            std.debug.print("PUB: Frame: is_command={}, len={d}, data[0]=0x{x:0>2}\n", .{ frame.is_command, frame.data.len, if (frame.data.len > 0) frame.data[0] else 0 });
            if (!frame.is_command and frame.data.len >= 1) {
                const op = frame.data[0];
                const topic = frame.data[1..];
                if (op == 0x01) {
                    std.debug.print("PUB: Conn #{d} SUB '{s}'\n", .{ conn.id, topic });
                    self.addSubscription(conn, topic);
                } else if (op == 0x00) {
                    std.debug.print("PUB: Conn #{d} UNSUB '{s}'\n", .{ conn.id, topic });
                    self.removeSubscription(conn, topic);
                } else {
                    std.debug.print("PUB: Ignoring frame with op=0x{x:0>2}\n", .{op});
                }
            }

            // If there are no more frames queued, the next parse will return WouldBlock
            // Loop continues until then
        }
    }

    fn sendDefault(self: *Self, data: []const u8, flags: SendFlags) !void {
        _ = flags;
        std.debug.print("Sending message data frame\n", .{});
        const frame = try self.frame_engine.createMessageFrame(data, false);
        defer self.allocator.free(frame);
        try self.sendRawFrame(frame);
    }

    fn sendRawFrame(self: *Self, frame: []const u8) !void {
        if (self.stream) |stream| {
            std.debug.print("Sending raw frame ({d} bytes): {x}\n", .{ frame.len, frame });

            // Send frame using writer
            var send_buf: [1024]u8 = undefined;
            var writer = stream.writer(send_buf[0..]);
            _ = writer.interface.write(frame) catch |err| {
                // On write error, mark stream as null to avoid double-close issues
                self.stream = null;
                return err;
            };
            writer.interface.flush() catch |err| {
                // On flush error, mark stream as null to avoid double-close issues
                self.stream = null;
                return err;
            };
            std.debug.print("Frame sent successfully\n", .{});
        } else {
            return error.NotConnected;
        }
    }

    fn sendRawFrameToConnection(self: *Self, conn: *Connection, frame: []const u8) !void {
        _ = self;
        std.debug.print("Sending raw frame to connection #{d} ({d} bytes)\n", .{ conn.id, frame.len });

        // Send frame using writer
        var send_buf: [1024]u8 = undefined;
        var writer = conn.stream.writer(send_buf[0..]);
        _ = try writer.interface.write(frame);
        try writer.interface.flush();
        std.debug.print("Frame sent to connection #{d} successfully\n", .{conn.id});
    }

    pub fn recv(self: *Self, buffer: []u8, recvFlags: u32) !usize {
        _ = recvFlags;
        if (self.stream == null) return error.NotConnected;

        std.debug.print("\n=== Starting recv() ===\n", .{});

        // For REQ/REP sockets, we need to receive with proper ZMTP framing
        if (self.socket_type == .REQ or self.socket_type == .REP) {
            // Read frames until we get one without MORE flag
            // Skip empty delimiter frames (they have size 0)
            var total_read: usize = 0;
            var frame_count: usize = 0;

            while (true) {
                frame_count += 1;
                std.debug.print("\n--- Frame #{d} ---\n", .{frame_count});

                // Parse frame using frame engine
                const frame = self.frame_engine.parseFrame(self.stream.?) catch |err| {
                    // On connection error, mark stream as null to avoid double-close
                    self.stream = null;
                    return err;
                };
                defer self.allocator.free(frame.data);

                std.debug.print("Frame #{d}: len={d}, has_more={}\n", .{ frame_count, frame.data.len, frame.more });

                // Only accumulate non-empty frames (skip delimiter frames)
                if (frame.data.len > 0) {
                    if (total_read + frame.data.len > buffer.len) {
                        return error.BufferTooSmall;
                    }
                    @memcpy(buffer[total_read .. total_read + frame.data.len], frame.data);
                    total_read += frame.data.len;
                    std.debug.print("Accumulated data so far: {d} bytes\n", .{total_read});
                }

                if (!frame.more) break;
            }

            std.debug.print("\n=== recv() complete: {d} bytes total ===\n", .{total_read});
            return total_read;
        } else {
            // Other socket types
            const frame = self.frame_engine.parseFrame(self.stream.?) catch |err| {
                // On connection error, mark stream as null to avoid double-close
                self.stream = null;
                return err;
            };
            defer self.allocator.free(frame.data);

            if (frame.data.len > buffer.len) {
                return error.BufferTooSmall;
            }
            @memcpy(buffer[0..frame.data.len], frame.data);
            return frame.data.len;
        }
    }

    /// Subscribe to a topic (SUB socket only)
    /// Pass empty string "" to subscribe to all messages
    pub fn subscribe(self: *Self, topic: []const u8) !void {
        if (self.socket_type != .SUB) {
            return error.InvalidSocketType;
        }
        if (self.stream == null) return error.NotConnected;

        std.debug.print("SUB: Subscribing to topic: '{s}'\n", .{topic});

        // Create a SUBSCRIBE command frame
        // In ZMTP 3.x, subscriptions are sent as messages with \x01 prefix + topic
        var sub_data: [256]u8 = undefined;
        sub_data[0] = 0x01; // SUBSCRIBE command byte
        @memcpy(sub_data[1 .. 1 + topic.len], topic);
        const sub_message = sub_data[0 .. 1 + topic.len];

        const frame = try self.frame_engine.createMessageFrame(sub_message, false);
        defer self.allocator.free(frame);
        try self.sendRawFrame(frame);
    }

    /// Unsubscribe from a topic (SUB socket only)
    pub fn unsubscribe(self: *Self, topic: []const u8) !void {
        if (self.socket_type != .SUB) {
            return error.InvalidSocketType;
        }
        if (self.stream == null) return error.NotConnected;

        std.debug.print("SUB: Unsubscribing from topic: '{s}'\n", .{topic});

        // Create a CANCEL (unsubscribe) command frame
        // In ZMTP 3.x, unsubscriptions are sent as messages with \x00 prefix + topic
        var unsub_data: [256]u8 = undefined;
        unsub_data[0] = 0x00; // CANCEL command byte
        @memcpy(unsub_data[1 .. 1 + topic.len], topic);
        const unsub_message = unsub_data[0 .. 1 + topic.len];

        const frame = try self.frame_engine.createMessageFrame(unsub_message, false);
        defer self.allocator.free(frame);
        try self.sendRawFrame(frame);
    }

    pub fn close(self: *Self) void {
        // Close all connections
        self.accept_mutex.lock();
        for (self.connections.items) |*conn| {
            conn.close();
        }
        if (self.connections.capacity > 0) {
            self.allocator.free(self.connections.allocatedSlice());
        }
        self.accept_mutex.unlock();

        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
        if (self.server) |*server| {
            server.deinit();
            self.server = null;
        }
        self.allocator.destroy(self);
    }

    /// Accept connections in a loop (non-blocking after first connection)
    /// Useful for accepting multiple connections without blocking the main thread
    pub fn acceptLoop(self: *Self, max_connections: ?usize) !void {
        const max = max_connections orelse std.math.maxInt(usize);
        var count: usize = 0;

        while (count < max) : (count += 1) {
            try self.accept();
        }
    }

    /// Get the number of active connections
    pub fn connectionCount(self: *Self) usize {
        self.accept_mutex.lock();
        defer self.accept_mutex.unlock();
        return self.connections.items.len;
    }

    /// Remove dead connections
    pub fn pruneConnections(self: *Self) void {
        self.accept_mutex.lock();
        defer self.accept_mutex.unlock();

        var i: usize = 0;
        while (i < self.connections.items.len) {
            // Try a test write to check if connection is alive
            // For now, just keep all connections
            // TODO: Implement connection health check
            i += 1;
        }
    }
};

// Tests
const testing = std.testing;

test "Socket init and type" {
    const allocator = testing.allocator;

    const sock = try Socket.init(allocator, .PUB);
    defer sock.close();

    try testing.expectEqual(SocketType.PUB, sock.socket_type);
    try testing.expect(sock.stream == null);
    try testing.expect(sock.server == null);
    try testing.expectEqual(@as(usize, 0), sock.connections.items.len);
}

test "Connection subscription management - match all" {
    const allocator = testing.allocator;

    const sock = try Socket.init(allocator, .PUB);
    defer sock.close();

    // Create a mock stream (we won't actually use it for network operations)
    var conn = Connection.init(allocator, undefined, 0);
    defer {
        // Don't close the stream since it's undefined
        // Just free subscriptions
        if (conn.subscriptions.capacity > 0) {
            for (conn.subscriptions.items) |topic| {
                allocator.free(topic);
            }
            allocator.free(conn.subscriptions.allocatedSlice());
        }
    }

    // Initially, connection should not want any messages
    try testing.expectEqual(false, sock.connectionWants(&conn, "weather update"));
    try testing.expectEqual(false, sock.connectionWants(&conn, "news flash"));

    // Subscribe to all (empty topic)
    sock.addSubscription(&conn, "");
    try testing.expectEqual(true, conn.match_all);
    try testing.expectEqual(true, sock.connectionWants(&conn, "weather update"));
    try testing.expectEqual(true, sock.connectionWants(&conn, "news flash"));
    try testing.expectEqual(true, sock.connectionWants(&conn, "any message"));
}

test "Connection subscription management - specific topics" {
    const allocator = testing.allocator;

    const sock = try Socket.init(allocator, .PUB);
    defer sock.close();

    var conn = Connection.init(allocator, undefined, 0);
    defer {
        if (conn.subscriptions.capacity > 0) {
            for (conn.subscriptions.items) |topic| {
                allocator.free(topic);
            }
            allocator.free(conn.subscriptions.allocatedSlice());
        }
    }

    // Subscribe to "weather" topic
    sock.addSubscription(&conn, "weather");
    try testing.expectEqual(false, conn.match_all);
    try testing.expectEqual(@as(usize, 1), conn.subscriptions.items.len);

    // Should match messages starting with "weather"
    try testing.expectEqual(true, sock.connectionWants(&conn, "weather update"));
    try testing.expectEqual(true, sock.connectionWants(&conn, "weather forecast"));
    try testing.expectEqual(false, sock.connectionWants(&conn, "news flash"));
    try testing.expectEqual(false, sock.connectionWants(&conn, "sports scores"));

    // Add another subscription
    sock.addSubscription(&conn, "news");
    try testing.expectEqual(@as(usize, 2), conn.subscriptions.items.len);

    // Should match both topics now
    try testing.expectEqual(true, sock.connectionWants(&conn, "weather update"));
    try testing.expectEqual(true, sock.connectionWants(&conn, "news flash"));
    try testing.expectEqual(false, sock.connectionWants(&conn, "sports scores"));
}

test "Connection subscription management - remove subscription" {
    const allocator = testing.allocator;

    const sock = try Socket.init(allocator, .PUB);
    defer sock.close();

    var conn = Connection.init(allocator, undefined, 0);
    defer {
        if (conn.subscriptions.capacity > 0) {
            for (conn.subscriptions.items) |topic| {
                allocator.free(topic);
            }
            allocator.free(conn.subscriptions.allocatedSlice());
        }
    }

    // Subscribe to multiple topics
    sock.addSubscription(&conn, "weather");
    sock.addSubscription(&conn, "news");
    try testing.expectEqual(@as(usize, 2), conn.subscriptions.items.len);

    // Remove one subscription
    sock.removeSubscription(&conn, "weather");
    try testing.expectEqual(@as(usize, 1), conn.subscriptions.items.len);

    // Should only match news now
    try testing.expectEqual(false, sock.connectionWants(&conn, "weather update"));
    try testing.expectEqual(true, sock.connectionWants(&conn, "news flash"));

    // Remove the last subscription
    sock.removeSubscription(&conn, "news");
    try testing.expectEqual(@as(usize, 0), conn.subscriptions.items.len);

    // Should not match anything
    try testing.expectEqual(false, sock.connectionWants(&conn, "weather update"));
    try testing.expectEqual(false, sock.connectionWants(&conn, "news flash"));
}

test "Connection subscription management - duplicate prevention" {
    const allocator = testing.allocator;

    const sock = try Socket.init(allocator, .PUB);
    defer sock.close();

    var conn = Connection.init(allocator, undefined, 0);
    defer {
        if (conn.subscriptions.capacity > 0) {
            for (conn.subscriptions.items) |topic| {
                allocator.free(topic);
            }
            allocator.free(conn.subscriptions.allocatedSlice());
        }
    }

    // Subscribe to same topic multiple times
    sock.addSubscription(&conn, "weather");
    sock.addSubscription(&conn, "weather");
    sock.addSubscription(&conn, "weather");

    // Should only be stored once
    try testing.expectEqual(@as(usize, 1), conn.subscriptions.items.len);
}

test "Connection subscription management - match_all unsubscribe" {
    const allocator = testing.allocator;

    const sock = try Socket.init(allocator, .PUB);
    defer sock.close();

    var conn = Connection.init(allocator, undefined, 0);
    defer {
        if (conn.subscriptions.capacity > 0) {
            for (conn.subscriptions.items) |topic| {
                allocator.free(topic);
            }
            allocator.free(conn.subscriptions.allocatedSlice());
        }
    }

    // Subscribe to all
    sock.addSubscription(&conn, "");
    try testing.expectEqual(true, conn.match_all);

    // Unsubscribe from all (empty topic)
    sock.removeSubscription(&conn, "");
    try testing.expectEqual(false, conn.match_all);
    try testing.expectEqual(false, sock.connectionWants(&conn, "any message"));
}

test "Socket connection counting" {
    const allocator = testing.allocator;

    const sock = try Socket.init(allocator, .PUB);
    defer sock.close();

    // Initially no connections
    try testing.expectEqual(@as(usize, 0), sock.connectionCount());

    // Note: We can't easily test adding connections without network operations
    // This test just verifies the function exists and returns the initial count
}
