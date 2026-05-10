# smartRoute — Spec Document

## 1. Concept & Vision

**smartRoute** is a cost-aware AI coding router delivered as an MCP (Model Context Protocol) server. Codex calls it as a tool (`codexsaver.delegate_task`) rather than spawning a subprocess. This keeps Codex's心智模型 clean: smartRoute is not another agent — it is Codex's cost-saving tool.

The philosophy: _don't replace Codex, shrink it_. Let cheap models do the work; let expensive models do the thinking.

**Slogan:** _Make Codex cheaper without making it dumber._

---

## 2. Design Language

### Visual Identity

- **Name:** smartRoute
- **Tagline:** Make Codex cheaper without making it dumber.
- **Primary palette:** terminal-native, monospace-first, minimal chrome
- **Font:** system monospace
- **No external UI** — MCP tool; all feedback is structured JSON

### Log Output Aesthetic (for Codex operators)

```
[smartRoute] Delegating low-risk task to DeepSeek (score=2)
[DeepSeek] Generated 6 tests in 3.2s
[Verifier] Tests passed
[smartRoute] Returning patch to Codex — estimated 62% token savings
```

### README Tone

Engineer-first: no fluff, numbers first, demo immediately visible.

---

## 3. Architecture

```
User
  ↓
Codex (Primary Agent / Brain)
  ↓ MCP tool call: codexsaver.delegate_task
smartRoute MCP Server
  ├─ Task Classifier     (rule-based: delegate or keep)
  ├─ Risk Scorer        (file_risk + task_risk + diff_size + test_confidence)
  ├─ Context Packer     (prune workspace context)
  ├─ Task Runner        (DeepSeek API via openai-compatible client)
  ├─ Verifier           (run tests, lint, parse diff)
  └─ Fallback Engine    (on failure → return needs_codex)
  ↓
DeepSeek API
  ↓
smartRoute Result
  ↓
Codex (reviews patch, applies, finalizes)
```

### MCP Integration

Codex discovers smartRoute via `~/.codex/config.toml` or project-level `.codex/config.toml`:

```toml
[mcp_servers.codexsaver]
command = "python"
args = ["codexsaver_mcp.py"]
startup_timeout_sec = 10
tool_timeout_sec = 120
```

### Data Flow

1. **MCP Input** (tool call from Codex):
   ```json
   {
     "instruction": "Add unit tests for user service",
     "files": ["src/user/service.ts"],
     "constraints": ["Do not modify production logic", "Return patch only"]
   }
   ```

2. **MCP Output** (tool response):
   ```json
   {
     "status": "success",
     "route": "deepseek",
     "summary": "Generated 6 unit tests",
     "changed_files": ["tests/user/service.test.ts"],
     "patch": "git diff output",
     "commands_to_run": ["npm test -- user"],
     "risk_notes": [],
     "estimated_savings_percent": 62
   }
   ```

3. **Fallback Response** (when Codex must take over):
   ```json
   {
     "status": "needs_codex",
     "summary": "Task involves auth logic — too high risk to delegate",
     "risk_notes": ["forbidden path: auth/*"],
     "suggested_action": "Codex handles this"
   }
   ```

---

## 4. Task Routing Strategy

### Rule-Based Classification

**Delegate to DeepSeek** (low-risk, high-volume):

```yaml
- summarize repository
- locate files
- explain code
- write tests for existing function
- update docs
- simple refactor under 5 files
- fix lint/type errors
- generate migration draft
```

**Keep in Codex** (high-risk, complex judgment):

```yaml
- architecture decision
- security-sensitive change
- auth/payment/permission logic
- database migration with data loss risk
- ambiguous product requirement
- final review before commit
- failed DeepSeek attempt
```

### Risk Scoring

```
risk = file_risk + task_risk + diff_size + test_confidence
```

| Score  | Action                                  |
|--------|-----------------------------------------|
| ≤ 3    | DeepSeek executes directly              |
| 4–6    | DeepSeek executes, Codex validates       |
| ≥ 7    | Codex handles it                        |

**High-risk file paths** (never delegated directly):
```
auth/*
security/*
billing/*
payments/*
migrations/*
infra/*
.github/workflows/*
```

---

## 5. Core Components

### 5.1 Task Classifier

Reads task description and workspace, outputs a routing decision with risk score. Uses keyword matching + path scanning.

### 5.2 Context Packer

Prunes workspace context to fit within the configured worker model's context window. Removes boilerplate, node_modules, build artifacts. Outputs a focused prompt with file references.

### 5.3 Worker Provider Client

Calls the configured worker provider through an OpenAI-compatible Chat Completions API. DeepSeek remains the default provider, and custom providers can be configured with a base URL and model.

### 5.4 Verifier

After the worker provider completes:
1. Parse changed files from diff
2. Check forbidden paths were not touched
3. Run project test suite (`npm test`, `pytest`, etc.)
4. Run linter if available
5. Produce final status + diff

### 5.5 Fallback Engine

If any of these occur, smartRoute returns `needs_codex`:
- Test failures
- Diff touches forbidden paths
- DeepSeek API error or timeout
- Risk score ≥ 7

---

## 6. MCP Tool Interface

### Tool Name

```
codexsaver.delegate_task
```

### Input Schema

```json
{
  "instruction": "string (required)",
  "files": "string[] (optional, files to focus on)",
  "constraints": "string[] (optional, instructions for DeepSeek)",
  "workspace": "string (optional, defaults to cwd)"
}
```

### Output Schema

```json
{
  "status": "success | failed | needs_codex",
  "route": "deepseek | codex",
  "summary": "string",
  "changed_files": "string[]",
  "patch": "string",
  "commands_to_run": "string[]",
  "risk_notes": "string[]",
  "estimated_savings_percent": "number"
}
```

---

## 7. Codex Policy (AGENTS.md)

```markdown
# smartRoute Policy

You have access to a tool named `codexsaver.delegate_task`.

## When to Use smartRoute

Use smartRoute for:
- repo scanning
- code explanation
- writing tests
- simple refactors
- lint/type fixes
- documentation updates
- boilerplate generation

Do NOT use smartRoute for:
- architecture decisions
- auth/security/payment logic
- database migrations
- ambiguous requirements
- final review

## Workflow

1. If task is low-risk, call `codexsaver.delegate_task`.
2. Review the returned patch carefully.
3. Run or recommend tests.
4. Apply only if safe.
5. If smartRoute returns `needs_codex`, take over yourself.
```

---

## 8. File Structure

```
codexsaver/
├── SPEC.md
├── README.md
├── codexsaver_mcp.py        # MCP server entry point
├── codexsaver/
│   ├── __init__.py
│   ├── router.py            # Task classification + risk scoring
│   ├── packer.py            # Context pruning
│   ├── deepseek_client.py   # DeepSeek API client
│   ├── verifier.py          # Diff + test verification
│   ├── fallback.py          # Escalation logic
│   └── models.py           # Task/Result dataclasses
├── .codex/
│   └── config.toml          # Codex MCP configuration
├── AGENTS.md                # Codex policy
└── tests/
    └── ...
```

---

## 9. Success Metrics

| Metric                              | Target                      |
|-------------------------------------|-----------------------------|
| Codex token cost reduction           | 40–70%                      |
| Task success rate delta              | < 3% degradation            |
| Average completion time delta        | < 20% increase              |
| DeepSeek output re-do rate by Codex  | < 25%                       |
| Test pass rate                       | ≥ current Codex-only baseline |
| High-risk file DeepSeek direct edits | 0                           |

---

## 10. Design Principles

1. **DeepSeek can write, Codex must validate.** The split is by _verification difficulty_, not by _task type alone_.
2. **Fail fast and escalate.** One DeepSeek failure → escalate to Codex. Never burn tokens on retry loops.
3. **Zero friction for Codex.** smartRoute is an MCP tool — no shell spawning, no stdio pipe parsing.
4. **Observable.** Every step logs its decision so operators can audit routing behavior.
5. **Token savings first.** Every feature is justified by cost reduction or quality maintenance.
6. **smartRoute never touches code directly.** It returns a patch; Codex applies it.

---

## 11. Out of Scope (MVP)

- CLI wrapper (deprecated — MCP is primary)
- Learning-based routing
- Web dashboard
- Multi-workspace support
- worker session resume

---

## 12. Environment Variables

| Variable           | Description                  | Required |
|--------------------|------------------------------|----------|
| `CODEXSAVER_PROVIDER` | Worker provider name (`deepseek` by default) | No |
| `CODEXSAVER_API_KEY` | Generic worker provider API key | Yes for live delegation |
| `CODEXSAVER_BASE_URL` | Generic OpenAI-compatible chat completions URL | Required for custom providers |
| `CODEXSAVER_MODEL` | Generic worker model override | Required for custom providers |
| `DEEPSEEK_API_KEY` | Backward-compatible DeepSeek API key | No |

---

## 13. Install Behavior

`python cli.py install` writes a global Codex MCP server entry to
`~/.codex/config.toml` by default. The entry points to a stable launcher at
`~/.codexsaver/codexsaver_mcp.py`, so every Codex workspace can use the same
smartRoute server without adding per-project config.

Use `python cli.py install --project` only when a repository-local
`.codex/config.toml` is preferred.

Provider credentials are persisted separately in `~/.codexsaver/config.json`,
with file permissions restricted to the local user.

---

_This spec was designed collaboratively and approved before implementation._
