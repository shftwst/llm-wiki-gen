# Writing style: avoid AI-writing tells

This guide governs how everything in this repo is written: every wiki page, and every doc
and README too. The goal: text reads like concrete reference notes from someone who knows
the material, not like generated filler. LLM prose has recognisable tells (catalogued in
Wikipedia's "Signs of AI writing"); avoid all of them. Read this before you write or edit
any page or doc.

## The one principle

State facts plainly and cite them. If you cannot say something concrete and sourced, leave
it out. Almost every tell below is what writing does *instead* of stating a plain, sourced
fact.

## 1. Banned vocabulary

Do not use these (the strongest AI signatures). Use plain words.

- **Significance-inflation:** `testament to`, `stands/serves as`, `plays a vital / crucial
  / pivotal / key role`, `underscores`, `highlights`, `reflects a broader`, `marks a
  turning point`, `evolving landscape`, `indelible mark`, `deeply rooted`, `enduring
  legacy`.
- **Promotional / brochure:** `boasts`, `vibrant`, `rich history/culture`, `nestled`, `in
  the heart of`, `breathtaking`, `renowned`, `showcase`, `commitment to`, `dedication to`,
  `groundbreaking`, `diverse array`, `natural beauty`.
- **Filler adjectives:** `crucial`, `robust`, `comprehensive`, `multifaceted`, `seamless`,
  `intricate`, `meticulous`, `nuanced`, `holistic`, `myriad`, `bespoke`.
- **Connective filler:** sentence-initial `Additionally,` / `Moreover,` / `Furthermore,`;
  `delve into`, `align with`, `foster`, `garner`, `leverage`, `tapestry`, `interplay`.
- **Hollow verbs that replace "is/are":** `serves as`, `represents`, `stands as`,
  `features`, `embodies`, `exemplifies`. Prefer `is` / `are`.

Plain is better. Write "Northwind prepares the T2 return," not "Northwind plays a crucial role in
the company's tax compliance, serving as a testament to its commitment to accuracy."

## 2. No editorialising or significance-padding

- Do not tell the reader why something matters. State what it is; let it matter on its own.
- Cut superficial "-ing" commentary tacked onto a sentence: `…, highlighting its
  importance`, `…, reflecting a broader trend`, `…, ensuring consistency`, `…, fostering a
  sense of`. Delete the clause.
- No "Despite its X, it faces several challenges" closers. No `Challenges and Legacy`,
  `Future Outlook`, or `Impact and Significance` sections.

## 3. Attribution: name it or drop it

- No vague authorities: `experts argue`, `observers note`, `industry reports`, `some
  critics`, `studies show`, `it is widely regarded`. Name the actual source, or do not make
  the claim. (Same rule as: never assert what you did not read in a document.)

## 4. Sentence shape

- Use plain copulas (`is`, `are`, `was`). Do not reach for `serves as` / `represents`.
- No rule-of-three padding (`adjective, adjective, and adjective`) unless all three are
  load-bearing facts.
- No negative parallelism: `not only X but also Y`, `it is not X, it is Y`, `not a…, not
  a…, just a…`. Say the positive thing directly.
- No elegant variation. Reuse the same plain noun for the same thing. Do not thesaurus-swap
  ("the company" then "the firm" then "the enterprise") to avoid repetition.

## 5. Structure

- Headings in **sentence case** ("Corporate identity", not "Corporate Identity And
  Structure"). Keep them short and literal.
- Bold sparingly: a genuine key term on first definition only. Never bold every instance of
  a word, never whole sentences.
- Lists for real lists (enumerable items). Do not turn prose into bullets, and do not write
  `- **Header**: sentence` pseudo-lists where a paragraph belongs.
- No summary or recap paragraph that restates the section. No "In conclusion" / "In
  summary".

## 6. Punctuation and characters

- Straight quotes and apostrophes (`"` and `'`), never curly ones.
- Em-dashes: rare. Prefer a comma, a period, or parentheses. Not more than one per
  paragraph.
- No emoji anywhere, including as bullets or status marks.
- Never leave stray AI tokens: `turn0search0`, `oaicite`, `contentReference`, `:::`, `+1`,
  `grok_card`, placeholder text, or unclosed brackets.

## 7. No model self-references

- Never mention being an AI, training data, or a knowledge cutoff ("as of my last update",
  "I cannot verify that"). If something is unknown, mark it with a `> [!review]` callout or
  omit it.
- Do not address the reader as a collaborator ("let's…", "I appreciate", "happy to help").

## 8. Citations

- Cite only documents you actually read (`## Sources`, `../raw/...` links). Never invent a
  source, page number, DOI, or URL. Strip tracking parameters (`utm_*`) from any link.
- In `## Sources`, separate fields with a middle dot `·`, not an em-dash:
  `- [path](../raw/...) · note · read in full`.

## 9. The voice to aim for

Write like a sharp internal analyst briefing a busy owner: concrete nouns, real numbers and
dates, short declarative sentences, the fact first. Specific beats impressive. If a
sentence still reads fine after you delete every adjective, it was doing its job.

## 10. Keep wiki-mechanics and provenance out of the prose

The page body is about its **subject**, nothing else. The reader does not care how the page
was built, where the raw file sits, or what it was synthesized from. None of that belongs in
prose:

- **Ingestion mechanics.** No "read in full this pass", "not read this pass", "map pass",
  "deferred to a later pass", "the first ingest", "this ingest", "coverage row", "the
  frontier". Read-state lives in `coverage.tsv`; what was read vs deferred goes in `log.md`.
- **Provenance.** No "Source: `finance/tax/` in [[shared-drive]]", no "drawn from the
  `Minute Book/` folder", no statement of which raw folder or file the content came from.
  Provenance belongs in the `## Sources` section and the frontmatter, not the body.
- **Derivation bookkeeping.** No "derived from the signed agreements", no "see X for the
  rates derived from them". State the fact; link the related page in a natural sentence. The
  `derived_from` frontmatter records the dependency.

Cross-links are good: `[[client-rates]]` inside a sentence that reads naturally is exactly
right. Just never frame a link as ingestion bookkeeping.

Data-confidence caveats are different and stay: if a number is an estimate or unverified, say
so as a fact about the data ("the 2024 distribution total is an estimate; the T5 is not yet on
file"), not as a note about the read pass. Use a `> [!review]` callout for an internal QA flag,
phrased as a fact about the data, not about how it was processed.

**Source pages are the one exception:** a `type: source` page's subject *is* the source, so it
describes what the source is and what it contains. Provenance there is the content.

## Self-check before saving a page

- Any word from §1? Replace it.
- Any sentence that says *why it matters* rather than *what it is*? Cut it.
- Any claim without a named or cited source? Remove it or source it.
- Any ingestion mechanics, raw-folder provenance, or "derived from" in the prose? Cut it (§10).
- Headings sentence-case? Bold rare? Quotes straight? No emoji, no stray tokens?
- Could a knowledgeable human have written this without an LLM? If not, rewrite it.
