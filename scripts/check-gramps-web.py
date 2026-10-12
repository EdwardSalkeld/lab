"""Exercise the evaluated Partridge container config on an isolated CI runner."""

import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

repo = Path(__file__).resolve().parents[1]
containers = json.loads(subprocess.check_output([
    "nix", "eval", "--json",
    ".#nixosConfigurations.partridge.config.virtualisation.oci-containers.containers",
], cwd=repo))
app_config = containers["gramps-web"]
worker_config = containers["gramps-web-worker"]
names = []


def docker(*args, **kwargs):
    return subprocess.run(["docker", *args], check=True, text=True, **kwargs)


def request(path, body=None, token=None, method=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = Request("http://127.0.0.1:5051" + path,
                  data=None if body is None else json.dumps(body).encode(),
                  headers=headers, method=method)
    with urlopen(req, timeout=20) as response:
        payload = response.read()
        return response.status, json.loads(payload) if payload else None


def wait_for_api():
    for _ in range(120):
        try:
            with urlopen("http://127.0.0.1:5051/", timeout=5) as response:
                if response.status == 200:
                    return
        except (URLError, TimeoutError):
            time.sleep(2)
    raise RuntimeError("Gramps Web did not become ready")


with tempfile.TemporaryDirectory(prefix="gramps-smoke-") as temp:
    root = Path(temp)
    # The test credentials are disposable; production uses SOPS exclusively.
    password = secrets.token_hex(32)
    key = secrets.token_hex(32)
    env = root / "app.env"
    env.write_text("\n".join([
        "GRAMPSWEB_SECRET_KEY=" + key,
        "GRAMPSWEB_POSTGRES_PASSWORD=" + password,
        f"GRAMPSWEB_USER_DB_URI=postgresql://gramps:{password}@127.0.0.1:5432/grampswebuser",
        f"GRAMPSWEB_SEARCH_INDEX_DB_URI=postgresql://gramps:{password}@127.0.0.1:5432/gramps",
    ]) + "\n")
    env.chmod(0o600)
    pg_env = root / "pg.env"
    pg_env.write_text("POSTGRES_PASSWORD=" + password + "\n")
    pg_env.chmod(0o600)
    volumes = []
    for volume in app_config["volumes"]:
        source, target = volume.split(":", 1)
        local = root / Path(source).name
        local.mkdir()
        volumes += ["--volume", f"{local}:{target}"]
    args = ["--network=host", "--env-file", str(env), *volumes]
    for name, value in app_config["environment"].items():
        args += ["--env", f"{name}={value}"]

    try:
        names.append("gramps-smoke-postgres")
        docker("run", "-d", "--name", names[-1], "--network=host",
               "--env-file", str(pg_env), "postgres:17")
        for _ in range(60):
            result = subprocess.run(["docker", "exec", names[-1], "pg_isready", "-U", "postgres"],
                                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            if result.returncode == 0:
                break
            time.sleep(1)
        sql = (f"CREATE ROLE gramps LOGIN PASSWORD '{password}';\n"
               "CREATE DATABASE gramps OWNER gramps;\n"
               "CREATE DATABASE grampswebuser OWNER gramps;\n")
        docker("exec", "-i", names[-1], "psql", "-U", "postgres", "-v", "ON_ERROR_STOP=1",
               input=sql, stdout=subprocess.DEVNULL)
        names.append("gramps-smoke-redis")
        docker("run", "-d", "--name", names[-1], "--network=host", "redis:7-alpine",
               "redis-server", "--bind", "127.0.0.1", "--port", "6381")
        bootstrap = repo / "nixos/hosts/partridge/gramps-web-bootstrap.py"

        def initialize():
            docker("run", "--rm", *args, "--volume", f"{bootstrap}:/bootstrap.py:ro",
                   "--entrypoint", "python3", app_config["image"], "/bootstrap.py")

        initialize()
        initialize()  # A second startup must find the same existing tree.
        marker = root / "db" / app_config["environment"]["GRAMPSWEB_TREE_ID"] / "database.txt"
        assert marker.read_text().strip() == "sharedpostgresql"
        names.append("gramps-smoke-app")
        docker("run", "-d", "--name", names[-1], *args, app_config["image"], *app_config["cmd"])
        wait_for_api()
        status, setup = request("/api/token/create_owner/", {}, method="POST")
        assert status == 201
        owner_password = secrets.token_hex(24)
        status, _ = request("/api/users/smoke/create_owner/", {
            "password": owner_password, "email": "smoke@example.invalid", "full_name": "Smoke test",
        }, setup["access_token"])
        assert status == 201
        _, login = request("/api/token/", {"username": "smoke", "password": owner_password})
        token = login["access_token"]
        status, person = request("/api/people/", {}, token)
        assert status == 201
        _, people = request("/api/people/", token=token)
        assert len(people) == 1
        # The genealogy must exist in PostgreSQL, not a SQLite fallback.
        result = docker("exec", names[0], "psql", "-U", "postgres", "-d", "gramps", "-Atc",
                        "SELECT count(*) FROM person;", capture_output=True)
        assert result.stdout.strip() == "1"
        names.append("gramps-smoke-worker")
        docker("run", "-d", "--name", names[-1], *args, worker_config["image"], *worker_config["cmd"])
        # Export is a real Celery job, verifying the shared DB/Redis/volumes.
        status, job = request("/api/exporters/gramps/file", token=token, method="POST")
        assert status == 202, job
        task_id = job["task"]["id"]
        for _ in range(60):
            _, task = request(f"/api/tasks/{task_id}", token=token)
            if task["state"] == "SUCCESS":
                break
            assert task["state"] != "FAILURE", task
            time.sleep(2)
        else:
            raise RuntimeError("Celery export did not finish")
        docker("restart", "gramps-smoke-app")
        wait_for_api()
        _, people = request("/api/people/", token=token)
        assert len(people) == 1
        try:
            request("/api/token/create_owner/", {}, method="POST")
        except HTTPError as exc:
            assert exc.code == 405
        else:
            raise AssertionError("Owner setup reopened after restart")
        print("PASS: PostgreSQL tree, repeat bootstrap, owner setup, edits, Celery export and restart persistence")
    except BaseException:
        for name in names:
            subprocess.run(["docker", "logs", "--tail", "80", name])
        raise
    finally:
        for name in reversed(names):
            subprocess.run(["docker", "rm", "-f", name], stdout=subprocess.DEVNULL)
        # Docker wrote root-owned files into this disposable runner directory.
        subprocess.run(["sudo", "chown", "-R", f"{os.getuid()}:{os.getgid()}", str(root)], check=True)
