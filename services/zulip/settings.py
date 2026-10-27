# Appended to Zulip 12.3's pinned production template by the bootstrap script.
EXTERNAL_HOST = "zulip.int.alcachofa.faith"
ZULIP_ADMINISTRATOR = "edsalkeld@alcachofa.faith"
AUTHENTICATION_BACKENDS = ("zproject.backends.EmailAuthBackend",)
REMOTE_POSTGRES_HOST = "partridge.int.alcachofa.faith"
REMOTE_POSTGRES_PORT = "5432"
# Matches the existing home-LAN Postgres clients; neither database nor guest
# HTTP is exposed publicly. TLS to users terminates at Partridge's proxy.
REMOTE_POSTGRES_SSLMODE = "disable"
EMAIL_HOST = "smtp.fastmail.com"
EMAIL_PORT = 587
EMAIL_USE_TLS = True
EMAIL_HOST_USER = "edsalkeld@fastmail.com"
NOREPLY_EMAIL_ADDRESS = "billy@alcachofa.faith"
TOKENIZED_NOREPLY_EMAIL_ADDRESS = "billy+{token}@alcachofa.faith"
# Register explicitly later if mobile push is wanted; no hidden billing step.
ZULIP_SERVICE_PUSH_NOTIFICATIONS = False
ZULIP_SERVICE_SUBMIT_USAGE_STATISTICS = False
