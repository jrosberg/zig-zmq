//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");
const zmtp = @import("zmtp.zig");
const types = @import("types.zig");
const SocketType = types.SocketType;

pub const Greeting = struct {
    pub const greet_size = 64;

    version: zmtp.ZmtpVersion,
    mechanism: zmtp.Mechanism,
    as_server: bool,

    pub fn init() Greeting {
        return Greeting{
            .version = zmtp.ZmtpVersion{ 3, 1 },
            .mechanism = .null,
            .as_server = false,
        };
    }

    pub fn toSlice(self: *Greeting) [greet_size]u8 {
        var greet = [_]u8{0} ** greet_size;
        var s: []u8 = &greet;
        s[0] = 0xff;
        s[9] = 0x7f;
        s[10] = self.version.@"0";
        s[11] = self.version.@"1";
        const mech = self.mechanism.asSlice();
        @memcpy(s[12 .. 12 + mech.len], mech);
        s[32] = if (self.as_server) 0x01 else 0x00;
        return greet;
    }

    pub fn fromSlice(s: []const u8) !Greeting {
        var greet = Greeting.init();
        greet.version.@"0" = s[10];
        greet.version.@"1" = s[11];
        const mech = zmtp.Mechanism.from(s[12..31]) catch |err| {
            std.debug.print("Error: {any}\n", .{err});
            return err;
        };
        greet.mechanism = mech;
        return greet;
    }
};

const ZmqCommandName = enum {
    READY,
    ERROR,
    SUBSCRIBE,
    CANCEL,
    PING,
    PONG,

    pub fn string(self: ZmqCommandName) [:0]const u8 {
        return @tagName(self);
    }
};

pub const ZmqCommand = struct {
    name: ZmqCommandName,
    properties: std.StringHashMap([]const u8),
    frame_buffer: [256]u8 = undefined, // Buffer to store the frame
    frame_len: usize = 0, // Actual frame length

    const Self = @This();
    var map_allocator: ?std.mem.Allocator = null;

    /// set allocator to be used for all commands
    pub fn setAllocator(allocator: std.mem.Allocator) void {
        if (map_allocator == null) {
            map_allocator = allocator;
        } else {
            @panic("Don't be stupid!");
        }
    }

    pub fn ready(socket: SocketType) ZmqCommand {
        const hmap = std.StringHashMap([]const u8);
        var map = hmap.init(map_allocator.?);
        map.put("Socket-Type", socket.asString()) catch |err| {
            std.debug.print("Error: {any}\n", .{err});
        };

        //std.log.info("map: {any}\n", .{map});

        return ZmqCommand{
            .name = ZmqCommandName.READY,
            .properties = map,
        };
    }

    pub fn toFrame(self: *Self) []u8 {
        // TODO: refactor to frameEngine
        // calc needed frame size (payload only, not including frame header)
        var size: usize = 0;
        size += 1 + self.name.string().len; // command name length byte + command name
        // NO property count in ZMTP 3.x
        var iter = self.properties.iterator();
        while (iter.next()) |kv| {
            size += 1 + kv.key_ptr.len; // property name length byte + name
            size += 4 + kv.value_ptr.len; // property value length (4 bytes) + value
        }

        var pos: usize = 0;

        self.frame_buffer[0] = zmtp.ZmtpFrame.flag_command;

        if (size > 255) {
            self.frame_buffer[0] |= zmtp.ZmtpFrame.flag_long;
            std.mem.writeInt(u64, self.frame_buffer[1..9], size, .big);
            pos += 9;
        } else {
            self.frame_buffer[1] = @intCast(size); // total frame size
            pos += 2;
        }
        self.frame_buffer[pos] = @intCast(self.name.string().len); // command name size
        pos += 1;
        @memcpy(self.frame_buffer[pos .. pos + self.name.string().len], self.name.string());
        pos += self.name.string().len;

        // NOTE: Property count is NOT included in ZMTP 3.x READY command
        // The server also doesn't send it, so we match that behavior

        // add properties
        var iter2 = self.properties.iterator();

        while (iter2.next()) |kv| {
            self.frame_buffer[pos] = @intCast(kv.key_ptr.len);
            pos += 1;
            @memcpy(self.frame_buffer[pos .. pos + kv.key_ptr.len], kv.key_ptr.ptr);
            pos += kv.key_ptr.len;
            const len_slice = self.frame_buffer[pos .. pos + 4];
            std.mem.writeInt(u32, @ptrCast(len_slice), @intCast(kv.value_ptr.len), .big);
            pos += 4;
            @memcpy(self.frame_buffer[pos .. pos + kv.value_ptr.len], kv.value_ptr.ptr);
            pos += kv.value_ptr.len;
        }

        // Store the frame length
        self.frame_len = pos;

        // pos now points to the end of the frame
        std.log.info("Command Frame ({d} bytes total, {d} byte payload): {x}\n", .{ pos, size, self.frame_buffer[0..pos] });

        return self.frame_buffer[0..self.frame_len];
    }

    pub fn fromSlice(data: []const u8) !ZmqCommand {
        if (data.len < 2) {
            return zmtp.ZmtpError.badCommand;
        }
        var pos: usize = 0;
        const flags = data[0];
        pos += 1;
        if (flags & zmtp.ZmtpFrame.flag_command == 0) {
            return zmtp.ZmtpError.badCommand;
        }
        var payload_size: usize = 0;
        if (flags & zmtp.ZmtpFrame.flag_long != 0) {
            if (data.len < 10) {
                return zmtp.ZmtpError.badCommand;
            }
            payload_size = std.mem.readInt(u64, data[1..9], .big);
            pos += 8;
        } else {
            payload_size = @intCast(data[1]);
            pos += 1;
        }
        // data len should be 1 + payload_size
        const cmd_name_size: usize = @intCast(data[pos]);
        pos += 1;
        const cmd_name = data[pos .. pos + cmd_name_size];
        const cmdname = std.meta.stringToEnum(ZmqCommandName, cmd_name) orelse {
            std.log.warn("Unknown command: {s}\n", .{cmd_name});
            return zmtp.ZmtpError.badCommand;
        };

        const hmap = std.StringHashMap([]const u8);
        const map = hmap.init(map_allocator.?);

        const cmd = ZmqCommand{
            .name = cmdname,
            .properties = map,
        };

        return cmd;
    }

    pub fn deinit(self: *Self) void {
        self.properties.deinit();
        self.* = undefined;
    }
};

// Tests
const testing = std.testing;

test "Greeting init and toSlice" {
    var greeting = Greeting.init();
    const slice = greeting.toSlice();

    // Check signature bytes
    try testing.expectEqual(@as(u8, 0xff), slice[0]);
    try testing.expectEqual(@as(u8, 0x7f), slice[9]);

    // Check version
    try testing.expectEqual(@as(u8, 3), slice[10]);
    try testing.expectEqual(@as(u8, 1), slice[11]);

    // Check as_server flag
    try testing.expectEqual(@as(u8, 0x00), slice[32]);
}

test "Greeting fromSlice" {
    var greeting = Greeting.init();
    greeting.as_server = true;
    const slice = greeting.toSlice();

    const parsed = try Greeting.fromSlice(&slice);
    try testing.expectEqual(@as(u8, 3), parsed.version.@"0");
    try testing.expectEqual(@as(u8, 1), parsed.version.@"1");
    try testing.expectEqual(zmtp.Mechanism.null, parsed.mechanism);
}

test "ZmqCommand ready creation and operations" {
    const allocator = testing.allocator;

    // Set allocator only once for all ZmqCommand tests
    if (ZmqCommand.map_allocator == null) {
        ZmqCommand.setAllocator(allocator);
    }

    // Test 1: Create READY command
    {
        var cmd = ZmqCommand.ready(.PUB);
        defer cmd.deinit();

        try testing.expectEqual(ZmqCommandName.READY, cmd.name);
        try testing.expect(cmd.properties.count() > 0);

        const socket_type = cmd.properties.get("Socket-Type");
        try testing.expect(socket_type != null);
        try testing.expectEqualStrings("PUB", socket_type.?);
    }

    // Test 2: Convert to frame
    {
        var cmd = ZmqCommand.ready(.REQ);
        defer cmd.deinit();

        const frame = cmd.toFrame();

        // Frame should have command flag
        try testing.expect((frame[0] & zmtp.ZmtpFrame.flag_command) != 0);
        try testing.expect(frame.len > 2);
        try testing.expect(frame.len == cmd.frame_len);
    }

    // Test 3: Parse from slice
    {
        var cmd1 = ZmqCommand.ready(.SUB);
        defer cmd1.deinit();

        const frame = cmd1.toFrame();

        // Parse it back
        var cmd2 = try ZmqCommand.fromSlice(frame);
        defer cmd2.deinit();

        try testing.expectEqual(ZmqCommandName.READY, cmd2.name);
    }
}

test "Greeting roundtrip" {
    var greeting1 = Greeting.init();
    greeting1.as_server = true;
    greeting1.version = .{ 3, 1 };

    const slice = greeting1.toSlice();
    const greeting2 = try Greeting.fromSlice(&slice);

    try testing.expectEqual(greeting1.version.@"0", greeting2.version.@"0");
    try testing.expectEqual(greeting1.version.@"1", greeting2.version.@"1");
    try testing.expectEqual(greeting1.mechanism, greeting2.mechanism);
}
