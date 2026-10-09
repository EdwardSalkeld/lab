#!/usr/bin/env python3
"""Exercise the pinned native webtrees stack without touching host services."""

import html.parser
import errno
import http.client
import http.cookiejar
import json
import os
from pathlib import Path
import pwd
import re
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
config_path = Path(re.search(r"CONFIG_FILE = '([^']+)'", (app / "app/Webtrees.php").read_text())[1])
assert str(config_path).startswith("/nix/store/")
for operation in [lambda: config_path.open("a"), lambda: config_path.unlink()]:
    try:
        operation()
    except OSError as error:
        assert error.errno in (errno.EACCES, errno.EPERM, errno.EROFS), error
    else:
        raise AssertionError("Application user can edit or replace deployed configuration")
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

        units = evaluate("systemd.services", "s: builtins.mapAttrs (_: v: { inherit (v) requires requisite bindsTo after script; }) s")
        assert "webtrees" not in evaluate("services.postgresql.ensureDatabases")
        assert "webtrees" not in units["postgresql-setup"]["script"]
        assert "webtrees-db-setup.service" in units["phpfpm-webtrees"]["requires"]

        # Follow actual hard dependencies, including transitive ones. An
        # application-specific provisioning failure must not gate Forgejo.
        def hard_dependencies(name, seen=None):
            seen = set() if seen is None else seen
            if name in seen or name not in units:
                return seen
            seen.add(name)
            for key in ("requires", "requisite", "bindsTo"):
                for dependency in units[name][key]:
                    hard_dependencies(dependency.removesuffix(".service"), seen)
            return seen

        assert "webtrees-db-setup" not in hard_dependencies("forgejo")
        assert "webtrees-bootstrap" not in hard_dependencies("forgejo")
        assert "webtrees-bootstrap.service" in units["phpfpm-webtrees"]["requires"]
        sql("CREATE DATABASE existing_service", "postgres")
        sql("CREATE TABLE marker AS SELECT 42 AS value", "existing_service")
        setup = units["webtrees-db-setup"]["script"]
        setup_env = {**os.environ, "PATH": f"{pg}/bin:" + os.environ["PATH"], "PGHOST": str(work / "pgsocket")}
        # Make new database creation fail, without disrupting existing DBs.
        sql("ALTER DATABASE template1 RENAME TO unavailable_template", "postgres")
        failed = subprocess.run(["bash", "-e", "-c", setup], env=setup_env, stdout=log, stderr=log)
        assert failed.returncode != 0
        assert sql("SELECT value FROM marker", "existing_service") == "42"
        sql("ALTER DATABASE unavailable_template RENAME TO template1", "postgres")
        # Retry the exact evaluated provisioning script, then repeat it to
        # verify existing live databases/roles are preserved on later deploys.
        for _ in range(2):
            subprocess.run(["bash", "-e", "-c", setup], env=setup_env, check=True, stdout=log, stderr=log)
        assert sql("SELECT value FROM marker", "existing_service") == "42"
        print("Database provisioning failure isolation and idempotent retry passed", flush=True)
        settings = pool["settings"].copy()
        settings.update({"listen": str(work / "fpm.sock"), "user": unix_user, "group": pwd.getpwuid(os.getuid()).pw_gid})
        for key in ["listen.owner", "listen.group"]:
            settings.pop(key, None)
        (work / "fpm.conf").write_text(f"[global]\nerror_log = {work}/fpm.log\npid = {work}/fpm.pid\n[webtrees]\n" + "".join(f"{k} = {v}\n" for k, v in settings.items()))
        options = pool["phpOptions"].replace("/var/lib/webtrees/sessions", str(work / "sessions"))
        (work / "php.ini").write_text((php / "etc/php.ini").read_text() + "\n" + options)
        fpm_command = [php / "bin/php-fpm", "-F", "-y", work / "fpm.conf", "-c", work / "php.ini"]
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        base = f"http://127.0.0.1:{port}/"
        # Relocate the immutable config only in the test copy, to address the
        # disposable DB. Exercise the deployed config format and CLI script.
        config_file = work / "config.ini.php"
        original_config = config_path.read_text().replace("/run/postgresql", str(work / "pgsocket")).replace(
            "http://partridge.tailb35748.ts.net:5052", base.rstrip("/")
        )
        config_file.write_text(original_config)
        app_class = work / "app/app/Webtrees.php"
        app_class.chmod(0o644)
        app_class.write_text(app_class.read_text().replace(str(config_path), str(config_file)))
        # Writable legacy config must be ignored, even when it conflicts.
        (work / "data/config.ini.php").write_text('dbhost="/nonexistent"\nbase_url="http://invalid.example"\n')
        (work / "credentials").mkdir()
        credential = work / "credentials/bootstrap-password"
        credential.write_text("short")
        bootstrap = [php / "bin/php", work / "app/app/bootstrap.php"]
        bootstrap_env = {**os.environ, "CREDENTIALS_DIRECTORY": str(work / "credentials")}
        failed = subprocess.run(bootstrap, env=bootstrap_env, cwd=work / "app", stdout=log, stderr=log)
        assert failed.returncode != 0
        assert sql("SELECT count(*) FROM wt_user WHERE user_id > 0") == "0"
        assert sql("SELECT value FROM marker", "existing_service") == "42"
        credential.write_text("smoke-test-password")
        sql("INSERT INTO wt_user (user_name, real_name, email, password) VALUES ('edward', 'Existing user', 'other@example.invalid', 'unusable')")
        failed = subprocess.run(bootstrap, env=bootstrap_env, cwd=work / "app", stdout=log, stderr=log)
        assert failed.returncode != 0
        assert sql("SELECT count(*) FROM wt_user_setting WHERE setting_name='canadmin' AND setting_value='1'") == "0"
        sql("DELETE FROM wt_user WHERE user_name='edward'")
        subprocess.run(bootstrap, env=bootstrap_env, cwd=work / "app", check=True, stdout=log, stderr=log)
        assert sql("SELECT count(*) FROM wt_user WHERE user_name = 'edward'") == "1"
        # Represent a pre-existing administrator with a different identity.
        # Repeated deploys must neither add another admin nor reset passwords.
        sql("UPDATE wt_user SET user_name='smoke', email='smoke@example.invalid' WHERE user_name='edward'")
        saved_password = sql("SELECT password FROM wt_user WHERE user_name='smoke'")
        credential.write_text("a-different-bootstrap-password")
        subprocess.run(bootstrap, env=bootstrap_env, cwd=work / "app", check=True, stdout=log, stderr=log)
        assert sql("SELECT count(*) FROM wt_user WHERE user_id > 0") == "1"
        assert sql("SELECT password FROM wt_user WHERE user_name='smoke'") == saved_password
        fpm = subprocess.Popen(fpm_command, stdout=log, stderr=log)
        processes.append(fpm)
        locations = []
        for name, opts in vhost["locations"].items():
            content = opts["extraConfig"].replace(str(app), str(work / "app")).replace(pool["socket"], str(work / "fpm.sock"))
            if opts["tryFiles"]:
                content += f"\ntry_files {opts['tryFiles']};"
            for key, value in opts["fastcgiParams"].items():
                content += f"\nfastcgi_param {key} {value.replace(str(app), str(work / 'app'))};"
            locations.append(f"location {name} {{\n{content}\n}}")
        # Map LAN and tailnet sources to distinct local addresses while keeping
        # the evaluated allow/deny rules and exercising real Nginx decisions.
        extra = (vhost["extraConfig"]
                 .replace("10.4.1.0/24", "127.0.0.1/32")
                 .replace("100.64.0.0/10", "127.0.0.2/32")
                 .replace("fd7a:115c:a1e0::/48", "::1/128"))
        (work / "nginx.conf").write_text(f"pid {work}/nginx.pid;\nerror_log {work}/nginx.log;\nevents {{}}\nhttp {{\ninclude {nginx}/conf/mime.types;\naccess_log off;\nclient_body_temp_path {work}/body;\nfastcgi_temp_path {work}/fastcgi;\nserver {{ listen 127.0.0.1:{port}; listen [::1]:{port}; root {work}/app;\n{extra}\n" + "\n".join(locations) + "\n}}\n")
        processes.append(subprocess.Popen([nginx / "bin/nginx", "-c", work / "nginx.conf", "-p", str(work), "-g", "daemon off;"], stdout=log, stderr=log))
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

        def request(path="", data=None):
            body = None if data is None else urllib.parse.urlencode(data).encode()
            with opener.open(base + path, body, timeout=30) as response:
                return response.read().decode()

        for attempt in range(60):
            try:
                page = request("index.php?route=%2Flogin")
                break
            except (OSError, urllib.error.HTTPError):
                time.sleep(0.5)
        else:
            raise RuntimeError("Native web stack failed to start")
        assert 'name="lang"' not in page, page
        for destination, source, expected in [
            ("127.0.0.1", "127.0.0.2", 200),  # Tailnet IPv4
            ("::1", "::1", 200),  # Tailnet IPv6
            ("127.0.0.1", "127.0.0.3", 403),  # Outside permitted networks
        ]:
            connection = http.client.HTTPConnection(destination, port, timeout=30, source_address=(source, 0))
            try:
                connection.request("GET", "/index.php?route=%2Flogin", headers={"User-Agent": "webtrees-native-smoke", "Host": f"127.0.0.1:{port}"})
                response = connection.getresponse()
                response.read()
                assert response.status == expected, (source, response.status)
                if expected == 200:
                    connection.request("GET", "/data/config.ini.php")
                    response = connection.getresponse()
                    response.read()
                    assert response.status == 403, (source, response.status)
            finally:
                connection.close()
        page = request("index.php?route=%2Flogin")
        fields = Fields(page).values
        request("index.php?route=%2Flogin", {**fields, "username": "smoke", "password": "smoke-test-password"})
        assert sql("SELECT count(*) FROM wt_user WHERE user_name = 'smoke'") == "1"
        page = request("index.php?route=%2Fadmin%2Ftrees%2Fcreate")
        fields = Fields(page).values
        page = request("index.php?route=%2Fadmin%2Ftrees%2Fcreate", {**fields, "name": "smoke", "title": "Smoke family"})
        assert sql("SELECT count(*) FROM wt_gedcom WHERE gedcom_name = 'smoke'") == "1", page
        for path in ["data/config.ini.php", "data/example.ged", "vendor/autoload.php", "app/Webtrees.php", "app/bootstrap.json", ".htaccess"]:
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
        # A later tunnel cutover changes the canonical URL, not the tree or
        # accounts. Exercise HTTPS URL generation over an HTTP origin.
        assert f'base_url="{base.rstrip("/")}"' in original_config
        config_file.write_text(original_config.replace(
            f'base_url="{base.rstrip("/")}"',
            'base_url="https://family.salkeld.net"',
        ))
        connection = http.client.HTTPConnection("127.0.0.1", port, timeout=30)
        try:
            connection.request("GET", "/index.php?route=%2Flogin", headers={"Host": "family.salkeld.net", "User-Agent": "webtrees-native-smoke"})
            response = connection.getresponse()
            page = response.read().decode()
            assert response.status == 302, (response.status, page)
            destination = response.getheader("Location")
            assert destination.startswith("https://family.salkeld.net/"), destination
            parsed = urllib.parse.urlsplit(destination)
            connection.request("GET", parsed.path + "?" + parsed.query, headers={"Host": "family.salkeld.net", "User-Agent": "webtrees-native-smoke"})
            response = connection.getresponse()
            page = response.read().decode()
            assert response.status == 200, (response.status, page)
            assert 'https://family.salkeld.net/public/' in page, page
            assert base.rstrip("/") not in page, page
        finally:
            connection.close()
        assert sql("SELECT count(*) FROM wt_user WHERE user_name = 'smoke'") == "1"
        assert sql("SELECT count(*) FROM wt_gedcom WHERE gedcom_name = 'smoke'") == "1"
        config_file.write_text(original_config)
        assert "Smoke family" in request()
        print("PASS: immutable config, ignored legacy wizard config, bootstrap failure/retry and administrator preservation")
        print("PASS: native Nginx/PHP-FPM, LAN and tailnet IPv4/IPv6 access, denied other sources, socket peer authentication, admin login/tree creation, private path restrictions and restart persistence")
        print("PASS: canonical URL cutover to HTTPS behind an HTTP origin preserves the administrator/tree and generates public HTTPS links")
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
