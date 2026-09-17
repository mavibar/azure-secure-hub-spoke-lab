"""Tiny TCP test listener. No HTTP, TLS, SQL, login or exploit functionality."""
import argparse
import socketserver


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--role", choices=("web", "app", "data"), required=True)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("port must be between 1 and 65535")
    greeting = f"LAB_OK:{args.role}\n".encode("ascii")

    class Handler(socketserver.BaseRequestHandler):
        def handle(self):
            self.request.settimeout(3)
            self.request.sendall(greeting)

    class Server(socketserver.ThreadingTCPServer):
        allow_reuse_address = True
        daemon_threads = True

    with Server((args.bind, args.port), Handler) as server:
        server.serve_forever()


if __name__ == "__main__":
    main()
