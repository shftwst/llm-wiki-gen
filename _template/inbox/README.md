# inbox/: shared intake (staging)

Drop files or folders here for the knowledge base. A privileged **sweep**
(`scripts/sweep`, also the first step of `scripts/ingest`) **moves** each item
into `raw/`, the protected source store.

This is the **only** directory meant to be shared. Share `inbox/`, e.g. make it a shared
cloud folder, or symlink it to one, and let contributors drop sources in. Because the
sweep *moves* items out, once a source is curated it leaves this shared area, so
contributors can't reach, change, or delete the real `raw/` files.

**Do not share `raw/` or the knowledge-base root.**

Notes:
- Anything dropped here is transient and is **not committed to git** until it's swept into
  `raw/`.
- On a name collision with an existing `raw/` source, the incoming item is renamed with a
  timestamp, nothing in `raw/` is ever overwritten.
