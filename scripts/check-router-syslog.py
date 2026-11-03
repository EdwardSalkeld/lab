#!/usr/bin/env python3
"""Check rendered router syslog with real Alloy and loopback UDP packets."""

import argparse
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import urllib.request


def free_port(kind):
    with socket.socket(socket.AF_INET, kind) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--alloy", required=True)
    parser.add_argument("--config", type=Path, required=True)
    args = parser.parse_args()
    source = args.config.read_text()
    with tempfile.TemporaryDirectory(prefix="router-syslog-test-") as directory:
        root = Path(directory)
        production = root / "production.alloy"
        production.write_text(
            source
            + '\nloki.write "default" { endpoint { url = "http://127.0.0.1:3100/loki/api/v1/push" } }\n'
        )
        subprocess.run([args.alloy, "validate", str(production)], check=True)
        udp_port = free_port(socket.SOCK_DGRAM)
        http_port = free_port(socket.SOCK_STREAM)
        # Keep the rendered pipeline; change only socket addresses and the sink.
        test_config = (
            source.replace('"0.0.0.0:1514"', f'"127.0.0.1:{udp_port}"')
            .replace('"10[.]4[.]1[.]2"', '"127[.]0[.]0[.]1"')
            .replace("loki.write.default.receiver", "loki.echo.verify.receiver")
        )
        config = root / "test.alloy"
        config.write_text(test_config + '\nloki.echo "verify" {}\n')
        output = root / "output.log"
        with output.open("w") as log:
            proc = subprocess.Popen(
                [
                    args.alloy,
                    "run",
                    str(config),
                    "--storage.path=" + str(root / "state"),
                    f"--server.http.listen-addr=127.0.0.1:{http_port}",
                    "--disable-reporting",
                ],
                stdout=log,
                stderr=subprocess.STDOUT,
            )
            try:
                deadline = time.monotonic() + 15
                while True:
                    try:
                        urllib.request.urlopen(
                            f"http://127.0.0.1:{http_port}/-/ready", timeout=1
                        ).close()
                        break
                    except OSError:
                        if time.monotonic() > deadline or proc.poll() is not None:
                            raise RuntimeError(output.read_text())
                        time.sleep(0.1)
                # BusyBox forwards local syslog datagrams without adding a host.
                messages = [
                    b"<30>Nov  3 08:11:48 DD-WRT11 dnsmasq[6116]: router-test-with-host\n",
                    b"<30>Nov  3 08:11:48 dnsmasq[6116]: router-test-busybox-no-host\n",
                    b"<4>Nov  3 08:11:48 kernel: router-test-kernel\n",
                ]
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
                    for message in messages:
                        sender.sendto(message, ("127.0.0.1", udp_port))
                with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sender:
                    sender.bind(("127.0.0.2", 0))
                    sender.sendto(
                        b"<30>Nov  3 08:11:48 other app: router-test-rejected\n",
                        ("127.0.0.1", udp_port),
                    )
                markers = (
                    "router-test-with-host",
                    "router-test-busybox-no-host",
                    "router-test-kernel",
                )
                deadline = time.monotonic() + 5
                while time.monotonic() < deadline:
                    if all(marker in output.read_text() for marker in markers):
                        break
                    time.sleep(0.1)
                time.sleep(0.2)
                text = output.read_text()
                assert "router-test-rejected" not in text, text
                for marker in markers:
                    matching = [line for line in text.splitlines() if marker in line]
                    assert len(matching) == 1, text
                    assert 'host=\\"archer-c9\\"' in matching[0], text
                    assert 'source=\\"syslog\\"' in matching[0], text
                assert 'program=\\"kernel\\"' in text, text
                assert 'level=\\"warning\\"' in text, text
                print(
                    "Router syslog: valid config, three packet formats, labels and sender rejection passed"
                )
            finally:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait()


if __name__ == "__main__":
    main()
