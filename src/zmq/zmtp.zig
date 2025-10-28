//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");

pub const ZmtpFrame = struct {
    // ZMTP 3.1 frame flags (exact byte values, not bit flags)
    // Messages:
    pub const message_last_short: u8 = 0x00; // Last frame, short size
    pub const message_more_short: u8 = 0x01; // More frames, short size
    pub const message_last_long: u8 = 0x02; // Last frame, long size
    pub const message_more_long: u8 = 0x03; // More frames, long size
    // Commands:
    pub const command_short: u8 = 0x04; // Command, short size
    pub const command_long: u8 = 0x06; // Command, long size

    // Legacy bit flags for compatibility (but prefer exact values above)
    pub const flag_more: u8 = 0b0000_0001;
    pub const flag_long: u8 = 0b0000_0010;
    pub const flag_command: u8 = 0b0000_0100;

    len: u64,
    flags: u8,
    data: [*]const u8,
};

pub const ZmtpFrameEngine = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{ .allocator = allocator };
    }

    /// Create a message frame with the given data
    /// Caller owns the returned memory and must call allocator.free() on it
    pub fn createMessageFrame(self: *Self, data: []const u8, more: bool) ![]u8 {
        const is_long = data.len > 255;
        const header_size: usize = if (is_long) 9 else 2;
        const total_size = header_size + data.len;

        var frame = try self.allocator.alloc(u8, total_size);
        errdefer self.allocator.free(frame);

        var pos: usize = 0;

        // Set flags byte
        if (is_long) {
            frame[0] = if (more) ZmtpFrame.message_more_long else ZmtpFrame.message_last_long;
            std.mem.writeInt(u64, frame[1..9], @intCast(data.len), .big);
            pos = 9;
        } else {
            frame[0] = if (more) ZmtpFrame.message_more_short else ZmtpFrame.message_last_short;
            frame[1] = @intCast(data.len);
            pos = 2;
        }

        // Copy data
        if (data.len > 0) {
            @memcpy(frame[pos .. pos + data.len], data);
        }

        return frame;
    }

    /// Create a command frame with the given command name and properties
    /// Caller owns the returned memory and must call allocator.free() on it
    pub fn createCommandFrame(self: *Self, cmd_name: []const u8, properties: std.StringHashMap([]const u8)) ![]u8 {
        // Calculate payload size
        var payload_size: usize = 1 + cmd_name.len; // command name length byte + name
        var iter = properties.iterator();
        while (iter.next()) |kv| {
            payload_size += 1 + kv.key_ptr.len; // property name length byte + name
            payload_size += 4 + kv.value_ptr.len; // property value length (4 bytes) + value
        }

        const is_long = payload_size > 255;
        const header_size: usize = if (is_long) 9 else 2;
        const total_size = header_size + payload_size;

        var frame = try self.allocator.alloc(u8, total_size);
        errdefer self.allocator.free(frame);

        var pos: usize = 0;

        // Set flags and size
        if (is_long) {
            frame[0] = ZmtpFrame.command_long;
            std.mem.writeInt(u64, frame[1..9], @intCast(payload_size), .big);
            pos = 9;
        } else {
            frame[0] = ZmtpFrame.command_short;
            frame[1] = @intCast(payload_size);
            pos = 2;
        }

        // Write command name
        frame[pos] = @intCast(cmd_name.len);
        pos += 1;
        @memcpy(frame[pos .. pos + cmd_name.len], cmd_name);
        pos += cmd_name.len;

        // Write properties
        var iter2 = properties.iterator();
        while (iter2.next()) |kv| {
            // Property name length + name
            frame[pos] = @intCast(kv.key_ptr.len);
            pos += 1;
            @memcpy(frame[pos .. pos + kv.key_ptr.len], kv.key_ptr.*);
            pos += kv.key_ptr.len;

            // Property value length + value
            std.mem.writeInt(u32, frame[pos .. pos + 4], @intCast(kv.value_ptr.len), .big);
            pos += 4;
            @memcpy(frame[pos .. pos + kv.value_ptr.len], kv.value_ptr.*);
            pos += kv.value_ptr.len;
        }

        return frame;
    }

    /// Parse a received frame and allocate a buffer for the data
    /// Returns a struct containing the frame data and metadata
    /// Caller owns the frame.data memory and must call allocator.free() on it
    pub const ReceivedFrame = struct {
        data: []u8,
        more: bool,
        is_command: bool,
    };

    pub fn parseFrame(self: *Self, stream: anytype) !ReceivedFrame {
        var header: [9]u8 = undefined;

        // Read flags byte
        _ = try stream.readAtLeast(header[0..1], 1);
        const flags = header[0];

        // Parse flags according to ZMTP 3.1 spec
        const is_long = (flags == ZmtpFrame.message_last_long or
            flags == ZmtpFrame.message_more_long or
            flags == ZmtpFrame.command_long);
        const has_more = (flags == ZmtpFrame.message_more_short or
            flags == ZmtpFrame.message_more_long);
        const is_command = (flags == ZmtpFrame.command_short or
            flags == ZmtpFrame.command_long);

        // Read size
        var frame_size: usize = 0;
        if (is_long) {
            _ = try stream.readAtLeast(header[1..9], 8);
            frame_size = std.mem.readInt(u64, header[1..9], .big);
        } else {
            _ = try stream.readAtLeast(header[1..2], 1);
            frame_size = header[1];
        }

        // Allocate buffer for frame data
        const data = try self.allocator.alloc(u8, frame_size);
        errdefer self.allocator.free(data);

        // Read frame data
        if (frame_size > 0) {
            _ = try stream.readAtLeast(data, frame_size);
        }

        return ReceivedFrame{
            .data = data,
            .more = has_more,
            .is_command = is_command,
        };
    }
};

pub const ZmtpError = error{ mechanism, badCommand, notImplemented };

pub const ZmtpVersion = struct {
    u8,
    u8,
};

pub const Mechanism = enum {
    null,
    plain,
    curve,

    pub fn asSlice(self: Mechanism) []const u8 {
        switch (self) {
            .null => return "NULL",
            .plain => return "PLAIN",
            .curve => return "CURVE",
        }
    }

    pub fn from(data: []const u8) ZmtpError!Mechanism {
        // Trim null bytes from the mechanism string
        const trimmed = std.mem.trim(u8, data, &[_]u8{0});

        // Case-insensitive comparison for NULL mechanism
        if (trimmed.len >= 4 and std.ascii.eqlIgnoreCase(trimmed[0..4], "NULL"))
            return .null;
        if (trimmed.len >= 5 and std.ascii.eqlIgnoreCase(trimmed[0..5], "PLAIN"))
            return .plain;
        if (trimmed.len >= 5 and std.ascii.eqlIgnoreCase(trimmed[0..5], "CURVE"))
            return .curve;

        // Default to NULL mechanism if empty or unrecognized
        if (trimmed.len == 0)
            return .null;

        std.debug.print("Unknown mechanism: '{s}' (bytes: {x})\n", .{ trimmed, data });
        return ZmtpError.mechanism;
    }
};

// Tests
const testing = std.testing;

test "ZmtpFrameEngine create short message frame" {
    const allocator = testing.allocator;
    var engine = ZmtpFrameEngine.init(allocator);

    const data = "Hello";
    const frame = try engine.createMessageFrame(data, false);
    defer allocator.free(frame);

    // Short frame: 1 byte flags + 1 byte size + data
    try testing.expectEqual(@as(usize, 2 + data.len), frame.len);

    // Check flags (should be 0x00 for last message, short)
    try testing.expectEqual(@as(u8, 0x00), frame[0]);

    // Check size
    try testing.expectEqual(@as(u8, data.len), frame[1]);

    // Check data
    try testing.expectEqualSlices(u8, data, frame[2..]);
}

test "ZmtpFrameEngine create short message frame with more flag" {
    const allocator = testing.allocator;
    var engine = ZmtpFrameEngine.init(allocator);

    const data = "Hello";
    const frame = try engine.createMessageFrame(data, true);
    defer allocator.free(frame);

    // Check flags (should be 0x01 for more messages)
    try testing.expectEqual(@as(u8, 0x01), frame[0]);

    // Check size
    try testing.expectEqual(@as(u8, data.len), frame[1]);

    // Check data
    try testing.expectEqualSlices(u8, data, frame[2..]);
}

test "ZmtpFrameEngine create long message frame" {
    const allocator = testing.allocator;
    var engine = ZmtpFrameEngine.init(allocator);

    // Create data larger than 255 bytes
    var data: [300]u8 = undefined;
    @memset(&data, 'A');

    const frame = try engine.createMessageFrame(&data, false);
    defer allocator.free(frame);

    // Long frame: 1 byte flags + 8 bytes size + data
    try testing.expectEqual(@as(usize, 9 + data.len), frame.len);

    // Check flags (should be 0x02 for last message, long)
    try testing.expectEqual(@as(u8, 0x02), frame[0]);

    // Check size (big-endian u64)
    const size = std.mem.readInt(u64, frame[1..9], .big);
    try testing.expectEqual(@as(u64, data.len), size);

    // Check data
    try testing.expectEqualSlices(u8, &data, frame[9..]);
}

test "ZmtpFrameEngine parse short frame" {
    const allocator = testing.allocator;
    var engine = ZmtpFrameEngine.init(allocator);

    // Create a frame first
    const original_data = "Test message";
    const created_frame = try engine.createMessageFrame(original_data, false);
    defer allocator.free(created_frame);

    // Create a mock stream-like buffer
    var buf_stream = std.io.fixedBufferStream(created_frame);
    const reader = buf_stream.reader();

    // Parse it back
    const parsed = try engine.parseFrame(reader.any());
    defer allocator.free(parsed.data);

    try testing.expectEqual(false, parsed.more);
    try testing.expectEqual(false, parsed.is_command);
    try testing.expectEqualSlices(u8, original_data, parsed.data);
}

test "ZmtpFrameEngine parse frame with more flag" {
    const allocator = testing.allocator;
    var engine = ZmtpFrameEngine.init(allocator);

    const original_data = "Part 1";
    const created_frame = try engine.createMessageFrame(original_data, true);
    defer allocator.free(created_frame);

    var buf_stream = std.io.fixedBufferStream(created_frame);
    const reader = buf_stream.reader();

    const parsed = try engine.parseFrame(reader.any());
    defer allocator.free(parsed.data);

    try testing.expectEqual(true, parsed.more);
    try testing.expectEqual(false, parsed.is_command);
    try testing.expectEqualSlices(u8, original_data, parsed.data);
}

test "ZmtpVersion" {
    const version = ZmtpVersion{ 3, 1 };
    try testing.expectEqual(@as(u8, 3), version.@"0");
    try testing.expectEqual(@as(u8, 1), version.@"1");
}

test "Mechanism enum and string conversion" {
    try testing.expectEqualStrings("NULL", Mechanism.null.asSlice());
    try testing.expectEqualStrings("PLAIN", Mechanism.plain.asSlice());
    try testing.expectEqualStrings("CURVE", Mechanism.curve.asSlice());
}

test "Mechanism from string" {
    // Test NULL mechanism
    var null_bytes = [_]u8{0} ** 20;
    @memcpy(null_bytes[0..4], "NULL");
    const null_mech = try Mechanism.from(&null_bytes);
    try testing.expectEqual(Mechanism.null, null_mech);

    // Test PLAIN mechanism
    var plain_bytes = [_]u8{0} ** 20;
    @memcpy(plain_bytes[0..5], "PLAIN");
    const plain_mech = try Mechanism.from(&plain_bytes);
    try testing.expectEqual(Mechanism.plain, plain_mech);

    // Test case insensitivity
    var lower_bytes = [_]u8{0} ** 20;
    @memcpy(lower_bytes[0..4], "null");
    const lower_mech = try Mechanism.from(&lower_bytes);
    try testing.expectEqual(Mechanism.null, lower_mech);

    // Test empty/all zeros defaults to NULL
    var empty_bytes = [_]u8{0} ** 20;
    const empty_mech = try Mechanism.from(&empty_bytes);
    try testing.expectEqual(Mechanism.null, empty_mech);
}

test "ZmtpFrameEngine roundtrip" {
    const allocator = testing.allocator;
    var engine = ZmtpFrameEngine.init(allocator);

    // Test data
    const test_cases = [_][]const u8{
        "Short message",
        "A" ** 100, // Medium message
    };

    for (test_cases) |original_data| {
        // Create frame
        const frame = try engine.createMessageFrame(original_data, false);
        defer allocator.free(frame);

        // Parse it back
        var buf_stream = std.io.fixedBufferStream(frame);
        const reader = buf_stream.reader();
        const parsed = try engine.parseFrame(reader.any());
        defer allocator.free(parsed.data);

        // Verify roundtrip
        try testing.expectEqualSlices(u8, original_data, parsed.data);
        try testing.expectEqual(false, parsed.more);
    }
}
