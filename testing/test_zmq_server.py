#!/usr/bin/env python3
"""
Test ZMQ REP server with detailed logging to debug ZMTP protocol communication.
"""

import zmq
import sys

def main():
    context = zmq.Context()
    socket = context.socket(zmq.REP)

    # Set socket options for debugging
    socket.setsockopt(zmq.LINGER, 0)
    socket.setsockopt(zmq.RCVTIMEO, 5000)  # 5 second timeout

    socket.bind("tcp://127.0.0.1:42123")

    print("=" * 60)
    print("ZMQ REP Test Server")
    print("=" * 60)
    print(f"Listening on: tcp://127.0.0.1:42123")
    print(f"ZMQ Version: {zmq.zmq_version()}")
    print(f"PyZMQ Version: {zmq.pyzmq_version()}")
    print("=" * 60)
    print("\nWaiting for connections...\n")

    message_count = 0

    try:
        while True:
            print(f"\n[{message_count}] Calling recv()...")

            try:
                message = socket.recv()
                message_count += 1

                print(f"[{message_count}] ✓ Received message!")
                print(f"    Length: {len(message)} bytes")
                print(f"    Hex: {message.hex()}")
                print(f"    Text: {message.decode('utf-8', errors='replace')}")

                # Send reply
                reply = b"World"
                socket.send(reply)
                print(f"[{message_count}] ✓ Sent reply: {reply.decode()}")

            except zmq.Again:
                print(f"[{message_count}] Timeout waiting for message (5s)")
                continue

    except KeyboardInterrupt:
        print("\n\n" + "=" * 60)
        print("Server shutting down...")
        print(f"Total messages processed: {message_count}")
        print("=" * 60)

    finally:
        socket.close()
        context.term()

if __name__ == "__main__":
    main()
