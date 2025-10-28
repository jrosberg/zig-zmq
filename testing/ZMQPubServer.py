#!/usr/bin/env python3
"""
ZeroMQ PUB Server for testing Zig SUB client implementation.
This server binds to tcp://127.0.0.1:5555 and publishes messages with different topics.
"""

import zmq
import time
import sys


def main():
    print("=== ZeroMQ PUB Server (Python) ===")

    # Create context and PUB socket
    context = zmq.Context()
    socket = context.socket(zmq.PUB)

    # Bind to endpoint
    endpoint = "tcp://127.0.0.1:5555"
    socket.bind(endpoint)
    print(f"Publisher bound to {endpoint}")
    print("Publishing messages... (Press Ctrl+C to exit)\n")

    # Give subscribers time to connect
    time.sleep(1)

    try:
        count = 0
        while True:
            # Publish weather updates
            weather_msg = f"weather Temperature: {20 + (count % 10)}°C, Humidity: {50 + (count % 30)}%"
            socket.send_string(weather_msg)
            print(f"[{count * 3}] Published: {weather_msg}")

            time.sleep(0.5)

            # Publish news updates
            news_msg = f"news Breaking news #{count}: Important event occurred"
            socket.send_string(news_msg)
            print(f"[{count * 3 + 1}] Published: {news_msg}")

            time.sleep(0.5)

            # Publish sports updates
            sports_msg = f"sports Game {count}: Team A vs Team B"
            socket.send_string(sports_msg)
            print(f"[{count * 3 + 2}] Published: {sports_msg}")

            time.sleep(0.5)

            count += 1

    except KeyboardInterrupt:
        print("\n\nShutting down publisher...")
    finally:
        socket.close()
        context.term()
        print("Publisher closed.")


if __name__ == "__main__":
    main()
