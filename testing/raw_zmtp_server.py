#!/usr/bin/env python3
"""
Raw ZMTP 3.1 server implementation for testing our Zig ZMTP client.
This implements the protocol at the TCP level, not using libzmq.
"""

import socket
import struct
import sys

def send_all(sock, data):
    """Send all data"""
    total_sent = 0
    while total_sent < len(data):
        sent = sock.send(data[total_sent:])
        if sent == 0:
            raise RuntimeError("socket connection broken")
        total_sent += sent

def recv_exact(sock, n):
    """Receive exactly n bytes"""
    data = b''
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise RuntimeError("socket connection broken")
        data += chunk
    return data

def send_greeting(sock):
    """Send ZMTP 3.1 greeting"""
    greeting = bytearray(64)
    greeting[0] = 0xff
    greeting[9] = 0x7f
    greeting[10] = 3  # version major
    greeting[11] = 1  # version minor
    greeting[12:16] = b'NULL'  # mechanism
    greeting[32] = 1  # as_server = true
    send_all(sock, greeting)
    print("✓ Sent greeting (ZMTP 3.1, NULL mechanism, as_server=true)")

def recv_greeting(sock):
    """Receive and parse ZMTP greeting"""
    greeting = recv_exact(sock, 64)

    if greeting[0] != 0xff or greeting[9] != 0x7f:
        raise ValueError("Invalid greeting signature")

    version_major = greeting[10]
    version_minor = greeting[11]
    mechanism = greeting[12:32].rstrip(b'\x00').decode('ascii')
    as_server = greeting[32] == 1

    print(f"✓ Received greeting: version {version_major}.{version_minor}, mechanism {mechanism}, as_server={as_server}")
    return version_major, version_minor, mechanism

def send_ready_command(sock):
    """Send READY command"""
    # Build READY command
    command_name = b'READY'
    property_name = b'Socket-Type'
    property_value = b'REP'

    # Calculate payload size
    payload_size = 1 + len(command_name) + 1 + len(property_name) + 4 + len(property_value)

    # Build frame
    frame = bytearray()
    frame.append(0x04)  # command flag
    frame.append(payload_size)  # size
    frame.append(len(command_name))  # command name length
    frame.extend(command_name)  # command name
    frame.append(len(property_name))  # property name length
    frame.extend(property_name)  # property name
    frame.extend(struct.pack('>I', len(property_value)))  # property value length (big-endian)
    frame.extend(property_value)  # property value

    send_all(sock, frame)
    print(f"✓ Sent READY command ({len(frame)} bytes): {frame.hex()}")

def recv_ready_command(sock):
    """Receive and parse READY command"""
    # Read frame header
    header = recv_exact(sock, 2)
    flags = header[0]
    size = header[1]

    print(f"  Received frame: flags=0x{flags:02x}, size={size}")

    if flags != 0x04:
        raise ValueError(f"Expected command frame, got flags=0x{flags:02x}")

    # Read payload
    payload = recv_exact(sock, size)
    print(f"✓ Received READY command ({size} bytes payload): {(header + payload).hex()}")

    # Parse command name
    cmd_name_len = payload[0]
    cmd_name = payload[1:1+cmd_name_len].decode('ascii')

    if cmd_name != 'READY':
        raise ValueError(f"Expected READY, got {cmd_name}")

    print(f"  Command: {cmd_name}")

def recv_message(sock):
    """Receive a complete ZMTP message (multiple frames)"""
    frames = []
    frame_num = 0

    while True:
        frame_num += 1

        # Read frame header
        header = recv_exact(sock, 2)
        flags = header[0]
        size = header[1]

        has_more = (flags & 0x01) != 0
        is_long = (flags & 0x02) != 0

        if is_long:
            # Read 8-byte size
            size_bytes = recv_exact(sock, 8)
            size = struct.unpack('>Q', size_bytes)[0]

        print(f"  Frame #{frame_num}: flags=0x{flags:02x}, size={size}, more={has_more}")

        # Read frame data
        if size > 0:
            data = recv_exact(sock, size)
            frames.append(data)
            print(f"    Data: {data.hex()} = {data.decode('utf-8', errors='replace')}")
        else:
            frames.append(b'')
            print(f"    Data: (empty)")

        if not has_more:
            break

    return frames

def send_message(sock, data):
    """Send a message with REP socket pattern (delimiter + data)"""
    print(f"\nSending reply...")

    # Frame 1: Empty delimiter with MORE flag
    frame1 = bytes([0x01, 0x00])  # MORE flag, size 0
    send_all(sock, frame1)
    print(f"  Frame 1: {frame1.hex()} (delimiter)")

    # Frame 2: Data with LAST flag
    frame2 = bytes([0x00, len(data)]) + data  # LAST flag, size, data
    send_all(sock, frame2)
    print(f"  Frame 2: {frame2.hex()} (data)")

    print(f"✓ Sent message ({len(frame1) + len(frame2)} bytes total)")

def handle_client(client_sock, addr):
    """Handle a client connection"""
    print(f"\n{'='*60}")
    print(f"New connection from {addr}")
    print(f"{'='*60}\n")

    try:
        # ZMTP handshake
        print("=== Handshake Phase ===")
        send_greeting(client_sock)
        recv_greeting(client_sock)

        send_ready_command(client_sock)
        recv_ready_command(client_sock)

        print(f"\n{'='*60}")
        print("✓ Handshake complete! Ready for messages.")
        print(f"{'='*60}\n")

        # Message exchange
        print("=== Message Phase ===")
        print("\nWaiting for message...")
        frames = recv_message(client_sock)

        print(f"\n✓ Received complete message with {len(frames)} frame(s)")

        # Extract message data (skip empty delimiter frames)
        message_data = b''.join(f for f in frames if f)
        print(f"  Message data: {message_data.decode('utf-8', errors='replace')}")

        # Send reply
        reply = b"World"
        send_message(client_sock, reply)

        print(f"\n{'='*60}")
        print("✓ Message exchange complete!")
        print(f"{'='*60}\n")

    except Exception as e:
        print(f"\n❌ Error: {e}")
        import traceback
        traceback.print_exc()

    finally:
        client_sock.close()
        print(f"Connection closed: {addr}\n")

def main():
    server_sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_sock.bind(('127.0.0.1', 42123))
    server_sock.listen(1)

    print("=" * 60)
    print("Raw ZMTP 3.1 Test Server")
    print("=" * 60)
    print("Listening on: tcp://127.0.0.1:42123")
    print("Protocol: ZMTP 3.1, NULL mechanism, REP socket")
    print("=" * 60)
    print("\nWaiting for connections...\n")

    try:
        while True:
            client_sock, addr = server_sock.accept()
            handle_client(client_sock, addr)
    except KeyboardInterrupt:
        print("\n\nServer shutting down...")
    finally:
        server_sock.close()

if __name__ == "__main__":
    main()
