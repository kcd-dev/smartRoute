# RouteMint MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a working RouteMint MCP server (`codexsaver_mcp.py`) that Codex calls as a tool. The server routes low-cost tasks to DeepSeek API, verifies results, and returns a patch for Codex to apply.

**Architecture:** Python 3.10+ with MCP SDK. RouteMint is an MCP server that receives tool calls, routes tasks, calls DeepSeek, verifies output, and returns structured JSON. No subprocess spawning, no stdio pipe parsing.

**Tech Stack:** Python 3.10+, `mcp` library, `openai` (DeepSeek compatible), `python-dotenv`

---

## File Structure

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
├── pyproject.toml
└── tests/
    ├── test_router.py
    ├── test_packer.py
    ├── test_verifier.py
    └── test_mcp.py
```

---

### Task 1: Project Scaffold + pyproject.toml + Models

**Files:**
- Create: `pyproject.toml`
- Create: `codexsaver/__init__.py`
- Create: `codexsaver/models.py`
- Create: `.codex/config.toml`
- Create: `AGENTS.md`

- [ ] **Step 1: Create pyproject.toml**

```toml
[project]
name = "codexsaver"
version = "0.1.0"
description = "Cost-aware AI coding router — Codex does the thinking, DeepSeek does the work."
readme = "README.md"
requires-python = ">=3.10"
dependencies = [
    "mcp>=1.0.0",
    "openai>=1.0.0",
    "python-dotenv>=1.0.0",
]

[project.scripts]
codexsaver = "codexsaver_mcp:main"

[build-system]
requires = ["setuptools>=61.0"]
build-backend = "setuptools.build_meta"
```

- [ ] **Step 2: Create codexsaver/__init__.py**

```python
"""RouteMint — Cost-aware AI coding router."""
```

- [ ] **Step 3: Create codexsaver/models.py**

```python
from dataclasses import dataclass, field
from typing import Literal

@dataclass
class DelegateTaskInput:
    instruction: str
    files: list[str] = field(default_factory=list)
    constraints: list[str] = field(default_factory=list)
    workspace: str = ""

@dataclass
class DelegateTaskOutput:
    status: Literal["success", "failed", "needs_codex"]
    route: Literal["deepseek", "codex"]
    summary: str
    changed_files: list[str] = field(default_factory=list)
    patch: str = ""
    commands_to_run: list[str] = field(default_factory=list)
    risk_notes: list[str] = field(default_factory=list)
    estimated_savings_percent: float = 0.0

FORBIDDEN_PATHS = [
    "auth/*", "security/*", "billing/*", "payments/*",
    "migrations/*", "infra/*", ".github/workflows/*"
]
```

- [ ] **Step 4: Create .codex/config.toml**

```toml
[mcp_servers.codexsaver]
command = "python"
args = ["codexsaver_mcp.py"]
startup_timeout_sec = 10
tool_timeout_sec = 120
```

- [ ] **Step 5: Create AGENTS.md**

```markdown
# RouteMint Policy

You have access to a tool named `codexsaver.delegate_task`.

## When to Use RouteMint

Use RouteMint for:
- repo scanning
- code explanation
- writing tests
- simple refactors
- lint/type fixes
- documentation updates
- boilerplate generation

Do NOT use RouteMint for:
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
5. If RouteMint returns `needs_codex`, take over yourself.
```

- [ ] **Step 6: Commit**

```bash
git add pyproject.toml codexsaver/__init__.py codexsaver/models.py .codex/config.toml AGENTS.md
git commit -m "feat: project scaffold with models and MCP config"
```

---

### Task 2: Router — Task Classification + Risk Scoring

**Files:**
- Create: `codexsaver/router.py`
- Create: `tests/test_router.py`

- [ ] **Step 1: Write failing test for router**

```python
# tests/test_router.py
import pytest
from codexsaver.router import TaskRouter, RoutingDecision

def test_delegate_simple_task():
    router = TaskRouter()
    decision = router.decide("add unit tests for user service", "src/")
    assert decision.delegate_to_deepseek is True
    assert decision.risk_score <= 3

def test_keep_architecture_task():
    router = TaskRouter()
    decision = router.decide("design new authentication architecture", "src/")
    assert decision.delegate_to_deepseek is False

def test_keep_security_sensitive():
    router = TaskRouter()
    decision = router.decide("fix the auth logic", "src/auth/")
    assert decision.delegate_to_deepseek is False

def test_risk_score_calculation():
    router = TaskRouter()
    decision = router.decide("write tests for user service", "src/")
    assert 0 <= decision.risk_score <= 10

def test_high_risk_path_blocks_delegation():
    router = TaskRouter()
    decision = router.decide("write tests", "auth/")
    assert decision.delegate_to_deepseek is False
    assert decision.risk_score >= 7
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_router.py -v`
Expected: FAIL — router module not found

- [ ] **Step 3: Write router implementation**

```python
# codexsaver/router.py
import re
from dataclasses import dataclass

DELEGATE_PATTERNS = [
    r"summarize",
    r"repository",
    r"locate|find.*file",
    r"explain.*code",
    r"write.*test",
    r"simple.*refactor",
    r"fix.*lint",
    r"fix.*type.*error",
    r"update.*doc",
    r"add.*test",
    r"generate.*draft",
]

KEEP_PATTERNS = [
    r"architecture",
    r"security",
    r"auth",
    r"payment",
    r"migration",
    r"database",
    r"ambig",
    r"review.*before.*commit",
    r"final.*review",
]

HIGH_RISK_PATHS = [
    "auth", "security", "billing", "payments",
    "migrations", "infra", ".github/workflows"
]

HIGH_RISK_KEYWORDS = [
    "auth", "security", "billing", "payment", "permission",
    "password", "credential", "token", "encryption"
]

@dataclass
class RoutingDecision:
    delegate_to_deepseek: bool
    risk_score: int
    reason: str
    suggested_action: str

class TaskRouter:
    def __init__(self):
        self.delegate_re = [re.compile(p, re.I) for p in DELEGATE_PATTERNS]
        self.keep_re = [re.compile(p, re.I) for p in KEEP_PATTERNS]

    def decide(self, instruction: str, workspace: str) -> RoutingDecision:
        instruction_lower = instruction.lower()

        for pattern in self.keep_re:
            if pattern.search(instruction_lower):
                return RoutingDecision(
                    delegate_to_deepseek=False,
                    risk_score=8,
                    reason=f"keep pattern matched: {pattern.pattern}",
                    suggested_action="Codex handles this"
                )

        for pattern in self.delegate_re:
            if pattern.search(instruction_lower):
                risk = self._calc_risk(instruction_lower, workspace)
                return RoutingDecision(
                    delegate_to_deepseek=risk < 7,
                    risk_score=risk,
                    reason=f"delegate pattern matched: {pattern.pattern}",
                    suggested_action="DeepSeek" if risk < 7 else "Codex"
                )

        risk = self._calc_risk(instruction_lower, workspace)
        return RoutingDecision(
            delegate_to_deepseek=False,
            risk_score=risk,
            reason="default — no pattern matched",
            suggested_action="DeepSeek" if risk <= 3 else "Codex"
        )

    def _calc_risk(self, instruction: str, workspace: str) -> int:
        risk = 0
        if any(kw in instruction for kw in ["refactor", "migrate", "rewrite"]):
            risk += 2
        if "test" in instruction:
            risk -= 1
        for path in HIGH_RISK_PATHS:
            if path in workspace.lower():
                risk += 5
                break
        if any(kw in instruction for kw in HIGH_RISK_KEYWORDS):
            risk += 3
        return max(0, min(10, risk))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_router.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add codexsaver/router.py tests/test_router.py
git commit -m "feat: add task router with rule-based classification and risk scoring"
```

---

### Task 3: DeepSeek API Client

**Files:**
- Create: `codexsaver/deepseek_client.py`
- Create: `tests/test_deepseek_client.py`

- [ ] **Step 1: Write failing test for deepseek client**

```python
# tests/test_deepseek_client.py
import pytest
from unittest.mock import patch, MagicMock
from codexsaver.deepseek_client import DeepSeekClient

def test_build_messages():
    client = DeepSeekClient(api_key="test-key")
    messages = client._build_messages("add tests", ["src/foo.ts"], [])
    assert len(messages) == 2
    assert messages[0]["role"] == "system"
    assert messages[1]["role"] == "user"
    assert "add tests" in messages[1]["content"]

def test_estimate_savings():
    client = DeepSeekClient(api_key="test-key")
    savings = client.estimate_savings("add unit tests for auth service")
    assert 0 <= savings <= 100
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_deepseek_client.py -v`
Expected: FAIL — deepseek_client module not found

- [ ] **Step 3: Write deepseek client implementation**

```python
# codexsaver/deepseek_client.py
import os
import json
from typing import Generator
from openai import OpenAI

DEEPSEEK_BASE_URL = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com")

class DeepSeekClient:
    def __init__(self, api_key: str | None = None):
        self.api_key = api_key or os.getenv("DEEPSEEK_API_KEY", "")
        self.base_url = os.getenv("DEEPSEEK_BASE_URL", DEEPSEEK_BASE_URL)
        self.client = OpenAI(api_key=self.api_key, baseURL=self.base_url)

    def chat(
        self,
        instruction: str,
        files: list[str] | None = None,
        constraints: list[str] | None = None,
        workspace: str = "."
    ) -> Generator[str, None, None]:
        messages = self._build_messages(instruction, files or [], constraints or [])
        response = self.client.chat.completions.create(
            model="deepseek-chat",
            messages=messages,
            stream=True,
        )
        for chunk in response:
            if chunk.choices[0].delta.content:
                yield chunk.choices[0].delta.content

    def chat_single(self, instruction: str, files: list[str] | None = None, constraints: list[str] | None = None) -> str:
        messages = self._build_messages(instruction, files or [], constraints or [])
        response = self.client.chat.completions.create(
            model="deepseek-chat",
            messages=messages,
            stream=False,
        )
        return response.choices[0].message.content or ""

    def _build_messages(self, instruction: str, files: list[str], constraints: list[str]) -> list[dict]:
        system_prompt = (
            "You are a skilled coding assistant. Follow the instruction precisely.\n"
            "Output format: respond with a JSON object containing:\n"
            "  - changed_files: list of files to create/modify\n"
            "  - patch: git diff style patch\n"
            "  - summary: brief description of changes\n"
            "If you need to create or modify files, use git diff format.\n"
            "Do NOT modify files outside the scope of the instruction."
        )
        user_content = instruction
        if files:
            user_content += f"\n\nFocus files:\n" + "\n".join(f"- {f}" for f in files)
        if constraints:
            user_content += f"\n\nConstraints:\n" + "\n".join(f"- {c}" for c in constraints)

        return [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_content},
        ]

    def estimate_savings(self, instruction: str) -> float:
        instruction_lower = instruction.lower()
        if any(kw in instruction_lower for kw in ["test", "lint", "doc", "search", "explain"]):
            return 65.0
        if any(kw in instruction_lower for kw in ["refactor", "fix", "update"]):
            return 50.0
        return 40.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_deepseek_client.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add codexsaver/deepseek_client.py tests/test_deepseek_client.py
git commit -m "feat: add DeepSeek API client"
```

---

### Task 4: Verifier — Diff + Test Verification

**Files:**
- Create: `codexsaver/verifier.py`
- Create: `tests/test_verifier.py`

- [ ] **Step 1: Write failing test for verifier**

```python
# tests/test_verifier.py
import pytest
import tempfile
import subprocess
import os
from codexsaver.verifier import Verifier

def test_git_diff_returns_changed_files():
    with tempfile.TemporaryDirectory() as tmpdir:
        subprocess.run(["git", "init"], cwd=tmpdir, capture_output=True)
        with open(os.path.join(tmpdir, "foo.txt"), "w") as f:
            f.write("hello")
        subprocess.run(["git", "add", "foo.txt"], cwd=tmpdir, capture_output=True)
        subprocess.run(["git", "commit", "-m", "init"], cwd=tmpdir, capture_output=True)
        with open(os.path.join(tmpdir, "foo.txt"), "w") as f:
            f.write("world")

        verifier = Verifier(tmpdir)
        diff, files = verifier.get_git_diff()
        assert "foo.txt" in files

def test_forbidden_path_check_blocks_auth():
    verifier = Verifier(".")
    result = verifier.check_forbidden(["auth/login.go"], ["auth/*"])
    assert len(result) > 0

def test_no_violation_on_safe_paths():
    verifier = Verifier(".")
    result = verifier.check_forbidden(["src/utils/foo.go"], ["auth/*"])
    assert len(result) == 0
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_verifier.py -v`
Expected: FAIL — verifier module not found

- [ ] **Step 3: Write verifier implementation**

```python
# codexsaver/verifier.py
import subprocess
import fnmatch
from typing import Tuple

class Verifier:
    def __init__(self, workspace: str = "."):
        self.workspace = workspace

    def get_git_diff(self) -> Tuple[str, list[str]]:
        result = subprocess.run(
            ["git", "diff", "--name-only"],
            cwd=self.workspace,
            capture_output=True,
            text=True
        )
        files = [f.strip() for f in result.stdout.splitlines() if f.strip()]
        diff_result = subprocess.run(
            ["git", "diff"],
            cwd=self.workspace,
            capture_output=True,
            text=True
        )
        return diff_result.stdout, files

    def check_forbidden(self, changed_files: list[str], forbidden_paths: list[str]) -> list[str]:
        violated = []
        for file in changed_files:
            for pattern in forbidden_paths:
                if self._match_path(file, pattern):
                    violated.append(file)
        return violated

    def run_tests(self, test_cmd: str | None = None) -> Tuple[bool, str]:
        if not test_cmd:
            for cmd in ["npm test", "pytest", "cargo test", "go test ./..."]:
                result = subprocess.run(
                    cmd.split(), cwd=self.workspace, capture_output=True, text=True, timeout=60
                )
                if result.returncode in (0, 1):
                    return result.returncode == 0, result.stdout + result.stderr
            return False, "no test command found"
        result = subprocess.run(
            test_cmd.split(), cwd=self.workspace, capture_output=True, text=True, timeout=120
        )
        return result.returncode == 0, result.stdout + result.stderr

    def _match_path(self, file: str, pattern: str) -> bool:
        normalized = pattern.replace("/*", "/**/*")
        return (
            fnmatch.fnmatch(file, normalized)
            or fnmatch.fnmatch(file, pattern)
            or fnmatch.fnmatch(file, pattern.replace("/**/*", "/*"))
        )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_verifier.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add codexsaver/verifier.py tests/test_verifier.py
git commit -m "feat: add verifier for diff parsing and test running"
```

---

### Task 5: Fallback Engine

**Files:**
- Create: `codexsaver/fallback.py`
- Create: `tests/test_fallback.py`

- [ ] **Step 1: Write failing test for fallback**

```python
# tests/test_fallback.py
import pytest
from codexsaver.fallback import FallbackEngine

def test_escalate_high_risk():
    engine = FallbackEngine()
    decision = engine.should_escalate(risk_score=8, changed_files=["auth/foo.go"], test_passed=False, api_failed=False)
    assert decision.escalate is True

def test_no_escalate_low_risk_passed():
    engine = FallbackEngine()
    decision = engine.should_escalate(risk_score=2, changed_files=["src/foo.go"], test_passed=True, api_failed=False)
    assert decision.escalate is False

def test_escalate_on_api_failure():
    engine = FallbackEngine()
    decision = engine.should_escalate(risk_score=3, changed_files=["src/foo.go"], test_passed=True, api_failed=True)
    assert decision.escalate is True

def test_escalate_on_forbidden_path():
    engine = FallbackEngine()
    decision = engine.should_escalate(risk_score=3, changed_files=["auth/bar.go"], test_passed=True, api_failed=False)
    assert decision.escalate is True
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_fallback.py -v`
Expected: FAIL — fallback module not found

- [ ] **Step 3: Write fallback implementation**

```python
# codexsaver/fallback.py
from dataclasses import dataclass

FORBIDDEN_KEYWORDS = ["auth", "security", "billing", "payments", "migrations", "infra"]

@dataclass
class EscalationDecision:
    escalate: bool
    reason: str
    suggested_action: str

class FallbackEngine:
    def should_escalate(
        self,
        risk_score: int,
        changed_files: list[str],
        test_passed: bool,
        api_failed: bool
    ) -> EscalationDecision:
        if risk_score >= 7:
            return EscalationDecision(
                escalate=True,
                reason=f"high risk score: {risk_score}",
                suggested_action="Codex handles this"
            )

        forbidden_hit = any(
            any(kw in f for kw in FORBIDDEN_KEYWORDS) for f in changed_files
        )
        if forbidden_hit:
            return EscalationDecision(
                escalate=True,
                reason="forbidden path modified",
                suggested_action="Codex must review"
            )

        if api_failed:
            return EscalationDecision(
                escalate=True,
                reason="DeepSeek API failed",
                suggested_action="Escalate to Codex"
            )

        if not test_passed:
            return EscalationDecision(
                escalate=True,
                reason="tests failed after DeepSeek execution",
                suggested_action="Codex must investigate"
            )

        return EscalationDecision(
            escalate=False,
            reason="task completed successfully within risk bounds",
            suggested_action="Return result to Codex"
        )
```

- [ ] **Step 4: Run test to verify it passes**

Run: `python -m pytest tests/test_fallback.py -v`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add codexsaver/fallback.py tests/test_fallback.py
git commit -m "feat: add fallback engine for escalation decisions"
```

---

### Task 6: MCP Server Entry Point

**Files:**
- Create: `codexsaver_mcp.py`
- Create: `tests/test_mcp.py`

- [ ] **Step 1: Write failing test for MCP server**

```python
# tests/test_mcp.py
import pytest
from codexsaver.models import DelegateTaskInput

def test_delegate_task_input_model():
    inp = DelegateTaskInput(instruction="add tests for foo")
    assert inp.instruction == "add tests for foo"
    assert inp.files == []
    assert inp.constraints == []

def test_delegate_task_output_model():
    from codexsaver.models import DelegateTaskOutput
    out = DelegateTaskOutput(status="success", route="deepseek", summary="done")
    assert out.status == "success"
    assert out.route == "deepseek"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `python -m pytest tests/test_mcp.py -v`
Expected: FAIL — mcp module not found (or test passes depending on import)

- [ ] **Step 3: Write MCP server implementation**

```python
# codexsaver_mcp.py
import sys
import json
from mcp.server import Server
from mcp.types import Tool, ToolInputSchema
from mcp.server.stdio import stdio_server

from codexsaver.models import DelegateTaskInput, DelegateTaskOutput
from codexsaver.router import TaskRouter
from codexsaver.deepseek_client import DeepSeekClient
from codexsaver.verifier import Verifier
from codexsaver.fallback import FallbackEngine
from codexsaver.models import FORBIDDEN_PATHS

APP_NAME = "RouteMint"
APP_VERSION = "0.1.0"

server = Server(APP_NAME)

@server.list_tools()
async def list_tools() -> list[Tool]:
    return [
        Tool(
            name="codexsaver.delegate_task",
            description="Delegate a low-cost coding task to DeepSeek via RouteMint. "
                       "Use for: repo scanning, tests, simple refactors, lint fixes, docs. "
                       "DO NOT use for: auth, security, payments, migrations, architecture.",
            input_schema=ToolInputSchema(
                properties={
                    "instruction": {"type": "string", "description": "What to do"},
                    "files": {"type": "array", "items": {"type": "string"}, "description": "Files to focus on"},
                    "constraints": {"type": "array", "items": {"type": "string"}, "description": "Additional constraints"},
                    "workspace": {"type": "string", "description": "Workspace directory (defaults to cwd)"},
                },
                required=["instruction"],
            ),
        )
    ]

@server.call_tool()
async def call_tool(tool_name: str, arguments: dict) -> list[dict]:
    if tool_name != "codexsaver.delegate_task":
        raise ValueError(f"Unknown tool: {tool_name}")

    instruction = arguments["instruction"]
    files = arguments.get("files", [])
    constraints = arguments.get("constraints", [])
    workspace = arguments.get("workspace", ".")

    input_obj = DelegateTaskInput(
        instruction=instruction,
        files=files,
        constraints=constraints,
        workspace=workspace,
    )

    router = TaskRouter()
    decision = router.decide(instruction, workspace)

    if not decision.delegate_to_deepseek and decision.risk_score >= 7:
        output = DelegateTaskOutput(
            status="needs_codex",
            route="codex",
            summary=f"Task too risky (score={decision.risk_score}): {decision.reason}",
            risk_notes=[decision.reason],
        )
        return [dict(content=json.dumps(output.__dict__, ensure_ascii=False), mime_type="application/json")]

    client = DeepSeekClient()
    verifier = Verifier(workspace)

    try:
        response_text = client.chat_single(instruction, files, constraints)
    except Exception as e:
        fallback = FallbackEngine()
        esc = fallback.should_escalate(risk_score=decision.risk_score, changed_files=[], test_passed=False, api_failed=True)
        output = DelegateTaskOutput(
            status="needs_codex",
            route="codex",
            summary=f"DeepSeek API failed: {e}",
            risk_notes=[str(e)],
        )
        return [dict(content=json.dumps(output.__dict__, ensure_ascii=False), mime_type="application/json")]

    diff, changed_files = verifier.get_git_diff()
    forbidden_hit = verifier.check_forbidden(changed_files, FORBIDDEN_PATHS)
    test_passed, test_output = verifier.run_tests()

    fallback = FallbackEngine()
    esc = fallback.should_escalate(
        risk_score=decision.risk_score,
        changed_files=changed_files,
        test_passed=test_passed,
        api_failed=False
    )

    savings = client.estimate_savings(instruction)

    if esc.escalate:
        output = DelegateTaskOutput(
            status="needs_codex",
            route="codex",
            summary=esc.reason,
            changed_files=changed_files,
            risk_notes=[esc.reason] + (["forbidden paths hit"] if forbidden_hit else []),
            estimated_savings_percent=savings,
        )
    else:
        output = DelegateTaskOutput(
            status="success",
            route="deepseek",
            summary=response_text[:200] if len(response_text) > 200 else response_text,
            changed_files=changed_files,
            patch=diff,
            commands_to_run=[],
            risk_notes=[],
            estimated_savings_percent=savings,
        )

    return [dict(content=json.dumps(output.__dict__, ensure_ascii=False), mime_type="application/json")]

async def main():
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())

if __name__ == "__main__":
    import asyncio
    asyncio.run(main())
```

- [ ] **Step 4: Verify imports work**

Run: `python -c "from codexsaver import router, deepseek_client, verifier, fallback, models"`
Expected: No import errors

- [ ] **Step 5: Commit**

```bash
git add codexsaver_mcp.py
git commit -m "feat: add MCP server entry point with delegate_task tool"
```

---

### Task 7: README — MCP + Quick Start

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README with MCP Quick Start**

Add to the end of README.md:

```md
## 🔌 MCP Setup (Recommended)

RouteMint integrates as an MCP server. Add to your Codex config:

```toml
# ~/.codex/config.toml or project .codex/config.toml
[mcp_servers.codexsaver]
command = "python"
args = ["codexsaver_mcp.py"]
startup_timeout_sec = 10
tool_timeout_sec = 120
```

Then in your project add `AGENTS.md` (included in this repo).

## ⚡ Quick Start

```bash
pip install .
export DEEPSEEK_API_KEY=your_key_here
python codexsaver_mcp.py
```

Codex will automatically discover the `codexsaver.delegate_task` tool.
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add MCP setup and quick start to README"
```

---

## Spec Coverage Check

- [x] MCP server entry point — Task 6
- [x] `delegate_task` tool interface — Task 6
- [x] Task classification (rule-based) — Task 2
- [x] Risk scoring — Task 2
- [x] DeepSeek API client — Task 3
- [x] Diff verification — Task 4
- [x] Test verification — Task 4
- [x] Forbidden path check — Task 4
- [x] Fallback/escalation — Task 5
- [x] Codex config (`.codex/config.toml`) — Task 1
- [x] AGENTS.md policy — Task 1
- [x] README with MCP quick start — Task 7

## Placeholder Scan

No TBD/TODO placeholders found. All steps show actual code. All file paths are exact.

---

**Plan complete and saved to `docs/superpowers/plans/2026-05-06-codexsaver-mvp.md`.**

**Two execution options:**

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks sequentially in this session using `executing-plans`

Which approach?
