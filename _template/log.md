# {{KB_TITLE}} — Log

Append-only chronological record. One entry per operation. Newest at the bottom.

Format: `## [YYYY-MM-DD] ingest|reingest|query|lint | <title>`
Grep the timeline: `grep "^## \[" log.md | tail -5`

## [{{DATE}}] init | knowledge base created

- Scaffolded from llm-wiki-gen. Empty wiki ready for first ingest.
