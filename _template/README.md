# {{KB_TITLE}}

An LLM-maintained knowledge base, built on the **LLM Wiki** pattern. The LLM reads
sources and writes the wiki; you curate sources and ask questions.

## Layout

- `raw/`, your sources (files, directories, or symlinks to living documents). You add
  these.
- `wiki/`, the wiki the LLM writes and maintains. **Open this folder as your Obsidian
  vault.**
- `CLAUDE.md`, the schema the LLM follows. Co-evolve it as you learn what works.
- `log.md`, chronological record of every ingest / re-ingest / query / lint.

## Using it

1. Open this folder in Claude Code (the `CLAUDE.md` loads automatically).
2. Open `wiki/` as an Obsidian vault to browse the result.
3. Add a source, drop a file or folder into `raw/`, or symlink a living document:
   ```sh
   ln -s /path/to/shared-drive/Ops raw/ops-shared-drive
   ```
4. Ask the LLM to ingest it (e.g. "ingest `raw/ops-shared-drive`"). Ask questions.
   Periodically ask it to **lint** the wiki, and to **re-ingest** sources that have
   changed.

## Notes

- Symlinked living sources stay at their origin, git stores the link, never the
  target's contents.
- Obsidian only renders markdown; non-markdown sources are read by the LLM and surface
  through wiki pages.
