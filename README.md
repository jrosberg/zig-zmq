# zmq.zig

A pure Zig implementation of ZeroMQ with ZMTP 3.1 protocol support.

Note that this is an experimental implementation intended for learning and exploration purposes. It may not cover all edge cases or be suitable for production use.

## Features

- **ZMTP 3.1 Protocol**: Full implementation of ZeroMQ Message Transport Protocol
- **Socket Types**: REQ/REP (request-reply) and PUB/SUB (publish-subscribe) patterns
- **Multi-Connection Support**: PUB sockets support multiple concurrent subscribers
- **Subscription Filtering**: Topic-based message filtering for PUB/SUB
- **Python Interoperability**: Full compatibility with PyZMQ clients
- **NULL Security**: ZMTP 3.1 NULL mechanism (no security)

## Requirements

- Zig 0.15.2
- Python 3.x with PyZMQ (optional, for interoperability tests)

## Installation

```bash
# Clone the repository
git clone <repository-url>
cd zmq.zig

# Build the project
zig build

# Run tests
zig build test
```

## Quick Start

### REQ/REP Pattern (Request-Reply)

**Server (REP):**
```zig
const std = @import("std");
const zmq = @import("zmq");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    const ctx = try zmq.Context.init(allocator);
    defer ctx.deinit();

    const sock = try ctx.socket(.REP);
    defer sock.close();

    try sock.bind("tcp://*:42123");
    try sock.accept();

    var buffer: [512]u8 = undefined;
    while (true) {
        const len = try sock.recv(&buffer, 0);
        std.debug.print("Received: {s}\n", .{buffer[0..len]});

        try sock.send("Reply message", .{});
    }
}
```

**Client (REQ):**
```zig
const ctx = try zmq.Context.init(allocator);
defer ctx.deinit();

const sock = try ctx.socket(.REQ);
defer sock.close();

try sock.connect("tcp://127.0.0.1:42123");

try sock.send("Hello server", .{});

var buffer: [512]u8 = undefined;
const len = try sock.recv(&buffer, 0);
std.debug.print("Got reply: {s}\n", .{buffer[0..len]});
```

### PUB/SUB Pattern (Publish-Subscribe)

**Publisher (PUB):**
```zig
const ctx = try zmq.Context.init(allocator);
defer ctx.deinit();

const sock = try ctx.socket(.PUB);
defer sock.close();

try sock.bind("tcp://*:5555");
try sock.accept();

// Publish messages with topics
try sock.send("weather Temperature: 25°C", .{});
try sock.send("news Breaking news!", .{});
```

**Subscriber (SUB):**
```zig
const ctx = try zmq.Context.init(allocator);
defer ctx.deinit();

const sock = try ctx.socket(.SUB);
defer sock.close();

try sock.connect("tcp://127.0.0.1:5555");

// Subscribe to specific topics
try sock.subscribe("weather");
try sock.subscribe("news");
// Or subscribe to all messages
// try sock.subscribe("");

var buffer: [512]u8 = undefined;
while (true) {
    const len = try sock.recv(&buffer, 0);
    std.debug.print("Received: {s}\n", .{buffer[0..len]});
}
```

## API Reference

### Context

```zig
// Create a new context
const ctx = try zmq.Context.init(allocator);
defer ctx.deinit();

// Create a socket
const sock = try ctx.socket(.REQ);  // or .REP, .PUB, .SUB
```

### Socket Operations

```zig
// Binding (server mode)
try sock.bind("tcp://*:5555");
try sock.accept();  // Accept connections

// Connecting (client mode)
try sock.connect("tcp://127.0.0.1:5555");

// Sending
try sock.send("message", .{});

// Receiving
var buffer: [1024]u8 = undefined;
const len = try sock.recv(&buffer, 0);

// Subscription (SUB sockets only)
try sock.subscribe("topic");      // Subscribe to topic
try sock.unsubscribe("topic");    // Unsubscribe
try sock.subscribe("");           // Subscribe to all
```

### Socket Types

- `SocketType.REQ` - Request socket (client)
- `SocketType.REP` - Reply socket (server)
- `SocketType.PUB` - Publisher socket (broadcasts)
- `SocketType.SUB` - Subscriber socket (receives filtered)

### SendFlags

```zig
// Default (blocking)
try sock.send("message", .{});

// With flags
try sock.send("message", .{ .dontwait = true });
try sock.send("message", .{ .sndmore = true });
try sock.send("message", .{ .dontwait = true, .sndmore = true });
```

Available flags:
- `dontwait`: Non-blocking send (ZMQ_DONTWAIT)
- `sndmore`: More message parts follow (ZMQ_SNDMORE)

## Project Structure

```
zmq.zig/
├── src/
│   ├── zmq.zig           # Main module exports
│   ├── main.zig          # Example REQ client
│   └── zmq/
│       ├── context.zig   # Context management
│       ├── socket.zig    # Socket implementation
│       ├── types.zig     # Socket types and enums
│       ├── protocol.zig  # ZMTP protocol (Greeting, Commands)
│       └── zmtp.zig      # Frame engine and ZMTP details
├── examples/
│   ├── rep_server.zig    # REP server example
│   ├── pub_server.zig    # PUB server example
│   ├── pub_multi_server.zig  # Multi-connection PUB
│   ├── sub_client.zig    # SUB client example
│   └── simple_multi.zig  # Simple multi-connection demo
├── testing/
│   ├── test_bind.sh      # Automated test suite
│   ├── test_zmq_client.py    # Python REQ client
│   ├── test_zmq_server.py    # Python REP server
│   ├── ZMQSubClient.py   # Python SUB client
│   └── ZMQPubServer.py   # Python PUB server
└── build.zig             # Build configuration
```

## Build Commands

```bash
# Build all
zig build

# Run examples
zig build run          # REQ client
zig build run-rep      # REP server
zig build run-pub      # PUB server
zig build run-sub      # SUB client

# Run tests
zig build test
./testing/test_bind.sh  # Full test suite with Python interop
```

## Testing

The project includes comprehensive tests:

```bash
# Automated test suite
./testing/test_bind.sh

# Individual tests
./testing/test_multi_connection.sh
./testing/test_pubsub.sh
```

Tests validate:
- ✅ REQ/REP pattern (Zig-to-Zig)
- ✅ PUB/SUB pattern (Zig-to-Zig)
- ✅ Python REQ client → Zig REP server
- ✅ Python SUB client → Zig PUB server
- ✅ Multi-connection support
- ✅ Subscription filtering

## Python Interoperability

This implementation is compatible with PyZMQ:

```python
# Python client connecting to Zig server
import zmq

context = zmq.Context()
socket = context.socket(zmq.REQ)
socket.connect("tcp://localhost:42123")

socket.send(b"Hello from Python")
reply = socket.recv()
print(f"Reply: {reply}")
```

## Implementation Details

### ZMTP 3.1 Protocol

- Full ZMTP 3.1 handshake (greeting + READY command)
- NULL security mechanism
- Message framing with proper flags (MORE, COMMAND)
- Compatible with ZeroMQ 4.x implementations

### Socket Behavior

- **REP/REQ**: Blocking I/O for reliable request-reply
- **PUB/SUB**: Non-blocking I/O for PUB with subscription harvesting
- **Multi-connection**: PUB sockets support multiple subscribers
- **Topic filtering**: Prefix-based topic matching for subscriptions

## Limitations

- Only NULL security mechanism supported
- No CURVE, PLAIN, or GSSAPI security
- Limited to TCP transport (no IPC, inproc, PGM)
- Some advanced ZeroMQ features not implemented

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Please ensure:
- Code follows Zig style guidelines
- Tests pass (`zig build test` and `./testing/test_bind.sh`)
- New features include tests and documentation

## References

- [ZMTP 3.1 Specification](https://rfc.zeromq.org/spec/23/)
- [ZeroMQ Guide](https://zguide.zeromq.org/)
- [PyZMQ Documentation](https://pyzmq.readthedocs.io/)

---

**Note**: This is a learning/experimental implementation. For production use, consider using the official ZeroMQ C library with Zig bindings.
