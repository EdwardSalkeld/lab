"""Idempotently create the single SharedPostgreSQL tree before serving it."""

import os
from pathlib import Path

tree_id = os.environ.pop("GRAMPSWEB_TREE_ID")
tree_name = os.environ["GRAMPSWEB_TREE"]
# Use multi-tree configuration only during creation, so Gramps saves the
# PostgreSQL host and port in the tree's metadata. The web app stays single-tree.
os.environ["GRAMPSWEB_TREE"] = "*"
os.environ["GRAMPSWEB_MEDIA_PREFIX_TREE"] = "true"

from gramps_webapi.app import create_app
from gramps_webapi.dbmanager import WebDbManager

app = create_app()
with app.app_context():
    manager = WebDbManager(
        dirname=tree_id,
        name=tree_name,
        username=app.config["POSTGRES_USER"],
        password=app.config["POSTGRES_PASSWORD"],
        create_if_missing=True,
        create_backend="sharedpostgresql",
    )
    if (Path(manager.path) / "database.txt").read_text().strip() != "sharedpostgresql":
        raise RuntimeError("Refusing to start with a non-PostgreSQL tree")
    dbstate = manager.get_db(readonly=False)
    dbstate.db.close()
    dbstate.db.undodb.close()
