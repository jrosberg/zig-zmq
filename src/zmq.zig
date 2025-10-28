//! ZeroMQ implementation in Zig
//! Copyright (c) 2025 Janne Rosberg <janne.rosberg@offcode.fi>
//! License: MIT
//! See the LICENSE file for details.
//!
//! This is the main module that re-exports all public APIs from the zmq library.

// Re-export types
pub const SocketType = @import("zmq/types.zig").SocketType;

// Re-export protocol types
pub const Greeting = @import("zmq/protocol.zig").Greeting;
pub const ZmqCommand = @import("zmq/protocol.zig").ZmqCommand;

// Re-export Context and Socket
pub const Context = @import("zmq/context.zig").Context;
pub const Socket = @import("zmq/socket.zig").Socket;
pub const SendFlags = @import("zmq/socket.zig").SendFlags;

// Re-export ZMTP (low-level protocol, useful for debugging)
pub const zmtp = @import("zmq/zmtp.zig");

// For backward compatibility
const std = @import("std");

// Run tests from all modules
test {
    std.testing.refAllDecls(@This());
    _ = @import("zmq/types.zig");
    _ = @import("zmq/protocol.zig");
    _ = @import("zmq/context.zig");
    _ = @import("zmq/socket.zig");
    _ = @import("zmq/zmtp.zig");
}
