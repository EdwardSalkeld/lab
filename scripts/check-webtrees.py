#!/usr/bin/env python3
"""Exercise the pinned native webtrees stack without touching host services."""

import html.parser
import http.cookiejar
import json
import os
from pathlib import Path
import pwd
import shutil
import socket
import subprocess
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

repo = Path(__file__).resolve().parents[1]
attrs = "nixosConfigurations.partridge.config."
targets = [
    "services.nginx.virtualHosts.webtrees-lan.root",
    "services.phpfpm.pools.webtrees.phpPackage",
    "services.postgresql.package",
    "services.nginx.package",
]
build_roots = tempfile.TemporaryDirectory(prefix="webtrees-build-")
subprocess.run(["nix", "build", "--out-link", f"{build_roots.name}/result", *[f"{repo}#{attrs}{t}" for t in targets]], check=True)


def evaluate(target, apply=None):
    command = ["nix", "eval", "--json", f"{repo}#{attrs}{target}"]
    if apply:
        command += ["--apply", apply]
    return json.loads(subprocess.check_output(command))


app, php, pg, nginx = [Path(evaluate(t)) for t in targets]
vhost = evaluate("services.nginx.virtualHosts.webtrees-lan", "v: { inherit (v) extraConfig; locations = builtins.mapAttrs (_: l: { inherit (l) extraConfig tryFiles fastcgiParams; }) v.locations; }")
pool = evaluate("services.phpfpm.pools.webtrees", "p: { inherit (p) settings socket phpOptions; }")
unix_user = pwd.getpwuid(os.getuid()).pw_name


class Fields(html.parser.HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.values = {}
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "input" and attrs.get("name"):
            self.values[attrs["name"]] = attrs.get("value", "")


with tempfile.TemporaryDirectory(prefix="webtrees-smoke-") as temp:
    work = Path(temp)
    processes = []
    log = (work / "process.log").open("w+")
    try:
        # Relocate only the writable data symlink; keep pinned application code.
        shutil.copytree(app, work / "app", symlinks=True)
        for directory, _, _ in os.walk(work / "app"):
            Path(directory).chmod(0o755)
        (work / "app/data").unlink()
        (work / "data").mkdir()
        (work / "app/data").symlink_to(work / "data")
        (work / "sessions").mkdir()
        (work / "pgsocket").mkdir()
        subprocess.run([pg / "bin/initdb", "-D", work / "pg", "--auth=peer", "--no-locale", "--encoding=UTF8"], check=True, stdout=log)
        # Test processes run as the CI user, mapped to the dedicated DB role.
        (work / "pg/pg_ident.conf").write_text(f"smoke {unix_user} webtrees\n")
        (work / "pg/pg_hba.conf").write_text("local webtrees webtrees peer map=smoke\nlocal all all peer\n")
        subprocess.run([pg / "bin/pg_ctl", "-D", work / "pg", "-l", work / "pg.log", "-o", f"-k {work}/pgsocket -c listen_addresses=''", "-w", "start"], check=True, stdout=log)

        def sql(statement, database="webtrees"):
            return subprocess.check_output([pg / "bin/psql", "-h", work / "pgsocket", "-d", database, "-At", "-v", "ON_ERROR_STOP=1", "-c", statement], text=True).strip()

        sql("CREATE ROLE webtrees LOGIN", "postgres")
        sql("CREATE DATABASE webtrees OWNER webtrees", "postgres")
        settings = pool["settings"].copy()
        settings.update({"listen": str(work / "fpm.sock"), "user": unix_user, "group": pwd.getpwuid(os.getuid()).pw_gid})
        for key in ["listen.owner", "listen.group"]:
            settings.pop(key, None)
        (work / "fpm.conf").write_text(f"[global]\nerror_log = {work}/fpm.log\npid = {work}/fpm.pid\n[webtrees]\n" + "".join(f"{k} = {v}\n" for k, v in settings.items()))
        options = pool["phpOptions"].replace("/var/lib/webtrees/sessions", str(work / "sessions"))
        (work / "php.ini").write_text((php / "etc/php.ini").read_text() + "\n" + options)
        fpm_command = [php / "bin/php-fpm", "-F", "-y", work / "fpm.conf", "-c", work / "php.ini"]
        fpm = subprocess.Popen(fpm_command, stdout=log, stderr=log)
        processes.append(fpm)
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        locations = []
        for name, opts in vhost["locations"].items():
            content = opts["extraConfig"].replace(str(app), str(work / "app")).replace(pool["socket"], str(work / "fpm.sock"))
            if opts["tryFiles"]:
                content += f"\ntry_files {opts['tryFiles']};"
            for key, value in opts["fastcgiParams"].items():
                content += f"\nfastcgi_param {key} {value.replace(str(app), str(work / 'app'))};"
            locations.append(f"location {name} {{\n{content}\n}}")
        # Keep the actual location/deny rules; substitute loopback for test LAN.
        extra = vhost["extraConfig"].replace("10.4.1.0/24", "127.0.0.1")
        (work / "nginx.conf").write_text(f"pid {work}/nginx.pid;\nerror_log {work}/nginx.log;\nevents {{}}\nhttp {{\ninclude {nginx}/conf/mime.types;\naccess_log off;\nclient_body_temp_path {work}/body;\nfastcgi_temp_path {work}/fastcgi;\nserver {{ listen 127.0.0.1:{port}; root {work}/app;\n{extra}\n" + "\n".join(locations) + "\n}}\n")
        processes.append(subprocess.Popen([nginx / "bin/nginx", "-c", work / "nginx.conf", "-p", str(work), "-g", "daemon off;"], stdout=log, stderr=log))
        base = f"http://127.0.0.1:{port}/"
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

        def request(path="", data=None):
            body = None if data is None else urllib.parse.urlencode(data).encode()
            with opener.open(base + path, body, timeout=30) as response:
                return response.read().decode()

        for attempt in range(60):
            try:
                page = request()
                break
            except (OSError, urllib.error.HTTPError):
                time.sleep(0.5)
        else:
            raise RuntimeError("Native web stack failed to start")
        assert 'name="lang"' in page, page
        data = dict(lang="en-US", dbtype="pgsql", dbhost=str(work / "pgsocket"), dbport="5432", dbuser="webtrees", dbpass="", dbname="webtrees", tblpfx="wt_")
        page = request(data={**data, "step": 5})
        assert 'name="wtuser"' in page, page
        request(data={**data, "step": 6, "baseurl": base.rstrip("/"), "wtname": "Smoke Test", "wtuser": "smoke", "wtpass": "smoke-test-password", "wtemail": "smoke@example.invalid"})
        assert (work / "data/config.ini.php").exists()
        assert sql("SELECT count(*) FROM wt_user WHERE user_name = 'smoke'") == "1"
        page = request("index.php?route=%2Fadmin%2Ftrees%2Fcreate")
        fields = Fields(page).values
        page = request("index.php?route=%2Fadmin%2Ftrees%2Fcreate", {**fields, "name": "smoke", "title": "Smoke family"})
        assert sql("SELECT count(*) FROM wt_gedcom WHERE gedcom_name = 'smoke'") == "1", page
        for path in ["data/config.ini.php", "data/example.ged", "vendor/autoload.php", "app/Webtrees.php", ".htaccess"]:
            try:
                request(path)
            except urllib.error.HTTPError as error:
                assert error.code == 403, (path, error.code)
            else:
                raise AssertionError(f"Private path was served: {path}")
        fpm.terminate()
        fpm.wait(timeout=10)
        processes.append(subprocess.Popen(fpm_command, stdout=log, stderr=log))
        time.sleep(1)
        assert "Smoke family" in request()
        assert sql("SELECT count(*) FROM wt_user WHERE user_name = 'smoke'") == "1"
        print("PASS: native Nginx/PHP-FPM, socket peer authentication, admin/tree creation, private path restrictions and restart persistence")
    except Exception:
        for name in ["process.log", "pg.log", "fpm.log", "nginx.log"]:
            path = work / name
            if path.exists():
                print(f"{name}:\n{path.read_text()[-10000:]}")
        raise
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                process.wait(timeout=10)
        if (work / "pg/postmaster.pid").exists():
            subprocess.run([pg / "bin/pg_ctl", "-D", work / "pg", "-m", "immediate", "stop"], stdout=log)
        log.close()
        build_roots.cleanup()
