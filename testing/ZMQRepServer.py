import zmq
import time

def main():
    # Create ZMQ context and socket
    context = zmq.Context()
    socket = context.socket(zmq.REP)  # REP socket pairs with REQ
    
    # Bind to the address your Zig client connects to
    socket.bind("tcp://127.0.0.1:42123")
    
    print("ZMQ REP server listening on tcp://127.0.0.1:42123")
    print("Waiting for connections...")

    # Add debug flag
    socket.setsockopt(zmq.LINGER, 0)

    try:
        while True:
            print("DEBUG: About to call recv()...")
            message = socket.recv()
            print(f"Received request: {message}")
            print(f"Raw bytes: {message.hex()}")

            reply = b"World"
            socket.send(reply)
            print(f"Sent reply: {reply}")

    except KeyboardInterrupt:
        print("\nShutting down server...")
    finally:
        socket.close()
        context.term()


if __name__ == "__main__":
    main()
