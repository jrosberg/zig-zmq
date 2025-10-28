#!/usr/bin/env python3
"""
ZeroMQ SUB Client for testing Zig PUB server implementation.
This client connects to tcp://127.0.0.1:5555 and subscribes to messages.
"""

import zmq
import sys


def main():
    print("=== ZeroMQ SUB Client (Python) ===")

    # Create context and SUB socket
    context = zmq.Context()
    socket = context.socket(zmq.SUB)

    # Connect to publisher
    endpoint = "tcp://127.0.0.1:5555"
    socket.connect(endpoint)
    print(f"Connected to publisher at {endpoint}")

    # Subscribe to topics
    # Subscribe to all messages (empty string means all)
    socket.subscribe("")
    print("Subscribed to all messages")

    # Alternatively, subscribe to specific topics:
    # socket.subscribe(b"weather")
    # socket.subscribe(b"news")
    # print("Subscribed to: weather, news")

    print("Waiting for messages... (Press Ctrl+C to exit)\n")

    try:
        count = 0
        while True:
            # Receive message
            message = socket.recv_string()
            count += 1
            print(f"[{count}] Received: {message}")

    except KeyboardInterrupt:
        print("\n\nShutting down subscriber...")
    finally:
        socket.close()
        context.term()
        print("Subscriber closed.")


if __name__ == "__main__":
    main()
