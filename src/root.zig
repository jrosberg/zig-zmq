//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.

const std = @import("std");

// Re-export the zmq module
pub const Context = @import("zmq.zig").Context;
pub const Socket = @import("zmq.zig").Socket;
pub const SocketType = @import("zmq.zig").SocketType;
pub const Greeting = @import("zmq.zig").Greeting;
pub const ZmqCommand = @import("zmq.zig").ZmqCommand;

test {
    std.testing.refAllDecls(@This());
}
