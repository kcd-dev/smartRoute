# smartRoute 在 Codex 中的使用指南

> 本文档面向 **Codex CLI 的用户**，说明如何在自己的工作会话中调用和配合 smartRoute。
> 如果你还没安装，先看 [README_zh.md](../README_zh.md) 完成安装和配置。

---

## 目录

- [工作流程概览](#工作流程概览)
- [smartRoute 如何与 Codex 通信](#smartroute-如何与-codex-通信)
- [告诉 Codex 使用 smartRoute](#告诉-codex-使用-smartroute)
- [Provider 与 base_url 配置](#provider-与-base_url-配置)
- [Codex 会收到什么](#codex-会收到什么)
- [好的 Prompt 模式 vs 不好的模式](#好的-prompt-模式-vs-不好的模式)
- [实操示例](#实操示例)
- [排查指南](#排查指南)

---

## 工作流程概览

当 smartRoute 安装完成后，你在 Codex 里的工作流程变成这样：

```
你 → 告诉 Codex 任务
     ↓
Codex 判断风险
     ├─ 低风险 → 调用 codexsaver.delegate_task → Worker LLM 执行 → 返回结果
     │              ↓
     │          Codex 审查 patch → 安全则应用 → 告知你完成
     │
     └─ 高风险或模糊需求 → Codex 自己处理（正常流程）
```

**你的交互方式没有变**，你依然像以前一样跟 Codex 对话。区别在后台：Codex 学会了把合适的任务转给便宜的 worker 模型。

---

## smartRoute 如何与 Codex 通信

smartRoute 通过 **MCP（Model Context Protocol）** 与 Codex 集成。

安装完成后，`.codex/config.toml`（全局或项目级）中注册了一个 MCP 服务：

```toml
[mcp_servers.codexsaver]
command = "python"
args = ["/Users/you/.codexsaver/codexsaver_mcp.py"]
startup_timeout_sec = 10
tool_timeout_sec = 120
```

Codex 启动时会自动加载这个配置，然后就能调用 smartRoute 暴露的 MCP 工具：

| 工具名 | 用途 | 触发方 |
|--------|------|--------|
| `delegate_task` | 将低风险任务委派给 worker LLM | Codex 调用 |

### `delegate_task` 的参数

| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `instruction` | string | 是 | 要委派的编码任务 |
| `files` | string[] | 否 | 需要包含的文件路径 |
| `constraints` | string[] | 否 | 额外的安全或输出约束 |
| `workspace` | string | 否 | 工作区根目录，默认 `.` |
| `max_files` | integer | 否 | 最多加载的文件数，默认 8 |
| `max_chars_per_file` | integer | 否 | 每个文件最大字符数，默认 24000 |
| `max_total_chars` | integer | 否 | 所有文件总字符上限，默认 120000 |
| `dry_run` | boolean | 否 | true 时只预览路由决策，不真实调用 |

**你不需要手动构造这些参数**——你只需要正常跟 Codex 对话，Codex 会决定是否调用及传入什么参数。

---

## 告诉 Codex 使用 smartRoute

启动 Codex 后，你只需要在合适的时机说一句类似这样的话：

```
对低风险任务使用 smartRoute。
```

或者在具体任务前加上：

```
用 smartRoute 给 user service 加单元测试。
```

安装时自动生成的 [AGENTS.md](../AGENTS.md) 已经告知了 Codex 什么任务适合委派、什么任务不该委派，所以通常只需要一句话提示。

### 一句话开启

```
帮我为 smartRoute 保存 worker provider API key，运行 `python cli.py auth set --provider deepseek --api-key ...`，然后运行 `python cli.py install` 和 `python cli.py doctor`，告诉我是否已经就绪。
```

如果 Codex 已经在仓库里，这句话会完成全套配置。

---

## Provider 与 base_url 配置

### 内置 provider 默认已经带 base_url

smartRoute 的 provider 解析不是“必须手填 endpoint”的设计。当前源码里，内置 provider
都有 preset 默认值，所以大多数情况下你**不需要**手动传 `--base-url`。

常见默认值：

| Provider | 默认 base_url |
|----------|---------------|
| `deepseek` | `https://api.deepseek.com/chat/completions` |
| `openai` | `https://api.openai.com/v1/chat/completions` |
| `anthropic` | `https://api.anthropic.com/v1/messages` |
| `gemini` | `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions` |
| `qwen` | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` |
| `ollama` | `http://localhost:11434/v1/chat/completions` |
| `lmstudio` | `http://localhost:1234/v1/chat/completions` |

完整列表请运行：

```bash
python cli.py auth providers
```

### 文档示例里建议显式写 `--base-url`

虽然内置 provider 已经有 preset 默认值，但为了让“当前请求到底发到哪”更直观，本文档里的
示例统一显式写出 `--base-url`。

示例一：DeepSeek，显式写默认 endpoint：

```bash
python cli.py auth set \
  --provider deepseek \
  --api-key YOUR_API_KEY \
  --base-url https://api.deepseek.com/chat/completions
python cli.py doctor
```

示例二：本地 Ollama，显式写本地 endpoint：

```bash
python cli.py auth set \
  --provider ollama \
  --model llama3.1 \
  --base-url http://localhost:11434/v1/chat/completions
python cli.py doctor
```

### 什么时候要显式传 `--base-url`

以下几类情况，建议你明确传：

1. `--provider custom`
2. 走自建中转、代理网关、兼容层
3. 想覆盖内置 provider 的默认 endpoint

示例三：OpenAI 的模型名，但请求走你自己的兼容网关：

```bash
python cli.py auth set \
  --provider openai \
  --api-key YOUR_API_KEY \
  --model gpt-4o-mini \
  --base-url https://gateway.example.com/v1/chat/completions
python cli.py doctor
```

示例四：custom provider，完全自定义：

```bash
python cli.py auth set \
  --provider custom \
  --api-key YOUR_API_KEY \
  --base-url https://example.com/v1/chat/completions \
  --model your-model
python cli.py doctor
```

### `--base-url` 会保存到哪里

`python cli.py auth set` 会把 provider、API key、model、base_url 一起保存到：

```text
~/.codexsaver/config.json
```

所以 `auth set --base-url ...` 不是一次性参数；保存后，后续 `doctor`、CLI 委派和 MCP
运行都会使用这个值。

### 环境变量覆盖顺序

如果你不想改本地配置，也可以只在当前 shell 临时覆盖：

```bash
export CODEXSAVER_BASE_URL=https://gateway.example.com/v1/chat/completions
python cli.py doctor
```

或者使用 provider 专属环境变量：

```bash
export DEEPSEEK_BASE_URL=https://gateway.example.com/v1/chat/completions
python cli.py doctor
```

当前源码里的 `base_url` 优先级从高到低是：

1. `--base-url`
2. `CODEXSAVER_BASE_URL`
3. provider 专属环境变量，例如 `DEEPSEEK_BASE_URL`
4. `~/.codexsaver/config.json` 里的 `providers.<name>.base_url`
5. 内置 preset 默认值

### 如何确认当前实际生效的是哪个 endpoint

运行：

```bash
python cli.py doctor
```

重点看这两个字段：

```json
{
  "provider_base_url": "https://api.deepseek.com/chat/completions",
  "provider_base_url_source": "preset"
}
```

常见来源值：

- `preset`
- `local_config:<provider>`
- `environment:CODEXSAVER_BASE_URL`
- `environment:<PROVIDER>_BASE_URL`

---

## Q&A：给程序员看的原理说明

### Q1：smartRoute 本质上是什么？

本质上它不是“另一个 IDE”，也不是“另一个 skill 包”。

它更像一个**任务分流层**：

1. Codex 负责理解任务和最终把关
2. smartRoute 负责把低风险任务委托给更便宜的 worker
3. worker 返回 patch / changed_files / commands_to_run
4. Codex 再决定是否采用

一句话：

> smartRoute = 给 Codex 增加一个便宜但受控的执行层

### Q2：它怎么判断该不该委托？

不是按“难度分数”机械判断，而是按**风险和边界**判断。

适合委托的通常是：

- 写单元测试
- 搜代码
- 文档更新
- lint / type 错误修复
- 小范围样板代码

不适合委托的通常是：

- 架构决策
- 权限 / 安全
- 支付逻辑
- 数据库迁移
- 生产部署
- 需求描述本身模糊

所以“复杂”不是指代码多，而是指**出错代价大**。

### Q3：它和 skill 的区别是什么？

- **skill**：增强 Codex 的提示词、流程、局部知识
- **smartRoute**：把部分任务真实发给别的模型执行

所以 skill 是“**怎么做**”的知识层，smartRoute 是“**先让谁做**”的执行层。

### Q4：为什么文档要把 `provider` / `model` / `base_url` 分开讲？

因为三者语义完全不同：

- `provider`：上游类别，决定默认 endpoint、鉴权方式、环境变量命名
- `model`：请求里的模型标识
- `base_url`：实际发请求的 HTTP 地址

内部可以理解成：

```text
provider -> preset(base_url, api_style, env_keys)
model -> request.model
base_url -> target endpoint
```

这也是为什么：

- 你可以保留 `provider=openai`
- 但把 `base_url` 指到你自己的 OpenAI-compatible gateway

### Q5：为什么大多数时候不需要手动填 `base_url`？

因为内置 provider 已经有 preset 默认值。

只有三类情况通常要手动填：

1. `provider=custom`
2. 走代理 / 网关 / 兼容层
3. 想覆盖默认 endpoint

### Q6：最终返回给 Codex 的是什么？

不是一句自由文本，而是一段结构化结果，典型包含：

- `decision`
- `changed_files`
- `patch`
- `commands_to_run`
- `risk_notes`

这样 Codex 能做二次审查，而不是盲信 worker。

---

## Codex 会收到什么

当 Codex 调用 `delegate_task` 后，smartRoute 的响应包含一个 **interaction 区块**，方便你（和 Codex）理解发生了什么。

### 三种状态

| interaction mode | 含义 | 说明 |
|-----------------|------|------|
| `preview` | 预览模式 | 只展示路由决策，没有实际调用 worker。`--dry-run` 时出现。|
| `delegated_execution` | 委派成功 | Worker 执行完成，通过验证，Codex 可以审查并应用 patch。 |
| `codex_takeover` | 交回 Codex | 风险太高 / 任务模糊 / worker 失败，smartRoute 把控制权交回 Codex。 |

### 完整响应示例

委派成功时：

```json
{
  "route": "deepseek",
  "status": "success",
  "decision": {
    "route": "deepseek",
    "task_type": "write_tests",
    "risk": "low",
    "reason": "Task is delegatable and risk is acceptable.",
    "protected_hits": []
  },
  "result": {
    "status": "success",
    "summary": "Added unit tests for UserService",
    "changed_files": ["tests/test_user_service.py"],
    "patch": "diff --git a/tests/test_user_service.py...",
    "commands_to_run": ["python -m pytest tests/test_user_service.py"],
    "risk_notes": "Standard test file, no production code changes."
  },
  "verification": {
    "ok": true,
    "reason": "All checks passed.",
    "warnings": []
  },
  "interaction": {
    "tool": "codexsaver.delegate_task",
    "mode": "delegated_execution",
    "headline": "smartRoute delegated this task to the configured worker provider.",
    "route_label": "[smartRoute] route=deepseek task_type=write_tests risk=low",
    "reason": "Task is delegatable and risk is acceptable.",
    "estimated_savings_percent": 45,
    "next_step": "Review the worker result and apply it only if the patch looks safe."
  }
}
```

交回 Codex 时：

```json
{
  "route": "codex",
  "status": "needs_codex",
  "decision": {
    "route": "codex",
    "task_type": "simple_refactor",
    "risk": "high",
    "reason": "Protected path(s) in scope: auth/",
    "protected_hits": ["auth/"]
  },
  "interaction": {
    "mode": "codex_takeover",
    "headline": "smartRoute kept this task in Codex.",
    "route_label": "[smartRoute] route=codex task_type=simple_refactor risk=high",
    "next_step": "Use Codex directly because the task is risky, protected, or ambiguous."
  }
}
```

### Codex 收到响应后的行为

1. **`delegated_execution`**：Codex 审查 worker 返回的 patch 和 risk_notes，安全则直接应用修改，然后运行或建议你运行 `commands_to_run` 中的验证命令。
2. **`codex_takeover`**：Codex 按照正常流程自己处理任务，你不会有任何感知差异。

---

## 好的 Prompt 模式 vs 不好的模式

### 适合委派的任务（低风险）

| 任务 | 推荐说法 | 效果 |
|------|---------|------|
| 单元测试 | "给 user service 加单元测试" | 成功委派 |
| 代码解释 | "解释 router 的路由逻辑" | 成功委派 |
| 文档更新 | "给 config.py 补文档注释" | 成功委派 |
| 搜索代码 | "找到所有调用 set 的地方" | 成功委派 |
| 修 lint | "修复 router.py 的 lint 错误" | 成功委派 |
| 重构（小范围） | "把 UserService 的重复代码提取成公共方法" | 可能委派 |

### 不适合委派的任务（高风险）

| 任务 | 说法 | 路由结果 |
|------|------|---------|
| 认证/授权 | "重构 auth 模块的登录逻辑" | → Codex |
| 支付 | "修改支付流程" | → Codex |
| 安全 | "修复安全漏洞" | → Codex |
| 数据库迁移 | "写数据库迁移脚本" | → Codex |
| 部署 | "写生产部署脚本" | → Codex |
| 敏感路径 | "修改 config/auth.yaml" | → Codex |

### 风险关键词

任务的描述中如果包含以下关键词，会触发 smartRoute 的风险保护，任务会留在 Codex：

```
authentication, authorization, permission, security, payment, billing,
migration, database schema, encrypt, decrypt, secret, token, production, deploy
```

### 文件路径保护

以下路径下的文件会被视为受保护域：

```
auth/, oauth/, jwt/, session/, security/, permission/, rbac/,
payment/, payments/, billing/, invoice/, migration/, schema/,
infra/, terraform/, .github/workflows/, .env, secret/, key/, token/
```

**特别注意**：即使你的任务看起来是低风险（比如"给 auth 模块加注释"），但只要涉及受保护路径，风险等级也会提升。

---

## 实操示例

### 场景 1：写单元测试

你在 Codex 中：

```
给 user service 添加单元测试。
```

Codex 判断这是低风险任务，调用 `delegate_task`，传入 `instruction="给 user service 添加单元测试"` 和相关文件。Worker 返回测试 patch，Codex 审查后写入文件。

```
User
  │ "给 user service 加单元测试"
  ▼
Codex ←── AGENTS.md 指示：write_tests 可以委派
  │
  ├─ Router: task_type=write_tests risk=low
  ├─ ContextPacker: 加载 user service 相关文件
  ├─ DeepSeek worker: 生成测试代码
  ├─ Verifier: 检查输出结构，确认无保护路径
  │
  ▼
Codex 收到 patch → 审查 → 写入 tests/test_user_service.py → 完成
```

### 场景 2：解释代码逻辑

```
解释 router.py 的路由决策逻辑。
```

```
Codex 调用 delegate_task
  → route=deepseek task_type=explain risk=low
  → Worker 返回只读总结
  → Codex 把总结呈现给你
```

### 场景 3：修改受保护模块

```
给 auth 模块加登录日志。
```

```
Codex 调用 delegate_task
  → Router 检测到文件路径含 auth/
  → risk=high → route=codex → codex_takeover
  → Codex 自己处理这个任务
```

### 场景 4：直接通过 CLI 委派（不经过 Codex）

你也可以绕过 Codex，直接从终端调用委派：

```bash
# 预览路由决策
python cli.py "解释 router 的路由逻辑" --files codexsaver/router.py --workspace . --dry-run

# 真实委派
python cli.py "解释 router 的路由逻辑" --files codexsaver/router.py --workspace .

# 使用 delegate 子命令
python cli.py delegate "给 user service 加单元测试" --files src/user/service.py --workspace .
```

---

## 排查指南

### 情形 1：Codex 从不调用 delegate_task

很可能 Codex 不知道 smartRoute 存在。确认：

1. `python cli.py doctor` 报告 `smartRoute is ready`
2. `.codex/config.toml` 或 `~/.codex/config.toml` 包含 `codexsaver` MCP server 条目
3. 对 Codex 说一句 **"对低风险任务使用 smartRoute"**

### 情形 2：所有任务都交回 Codex

检查任务描述中是否含有风险关键词，或文件是否在受保护路径下。Router 的设计就是偏向保守——模糊的任务默认走 Codex。

如果你确信某个任务很安全，可以告诉 Codex 明确排除风险表述。

### 情形 3：Worker 调用失败

```
python cli.py doctor
```

检查：
- API key 是否配置正确（看 `provider_api_key_source` 字段）
- 网络是否能连接 worker provider
- Provider 服务是否正常

### 情形 4：想临时换 provider

```bash
# 临时用环境变量切换
export CODEXSAVER_PROVIDER=openai
export CODEXSAVER_API_KEY=sk-xxx

# 或者持久化切换
python cli.py auth set --provider openai --api-key sk-xxx --model gpt-4o-mini
```

---

## 记住一句话

**你不改变自己的工作方式。Codex 学会在合适的时候叫 smartRoute 帮忙。**

你的职责只是：
1. 确保 smartRoute 已安装就绪（`doctor` 通过）
2. 告诉 Codex "对低风险任务用 smartRoute"
3. 正常描述你的需求

剩下的，Router 决定谁来做，Verifier 确保做得对，你只看到最终结果。
