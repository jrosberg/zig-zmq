#!/usr/bin/env python3
"""
Test ZMQ REQ client to verify the server works with a standard ZMQ client.
"""

import zmq
import sys

def main():
    context = zmq.Context()
    socket = context.socket(zmq.REQ)

    print("=" * 60)
    print("ZMQ REQ Test Client")
    print("=" * 60)
    print(f"Connecting to: tcp://127.0.0.1:42123")
    print(f"ZMQ Version: {zmq.zmq_version()}")
    print(f"PyZMQ Version: {zmq.pyzmq_version()}")
    print("=" * 60)

    socket.connect("tcp://127.0.0.1:42123")

    print("\nConnected! Sending test message...\n")

    # Send message
    message = b"Hello ZeroMQ"
    print(f"Sending: {message.decode()}")
    print(f"    Length: {len(message)} bytes")
    print(f"    Hex: {message.hex()}")

    socket.send(message)
    print("✓ Message sent")

    # Receive reply
    print("\nWaiting for reply...")
    reply = socket.recv()

    print(f"✓ Received reply: {reply.decode()}")
    print(f"    Length: {len(reply)} bytes")
    print(f"    Hex: {reply.hex()}")

    print("\n" + "=" * 60)
    print("Success! REQ/REP communication works.")
    print("=" * 60)

    socket.close()
    context.term()

if __name__ == "__main__":
    main()
