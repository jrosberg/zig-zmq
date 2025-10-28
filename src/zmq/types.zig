//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");

pub const SocketType = enum(u8) {
    PAIR = 0,
    PUB = 1,
    SUB = 2,
    REQ = 3,
    REP = 4,
    DEALER = 5,
    ROUTER = 6,
    PULL = 7,
    PUSH = 8,
    XPUB = 9,
    XSUB = 10,
    STREAM = 11,

    pub fn asString(self: SocketType) [:0]const u8 {
        return @tagName(self);
    }
};

// Tests
const testing = std.testing;

test "SocketType enum values" {
    // Verify enum values match ZeroMQ specification
    try testing.expectEqual(@as(u8, 0), @intFromEnum(SocketType.PAIR));
    try testing.expectEqual(@as(u8, 1), @intFromEnum(SocketType.PUB));
    try testing.expectEqual(@as(u8, 2), @intFromEnum(SocketType.SUB));
    try testing.expectEqual(@as(u8, 3), @intFromEnum(SocketType.REQ));
    try testing.expectEqual(@as(u8, 4), @intFromEnum(SocketType.REP));
    try testing.expectEqual(@as(u8, 5), @intFromEnum(SocketType.DEALER));
    try testing.expectEqual(@as(u8, 6), @intFromEnum(SocketType.ROUTER));
    try testing.expectEqual(@as(u8, 7), @intFromEnum(SocketType.PULL));
    try testing.expectEqual(@as(u8, 8), @intFromEnum(SocketType.PUSH));
    try testing.expectEqual(@as(u8, 9), @intFromEnum(SocketType.XPUB));
    try testing.expectEqual(@as(u8, 10), @intFromEnum(SocketType.XSUB));
    try testing.expectEqual(@as(u8, 11), @intFromEnum(SocketType.STREAM));
}

test "SocketType asString" {
    try testing.expectEqualStrings("PAIR", SocketType.PAIR.asString());
    try testing.expectEqualStrings("PUB", SocketType.PUB.asString());
    try testing.expectEqualStrings("SUB", SocketType.SUB.asString());
    try testing.expectEqualStrings("REQ", SocketType.REQ.asString());
    try testing.expectEqualStrings("REP", SocketType.REP.asString());
    try testing.expectEqualStrings("DEALER", SocketType.DEALER.asString());
    try testing.expectEqualStrings("ROUTER", SocketType.ROUTER.asString());
    try testing.expectEqualStrings("PULL", SocketType.PULL.asString());
    try testing.expectEqualStrings("PUSH", SocketType.PUSH.asString());
    try testing.expectEqualStrings("XPUB", SocketType.XPUB.asString());
    try testing.expectEqualStrings("XSUB", SocketType.XSUB.asString());
    try testing.expectEqualStrings("STREAM", SocketType.STREAM.asString());
}

test "SocketType string is null-terminated" {
    // Verify that asString returns a null-terminated string
    const pub_str = SocketType.PUB.asString();
    try testing.expectEqual(@as(usize, 3), pub_str.len);
    try testing.expectEqual(@as(u8, 0), pub_str.ptr[pub_str.len]); // Check null terminator
}

test "SocketType from int" {
    // Test casting from u8 to SocketType
    const pub_type: SocketType = @enumFromInt(1);
    try testing.expectEqual(SocketType.PUB, pub_type);

    const req_type: SocketType = @enumFromInt(3);
    try testing.expectEqual(SocketType.REQ, req_type);

    const rep_type: SocketType = @enumFromInt(4);
    try testing.expectEqual(SocketType.REP, rep_type);
}

test "SocketType roundtrip conversion" {
    // Test that we can convert to int and back
    const original = SocketType.SUB;
    const as_int = @intFromEnum(original);
    const back_to_enum: SocketType = @enumFromInt(as_int);
    try testing.expectEqual(original, back_to_enum);
}
