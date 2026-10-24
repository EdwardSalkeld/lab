# Sparrow: retired Chatting test container

Sparrow was shut down and destroyed on 2026-10-12 at Edward's request after
testing finished. CT 76300 and its 24 GiB root disk on `sol` were removed,
including all three test services and their data. Production Chatting on
Magpie is separate.

The Terraform resource, outputs, import and installer have been removed.
Plan and apply include `deploy/sparrow-import.tf.template` to forget remaining
state without requesting another deletion. Later deployments cannot recreate
the test container. The template retains its historical filename for compatibility
with older deployment dispatchers, but contains a retirement directive.
