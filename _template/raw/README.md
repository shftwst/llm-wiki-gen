# raw/ — sources

Drop your source material here. The LLM reads from this directory but never treats it as
something it owns. Three shapes are supported:

- **Files** — `cp report.pdf raw/`
- **Directories** — `cp -R ProjectX raw/` (a folder is one source; the LLM walks it)
- **Symlinks to living documents** — point at a source of truth that stays organized
  elsewhere:
  ```sh
  ln -s /mnt/gdrive/Ops raw/ops-shared-drive
  ```
  Git stores the symlink, not the linked contents. When the target changes, ask the LLM
  to **re-ingest** it.

This folder is not browsable in Obsidian (the Obsidian vault is `wiki/`). Knowledge from
these sources reaches you through the wiki pages the LLM writes.
