---
name: termdock-ast
displayName: Termdock AST
description: Queries AST index to find symbol locations, file dependencies, callers, and impact analysis. Use when user asks where is X, who calls X, what depends on X, or before refactoring. Skip when user provides exact file path.
version: 7
minAppVersion: 1.25.0
---

# Termdock AST API

## When to Use This Skill

**Use AST API first when:**
- The user asks "where is X", "who calls X", "what does X call", or "what depends on X"
- You need a file path or symbol ownership before editing
- You expect a change to touch multiple files or affect behavior
- You are about to run broad search without a known target

**Skip AST API when:**
- The user provides an exact file path or a snippet to edit
- The task is doc-only or config-only (SKILL.md, README, settings)
- You only need a literal-string search

**Default rule:** Use AST for discovery and impact; skip it for known-file edits.

**If API is unavailable:** Fall back to `rg`/`rg --files` and note the limitation.

---

## Quick Start

### Step 1: Get Workspace ID (Required First)
```bash
root=$(git rev-parse --show-toplevel)
curl -s 'http://localhost:3033/api/workspaces' | jq -r --arg r "$root" '.data.workspaces[] | select(.projectRoot == $r) | .id'
```
The list is ordered by status and name, not by which project you are in, so pick the entry whose `projectRoot` is your project. Save that ID for all subsequent calls.

### Step 2: Choose Your Query Type

| Goal | API | Example |
|------|-----|---------|
| Find symbol by name | `/api/search` | "Where is UserService?" |
| See file imports/exports | `/api/graph/deps` | "What does this file import?" |
| Find callers | `/api/graph/callers` | "Who calls this function?" |
| Find callees | `/api/graph/calls` | "What does this function call?" |
| Impact analysis | `/api/impact` | "What breaks if I change this?" |

---

## API Reference

For persisted-index compatibility and read-only behavior, see [references/api.md](references/api.md).

### 1. Search Symbols
```bash
curl 'http://localhost:3033/api/search?q=<name>&workspace=<wsId>&limit=10'
```

**Response fields:**
- `symbolId`: Use for callers/calls queries
- `file`: Absolute path
- `line`: 0-indexed (add 1 for display)
- `column`: 0-indexed indexed-definition start (add 1 for a 1-based editor). It can be the declaration start rather than the name, and non-ASCII text before it can make the source offset unit differ.
- `type`: 5=Class, 6=Method, 11=Interface, 12=Function

### 2. File Dependencies
```bash
curl 'http://localhost:3033/api/graph/deps?file=src/path/to/file.ts&workspace=<wsId>'
```

Returns: imports (what this file uses) and exports (what it provides)

### 3. Who Calls This?
```bash
curl 'http://localhost:3033/api/graph/callers?to=<symbolId>&workspace=<wsId>'
```

### 4. What Does This Call?
```bash
curl 'http://localhost:3033/api/graph/calls?from=<symbolId>&workspace=<wsId>'
```

### 5. Impact Analysis
```bash
curl 'http://localhost:3033/api/impact?symbolId=<id>&depth=2&workspace=<wsId>'
```

Returns all symbols and files affected by changing this symbol.

---

## Decision Flowchart

```
User asks about code
        |
        v
Is it a "where is X?" question?
    |yes              |no
    v                 v
/api/search      Is it about dependencies?
    |                 |yes         |no
    v                 v            v
Got symbolId?    /api/graph/deps  Is it about call chain?
    |yes                              |yes         |no
    v                                 v            v
Need callers? -----> /api/graph/callers   Use other tools
Need callees? -----> /api/graph/calls
Need impact?  -----> /api/impact
```

---

## Common Patterns

### Pattern A: Find and Understand a Class
```bash
# 1. Find it
curl 'http://localhost:3033/api/search?q=TerminalService&workspace=ws_xxx&limit=1'
# Note: symbolId, file

# 2. See dependencies
curl 'http://localhost:3033/api/graph/deps?file=src/main/services/TerminalService.ts&workspace=ws_xxx'

# 3. Now read the file with context
```

### Pattern B: Trace Usage
```bash
# 1. Find function
curl 'http://localhost:3033/api/search?q=createSession&workspace=ws_xxx&limit=5'
# Pick the right symbolId

# 2. Find all callers
curl 'http://localhost:3033/api/graph/callers?to=<symbolId>&workspace=ws_xxx'
```

### Pattern C: Safe Refactoring
```bash
# Before changing a function, check impact
curl 'http://localhost:3033/api/impact?symbolId=<id>&depth=2&workspace=ws_xxx'
# Review impactedFiles before making changes
```

---

## Error Handling

| Error | Cause | Action |
|-------|-------|--------|
| No workspace found | API not running | Start Termdock app |
| Empty search results | Symbol not indexed | Try partial name or rebuild index |
| Empty callers / calls / impact | The symbolId may be stale after a code change; these endpoints return an empty success, not 404, for an unknown ID | Re-search to get a fresh ID before trusting an empty result |

**Rebuild index after code changes:**
```bash
curl -X POST 'http://localhost:3033/api/index/update' -H 'Content-Type: application/json' -d '{"workspace":"<wsId>"}'
```

---

## Response Format

All APIs return:
```json
{
  "success": true|false,
  "data": {...},
  "error": {"code": "...", "message": "..."}
}
```

Always check `success` before using `data`.

---

### Symbol Detail Positions

`/api/symbols/<symbolId>` returns `line` and `column` as 0-indexed values. The `symbols` method of `POST /api/query` and the `termdock_node` tool expose the same start as `location.range.start.line` and `.character`. Do not assume `range.end` covers the full declaration: when no top-level end position is available it falls back to the start.

### References Analysis

Use `POST /api/query` with `method: "analyze"`, `params.symbolIds`, and `params.include: ["references"]` for semantic references to TS, TSX, JS, and JSX targets. The TypeScript LSP supplies locations; indexed source symbols supply the IDs. Other languages still return an unsupported warning. `data.analysis.data.references` contains relations and `referenceMap` maps each target ID to distinct source IDs. Mixed includes retain the first analysis and add these fields.

Inspect `referenceStatus` for each target: `status` and `reason` distinguish unavailable requests from successful empty results; `provider`, `language`, `supportedLanguages`, and `scope` identify the source and boundaries. `indexFreshness`, `coverage`, `lspCoverage`, and `completeness` describe what is known, not a guarantee: LSP coverage is currently `unknown`. `unresolved.observed`, `unresolved.reasons`, and `unresolved.locations` describe observed locations that could not be assigned an existing source ID; `unresolved.total` is `null` when total coverage is unknown. `excludedCount` and `excludedReasons` count locations outside the scope. `truncated.output` means the service stopped processing locations, and `truncated.provider: "unknown"` means provider truncation is unknown. `referenceBatch.truncated` and `omitted` disclose targets not analyzed.

The service processes at most 20 targets, 200 locations per target, 64 distinct files per target (including the target file), and 8 MiB of retained snapshot text measured in UTF-8 bytes; `params.maxResults` may lower the location limit. Relation and unresolved-location details also share a 400,000-character response budget; omitted details retain reason counts and set `truncated.output`, with `unresolved.omittedLocations` for omitted locations. These limits do not bound the array already returned by LSP. When there is a warning or truncation, an empty result does not prove the symbol is unreferenced. Tool Runtime `ast:reference-analysis` uses the same query; `ast:find-references` returns locations and may fall back to text search, while callers only cover call sites.

## Key Notes

1. **Line numbers are 0-indexed** - Add 1 when showing to users
2. **Use relative paths** for /api/graph/deps (e.g., `src/main/...`)
3. **Symbol IDs are stable** until code changes
4. **API base**: `http://localhost:3033` (prod) or `:3032` (dev)
