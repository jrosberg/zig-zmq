//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");
const types = @import("types.zig");
const protocol = @import("protocol.zig");
const Socket = @import("socket.zig").Socket;

const SocketType = types.SocketType;

/// ZeroMQ Context - manages sockets and shared resources
pub const Context = struct {
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !*Self {
        const ctx = try allocator.create(Self);
        ctx.* = .{ .allocator = allocator };
        protocol.ZmqCommand.setAllocator(allocator);
        return ctx;
    }

    pub fn deinit(self: *Self) void {
        self.allocator.destroy(self);
    }

    pub fn socket(self: *Self, socket_type: SocketType) !*Socket {
        return Socket.init(self.allocator, socket_type);
    }
};
