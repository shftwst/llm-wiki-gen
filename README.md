# llm-wiki-kit

A scaffolder for **LLM-maintained knowledge bases** — personal or team wikis that an LLM
agent reads into, writes, and keeps current. Based on Andrej Karpathy's **LLM Wiki**
pattern ([`docs/llm-wiki-pattern.md`](docs/llm-wiki-pattern.md)).

Point it anywhere and it stamps out a self-contained knowledge base: a source directory,
an LLM-owned wiki, a schema the agent follows, and an append-only log. Each generated KB
is its own git repo.

## Quickstart

```sh
./scripts/new-kb.sh my-kb "My KB Title"
```

This creates `../my-kb/` (a sibling of the kit by default), substitutes the
name/title/date into the template, and runs `git init` with an initial commit. Then:

```sh
cd ../my-kb
# open in Claude Code; open wiki/ as an Obsidian vault
# drop sources into raw/ and ask the agent to ingest them
```

Pick a different location with a third argument:

```sh
./scripts/new-kb.sh my-kb "My KB Title" /path/to/parent-dir
```

## What's in a generated KB

```
my-kb/
├── CLAUDE.md   # the schema the LLM follows (page conventions + workflows)
├── README.md   # human intro + Obsidian setup
├── raw/        # sources: files, directories, or symlinks to living docs
├── wiki/       # the LLM-owned wiki (Obsidian vault root)
│   ├── index.md
│   └── overview.md
└── log.md      # append-only ingest / re-ingest / query / lint record
```

## The pattern in one paragraph

Instead of RAG re-deriving knowledge on every query, the LLM **incrementally builds and
maintains a persistent wiki** between you and your raw sources. You curate sources and ask
questions; the LLM does the summarizing, cross-referencing, filing, and bookkeeping. The
wiki compounds — cross-references are already there, contradictions already flagged,
synthesis already current. Full write-up:
[`docs/llm-wiki-pattern.md`](docs/llm-wiki-pattern.md).

### Sources can be living

A KB's `raw/` accepts plain files, whole directories, and **symlinks to living documents**
(e.g. a shared-drive folder that stays organized at its source). Git stores the symlink,
not the target's contents, so the wiki references living sources without copying or owning
them — and the agent can **re-ingest** updates when they change.

## Customizing the template

Edit `_template/` to change what new KBs look like — especially
[`_template/CLAUDE.md`](_template/CLAUDE.md), which encodes the page conventions and the
ingest / re-ingest / query / lint workflows. Placeholders `{{KB_NAME}}`, `{{KB_TITLE}}`,
`{{DATE}}`, and `{{YEAR}}` are substituted at generation time.

## License

MIT — see [LICENSE](LICENSE).
