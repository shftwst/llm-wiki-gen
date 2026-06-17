#!/usr/bin/env python3
# guard-raw — Claude Code PreToolUse hook. Blocks any tool action that would EDIT, DELETE, MOVE,
# CREATE, or change PERMISSIONS under raw/ (including writes that resolve THROUGH a raw/ symlink
# into the living source). Reads are allowed, including a read that hydrates a cloud placeholder.
#
# Mechanism: a PreToolUse hook that exits 2 blocks the tool call and returns the reason to the
# model. This holds even under --permission-mode acceptEdits / bypassPermissions, so it is a real
# lock, not a policy. It backs (does not replace) the "raw/ is read-only" hard rule in AGENTS.md.
#
# Reads the hook payload (tool_name, tool_input, cwd) as JSON on stdin. KB root is taken from
# CLAUDE_PROJECT_DIR when set, else the payload cwd.
import sys, os, re, json


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        print("guard-raw: could not parse hook input; blocking to stay safe.", file=sys.stderr)
        sys.exit(2)

    tool = data.get("tool_name", "")
    ti = data.get("tool_input", {}) or {}
    cwd = data.get("cwd") or os.getcwd()
    kb = os.environ.get("CLAUDE_PROJECT_DIR") or cwd
    raw = os.path.normpath(os.path.join(kb, "raw"))
    raw_real = os.path.realpath(raw)

    # Protected real roots: raw/ itself plus every living-source symlink target under it.
    roots = {raw_real}
    try:
        for name in os.listdir(raw):
            p = os.path.join(raw, name)
            if os.path.islink(p):
                roots.add(os.path.realpath(p))
    except OSError:
        pass

    def resolve(path):
        ap = path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))
        anc, tail = ap, ""
        while anc and not os.path.lexists(anc):
            anc, base = os.path.split(anc)
            tail = os.path.join(base, tail) if tail else base
        real = os.path.realpath(anc) if anc else ap
        real = os.path.normpath(os.path.join(real, tail)) if tail else real
        return real, ap

    def under_protected(path):
        real, lexical = resolve(path)
        if lexical == raw or lexical.startswith(raw + os.sep):   # lexical raw/ (pre-resolution)
            return True
        for r in roots:                                          # resolved, incl. symlink targets
            if real == r or real.startswith(r + os.sep):
                return True
        return False

    def deny(what):
        print("guard-raw: BLOCKED " + what + ". raw/ and its linked sources are read-only to the "
              "agent: edit / delete / move / permission changes are not allowed (reads are fine). "
              "If a source must change, do it at its origin, then re-ingest.", file=sys.stderr)
        sys.exit(2)

    # File-mutating tools: any target path under raw/ is blocked.
    if tool in ("Write", "Edit", "MultiEdit", "NotebookEdit", "Update"):
        for key in ("file_path", "notebook_path", "path"):
            v = ti.get(key)
            if isinstance(v, str) and v and under_protected(v):
                deny(tool + " -> " + v)

    # Bash: block destructive/writing ops that involve a raw/ path, and redirects into raw/.
    if tool == "Bash":
        cmd = ti.get("command", "") or ""
        mentions_raw = ("raw/" in cmd) or (raw in cmd) or any(r in cmd for r in roots)
        verb = re.compile(r'\b(rm|rmdir|unlink|mv|cp|chmod|chown|chflags|chgrp|truncate|shred|dd|'
                          r'ln|install|rsync|touch|mkdir)\b')
        inplace = re.compile(r'\b(sed|perl)\b[^|;&]*\s-\S*i')   # sed -i / perl -i (in-place edit)
        redir = re.compile(r'(>>?|(?:^|\s)tee\b(?:\s+-a)?)\s*["\']?(?:\./)?(?:raw/|'
                           + re.escape(raw) + r'|' + re.escape(raw_real) + r')')
        if mentions_raw and (verb.search(cmd) or inplace.search(cmd)):
            deny("a Bash command that may modify raw/ (read raw/ with the Read tool instead)")
        if redir.search(cmd):
            deny("a Bash redirect into raw/")

    sys.exit(0)


if __name__ == "__main__":
    main()
