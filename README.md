# smartRoute

> 在不让 Codex 变笨的前提下，让它更便宜。

<p align="center">
  <a href="./README_EN.md"><strong>English</strong></a>
  ·
  <a href="./README_zh.md"><strong>中文备份页</strong></a>
</p>

![smartRoute](./smartRoute.png)

smartRoute 是一个 MCP 工具，它把 Codex 变成一个有成本意识的路由器。
低风险开发工作下放给更便宜的 worker LLM，高风险判断留给 Codex，并且返回足够清晰的交互信息，
让你明显感知到这个工具正在工作。

- 用更低成本处理测试、文档、搜索、解释类任务
- Codex 继续负责架构、安全、受保护域和最终审核
- 默认全局安装，一次配置后每个 Codex 工作区都能使用
- 默认 DeepSeek，同时支持 OpenAI、Anthropic、Gemini、Qwen、Ollama、LM Studio 等 provider
- provider 配置持久化到 `~/.codexsaver/config.json`
- 已通过测试、真实 DeepSeek 调用和全局 MCP launcher 检查

---

## 这个项目解决什么问题

大多数编码会话其实混着两类完全不同的工作：

- 昂贵的判断
- 廉价的执行

Codex 很擅长第一类，但用它去做大量第二类工作，往往太贵了。

smartRoute 故意把这两件事拆开：

- `Codex` 负责推理、模糊需求、受保护域和审批
- 已配置的 worker provider 负责低风险、高吞吐的执行工作

它想建立的是这样一个模式：

```text
把昂贵模型用在判断上。
把便宜模型用在体力活上。
不要混用这两种价值。
```

---

## 用起来是什么感觉

smartRoute 返回的不是一段静默 JSON。
它会附带一个 `interaction` 区块，让你一眼看出这次调用发生了什么：

```json
{
  "interaction": {
    "tool": "codexsaver.delegate_task",
    "mode": "delegated_execution",
    "headline": "smartRoute delegated this task to the configured worker provider.",
    "route_label": "[smartRoute] route=deepseek task_type=write_tests risk=low",
    "next_step": "Review the worker result and apply it only if the patch looks safe."
  }
}
```

你只需要理解三种状态：

- `preview`：只是预览路由，没有外部模型调用
- `delegated_execution`：委派执行已经完成
- `codex_takeover`：风险太高或任务太模糊，交回 Codex 处理

---

## 快速开始

### 推荐：全局安装

```bash
git clone git@github.com:kcd-dev/smartRoute.git
cd smartRoute

python cli.py auth set --provider deepseek --api-key YOUR_API_KEY
python cli.py install
python cli.py doctor
```

这就够了。`python cli.py install` 会把 smartRoute 写入全局 Codex MCP 配置
`~/.codex/config.toml`，并指向一个稳定启动入口：
`~/.codexsaver/codexsaver_mcp.py`。

之后任意 Codex 工作区都可以调用：

```text
codexsaver.delegate_task
```

只有当你想写入当前仓库自己的 `.codex/config.toml` 时，才需要使用：

```bash
python cli.py install --project
```

### Provider 配置

smartRoute 的**内置 provider 预设自带默认 base_url**，所以大多数情况下你只需要选 provider、
填 API key、必要时覆盖 model，**不需要手动传 `--base-url`**。

例如：

- `deepseek` 默认走 `https://api.deepseek.com/chat/completions`
- `openai` 默认走 `https://api.openai.com/v1/chat/completions`
- `anthropic` 默认走 `https://api.anthropic.com/v1/messages`
- `ollama` 默认走 `http://localhost:11434/v1/chat/completions`
- `lmstudio` 默认走 `http://localhost:1234/v1/chat/completions`

完整预设列表可以运行：

```bash
python cli.py auth providers
```

#### 1）使用内置 provider（文档示例里建议显式写 `--base-url`）

DeepSeek 是默认 provider，因为价格低，并且提供 OpenAI-compatible API。
虽然内置 provider 自带默认 endpoint，但**为了让当前实际请求地址一眼可见**，下面的文档示例统一显式写出 `--base-url`：

```bash
python cli.py auth set --provider deepseek --api-key YOUR_API_KEY --base-url https://api.deepseek.com/chat/completions
python cli.py auth set --provider openai --api-key YOUR_API_KEY --model gpt-4o-mini --base-url https://api.openai.com/v1/chat/completions
python cli.py auth set --provider anthropic --api-key YOUR_API_KEY --model claude-3-5-haiku-latest --base-url https://api.anthropic.com/v1/messages
python cli.py auth set --provider gemini --api-key YOUR_API_KEY --model gemini-2.0-flash --base-url https://generativelanguage.googleapis.com/v1beta/openai/chat/completions
python cli.py auth set --provider qwen --api-key YOUR_API_KEY --model qwen-plus --base-url https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions
```

本地模型同样建议显式写出来，便于排查当前到底连的是哪个本地 endpoint：

```bash
python cli.py auth set --provider ollama --model llama3.1 --base-url http://localhost:11434/v1/chat/completions
python cli.py auth set --provider lmstudio --model local-model --base-url http://localhost:1234/v1/chat/completions
```

#### 2）什么时候必须或建议传 `--base-url`

以下场景应该显式传 `--base-url`：

1. **`--provider custom`**：没有内置 preset，必须自己提供 endpoint。
2. **你要走代理网关或兼容层**：例如自建中转、one-api、new-api、各类 OpenAI-compatible gateway。
3. **你要覆盖内置 provider 的默认 endpoint**：比如 `openai` 仍然用 OpenAI 的模型名，但请求实际发到你自己的代理。

#### 3）custom provider：必须显式提供 `--base-url`

```bash
python cli.py auth set \
  --provider custom \
  --api-key YOUR_API_KEY \
  --base-url https://example.com/v1/chat/completions \
  --model your-model
```

#### 4）OpenAI-compatible 代理 / 网关：覆盖内置 provider 的默认 `base_url`

```bash
python cli.py auth set \
  --provider openai \
  --api-key YOUR_API_KEY \
  --model gpt-4o-mini \
  --base-url https://gateway.example.com/v1/chat/completions
```

#### 5）配置会保存到哪里

`python cli.py auth set` 会把 provider 相关配置保存到：

```text
~/.codexsaver/config.json
```

如果你传了 `--base-url`，这个值也会一起持久化到本地配置里；之后再次调用 `doctor`、
`delegate` 或 MCP 工具时，都会按这个值解析。

#### 6）只想临时覆盖 `base_url`，不想改本地配置

```bash
export CODEXSAVER_BASE_URL=https://gateway.example.com/v1/chat/completions
python cli.py doctor
```

也可以使用 provider 专属环境变量，例如：

```bash
export DEEPSEEK_BASE_URL=https://gateway.example.com/v1/chat/completions
python cli.py doctor
```

`{PROVIDER}_BASE_URL` 的命名规则和 provider 名字一致，例如：

- `DEEPSEEK_BASE_URL`
- `OPENAI_BASE_URL`
- `ANTHROPIC_BASE_URL`
- `OLLAMA_BASE_URL`

#### 7）`base_url` 的生效优先级

当前源码里的解析顺序是：

1. 命令行显式传入的 `--base-url`
2. 环境变量 `CODEXSAVER_BASE_URL`
3. provider 专属环境变量，如 `DEEPSEEK_BASE_URL`
4. `~/.codexsaver/config.json` 里的 `providers.<name>.base_url`
5. 内置 provider preset 默认值

#### 8）怎么确认现在实际生效的是哪个 `base_url`

运行：

```bash
python cli.py doctor
```

输出里会直接给你：

```json
{
  "provider_base_url": "https://api.deepseek.com/chat/completions",
  "provider_base_url_source": "preset"
}
```

常见的 `provider_base_url_source`：

- `preset`：来自内置默认值
- `local_config:<provider>`：来自 `~/.codexsaver/config.json`
- `environment:CODEXSAVER_BASE_URL`：来自全局环境变量
- `environment:DEEPSEEK_BASE_URL`：来自 provider 专属环境变量

#### 9）三个最常见的完整示例

DeepSeek，直接走默认 base_url：

```bash
python cli.py auth set --provider deepseek --api-key YOUR_API_KEY
python cli.py install
python cli.py doctor
```

OpenAI 模型名，但请求走你自己的代理网关：

```bash
python cli.py auth set \
  --provider openai \
  --api-key YOUR_API_KEY \
  --model gpt-4o-mini \
  --base-url https://gateway.example.com/v1/chat/completions
python cli.py doctor
```

custom provider，完全自定义 endpoint：

```bash
python cli.py auth set \
  --provider custom \
  --api-key YOUR_API_KEY \
  --base-url https://example.com/v1/chat/completions \
  --model your-model
python cli.py doctor
```

#### 10）如果你不想保存 key，而是只在当前 shell 会话里临时使用

```bash
export CODEXSAVER_PROVIDER=deepseek
export CODEXSAVER_API_KEY=YOUR_API_KEY
python cli.py install
python cli.py doctor
```

### Q&A：原理到底是什么

#### Q1：smartRoute 到底做了什么？

它本质上做两件事：

1. **帮 Codex 做低风险任务分流**
2. **把便宜模型的结果包装回 Codex 可审查的结构**

也就是说，smartRoute 不是替代 Codex，而是给 Codex 增加一个“便宜 worker 层”。

- 低风险任务：代码搜索、写单测、文档更新、lint 修复、小范围重构
- 高风险任务：架构、权限、安全、支付、迁移、生产部署

高风险任务不应该自动下放给便宜模型，仍然由 Codex 决策。

#### Q2：它是不是“自动把任务发给便宜模型”？

不是。

更准确地说，它是：

- **先判断任务是否适合委托**
- **适合才委托**
- **不适合就退回 Codex**

所以它不是无脑转发器，而是一个**带保护规则的委托器**。

#### Q3：它怎么判断“简单任务”和“复杂任务”？

当前不是靠一个神秘评分器，而是靠**规则 + 任务上下文 + 风险分类**。

可以粗暴理解成：

1. 先看你给的指令是不是明确、局部、低风险  
   例如：  
   - “给 `router.py` 写单元测试”
   - “修 README 里的错别字”
   - “解释这个函数在干嘛”

2. 再看任务有没有碰到保护区  
   例如：  
   - auth / 权限
   - 安全逻辑
   - 支付逻辑
   - 数据库迁移
   - 生产部署
   - 需求本身很模糊

3. 如果命中保护区，直接不给 worker 做，而是交还 Codex

所以“复杂”不只是代码行数多，而是**风险高、边界不清、后果重**。

#### Q4：那它和 Codex skill 有什么区别？

区别很大：

- **skill**：给 Codex 一套提示词 / 工作流程 / 本地知识
- **smartRoute**：真的把任务发给另一个更便宜的模型执行

所以：

- skill 解决的是“**怎么提示 Codex**”
- smartRoute 解决的是“**哪些活先给便宜 worker 干**”

两者可以一起用，但不是一回事。

#### Q5：为什么 `base_url` 不是必填？

因为 smartRoute 的很多 provider 是**内置预设**。

比如：

- `deepseek` 已经知道默认地址
- `openai` 已经知道默认地址
- `anthropic` 已经知道默认地址
- `ollama` / `lmstudio` 也已经知道本地默认地址

所以你选 provider 时，程序已经能推导出一个默认 endpoint。  
只有以下情况才需要你手动传 `--base-url`：

- 你在用 `custom provider`
- 你在走代理 / 网关 / 兼容层
- 你想覆盖系统默认 endpoint

#### Q6：`provider`、`model`、`base_url` 三者分别是什么？

这是最容易混淆的地方：

- `provider`：你选哪一类上游服务  
  例如 `deepseek`、`openai`、`anthropic`
- `model`：你要调用的具体模型名  
  例如 `deepseek-chat`、`gpt-4o-mini`
- `base_url`：请求实际打到哪个 HTTP endpoint

程序内部通常是：

```text
provider -> 推出默认 base_url / env key / API 风格
model -> 作为请求体里的 model 字段
base_url -> 作为真正发请求的目标地址
```

所以你可以：

- 保持 `provider=openai`
- 但把 `base_url` 改成你自己的 OpenAI-compatible 网关

这也是为什么文档里必须把 `base_url` 讲清楚。

#### Q7：一次真实委托时，smartRoute 返回什么给 Codex？

返回的不是一句“成功了”，而是一段结构化结果，通常包含：

- `decision`：为什么决定委托 / 不委托
- `result.summary`：worker 做了什么
- `changed_files`：改了哪些文件
- `patch`：具体补丁
- `commands_to_run`：建议你本地再跑哪些命令验证
- `risk_notes`：风险提示

所以 Codex 不是“盲信” worker，而是拿到结果后再审查、再决定是否采用。

#### Q8：最重要的一句话怎么理解？

可以直接记这一句：

> **DeepSeek 干便宜活，Codex 负责判断和把关。**

这就是 smartRoute 的核心原理。

### 一句话让 Codex 安装

如果 Codex 已经打开了这个仓库，你可以直接发：

```text
帮我为 smartRoute 保存 worker provider API key，运行 `python cli.py auth set --provider deepseek --api-key ...`，然后运行 `python cli.py install` 和 `python cli.py doctor`，告诉我是否已经就绪。
```

如果你只想做项目级安装：

```text
帮我为 smartRoute 保存 worker provider API key，并只把 smartRoute 安装到当前仓库，运行 `python cli.py auth set --provider deepseek --api-key ...`、`python cli.py install --project`，然后运行 `python cli.py doctor` 并总结结果。
```

这里的“就绪”指的是：

- `~/.codex/config.toml` 包含全局 `codexsaver` MCP server，或仓库里存在 `.codex/config.toml`
- 全局安装时存在 `~/.codexsaver/codexsaver_mcp.py`
- provider 配置来自环境变量或 `~/.codexsaver/config.json`
- `python cli.py doctor` 报告 `smartRoute is ready`

---

## 60 秒体验

`python cli.py install` 生成的全局 MCP 配置大致是：

```toml
[mcp_servers.codexsaver]
command = "python"
args = ["/Users/you/.codexsaver/codexsaver_mcp.py"]
startup_timeout_sec = 10
tool_timeout_sec = 120
```

然后直接告诉 Codex：

```text
对低风险任务使用 smartRoute。
给 user service 添加单元测试。
```

也可以直接走 CLI：

```bash
python cli.py delegate "Explain the routing logic briefly" --files codexsaver/router.py --workspace .
```

试运行：

```bash
python cli.py "添加单元测试" --files src/user/service.ts --workspace . --dry-run
```

真实运行：

```bash
python cli.py "添加单元测试" --files src/user/service.ts --workspace .
```

---

## 已验证的安装流程

基于 2026 年 5 月 8 日、全局安装和本地 key 流程的实测结果：

| 检查项 | 命令 | 结果 |
|---|---|---|
| 全量测试 | `PYTHONDONTWRITEBYTECODE=1 python -m pytest -q -p no:cacheprovider` | `86 passed in 0.23s` |
| 全局安装 | `python cli.py install --workspace .` | `status=ok`，全局配置指向 `~/.codexsaver/codexsaver_mcp.py` |
| 本地 provider 保存 | `python cli.py auth set --provider deepseek --api-key ...` | 已保存到 `~/.codexsaver/config.json` |
| 工作区诊断 | `python cli.py doctor --workspace .` | `provider_api_key_source=local_config:deepseek`，工作区已就绪 |
| 全局 launcher 检查 | 用 MCP `initialize` 调用 `~/.codexsaver/codexsaver_mcp.py` | 返回 `serverInfo.name=codexsaver` |
| 真实 DeepSeek 调用 | `python cli.py delegate "Explain the smartRoute router..." --files codexsaver/router.py --workspace .` | `route=deepseek`、`status=success`、验证通过 |

推荐流程就是：

1. 保存一次 key
2. 全局安装 smartRoute
3. 用 `doctor` 确认就绪
4. 之后直接发起真实委派调用，不再重复导出 API key

---

## Provider 一览

内置预设覆盖常见云端和本地模型：

| Provider | 接口风格 | 默认模型 | API key |
|---|---|---|---|
| `deepseek` | OpenAI-compatible | `deepseek-chat` | 需要 |
| `openai` | OpenAI | `gpt-4o-mini` | 需要 |
| `anthropic` | native Messages API | `claude-3-5-haiku-latest` | 需要 |
| `gemini` | OpenAI-compatible endpoint | `gemini-2.0-flash` | 需要 |
| `qwen` | OpenAI-compatible endpoint | `qwen-plus` | 需要 |
| `ollama` | 本地 OpenAI-compatible endpoint | `llama3.1` | 不需要 |
| `lmstudio` | 本地 OpenAI-compatible endpoint | `local-model` | 不需要 |

完整列表可以运行 `python cli.py auth providers` 查看。

---

## 配置完成后的使用占比

在配置完成之后，我统计了这轮工作会话里真正进入“模型路由决策”的任务。
像 `pytest`、`git`、`install`、`doctor`、README 编辑这类纯本地步骤都不计入比例。

结果是：

- `DeepSeek`：`7 / 8 = 87.5%`
- `Codex`：`1 / 8 = 12.5%`

为什么不是 100%？

有一个测试任务最初包含了 `production logic` 这类措辞。
这会触发路由器有意设计的高风险关键词保护，从而把任务交回 Codex。
这不是失败，而是保护逻辑按预期生效。

如果只看后面那组经过标准化措辞处理的“五任务基准”，则结果是：

- `DeepSeek`：`5 / 5 = 100%`
- `Codex`：`0 / 5 = 0%`

结论很直接：

- 在真实使用里，smartRoute 默认会把大多数低风险小任务交给 DeepSeek
- 但它仍然保留了严格的回退路径，用来处理高风险表述和受保护域

---

## 五个小任务的 A/B 对比

方法说明：

- **A** = 反事实的 `Codex-only` 基线，归一化成本指数固定为 `1.00`
- **B** = `smartRoute` 模式，真实经过当前路由器和 DeepSeek worker 执行
- 延迟统计的是 smartRoute 实时调用的墙钟时间
- 节省比例来自当前 `CostEstimator` 的估算，所以这是一个可复现的路由基准，不是账单级财务数据

文字总结：

- 这 5 个任务都属于典型的低风险开发小任务：解释代码、补文档、补测试、维护 README
- 在使用更自然的低风险表述后，5 个任务全部成功委派
- 实测平均延迟是 `6.18s`
- 平均预计节省是 `48.4%`
- 从归一化成本看，平均成本指数从 `1.00` 降到 `0.52`
- 预计相对下降 `48.0%`

| 任务 | 类型 | 路由 | 延迟 | A: Codex-only 成本指数 | B: smartRoute 成本指数 | 预计节省 | 输出形态 |
|---|---|---|---:|---:|---:|---:|---|
| Explain router logic | `explain` | `deepseek` | `2.13s` | `1.00` | `0.55` | `45%` | 只读总结 |
| Document router module | `docs` | `deepseek` | `3.13s` | `1.00` | `0.55` | `45%` | 单文件 patch |
| Add cost tests | `write_tests` | `deepseek` | `9.29s` | `1.00` | `0.55` | `45%` | 测试 patch |
| Explain verifier flow | `explain` | `deepseek` | `2.30s` | `1.00` | `0.55` | `45%` | 只读总结 |
| Update install docs | `docs` | `deepseek` | `14.06s` | `1.00` | `0.38` | `62%` | README patch |

![五任务基准图](./assets/ab-test-benchmark.svg)

图示说明：
灰色柱子是固定为 `100` 的 `Codex-only` 基线，绿色柱子表示同一任务在
`smartRoute` 模式下的归一化成本指数。柱子越低，预计节省越大。

结果解读：

- 只读解释型任务是最快、最稳定的收益来源
- 小型文档修改也很适合下放，而且会返回紧凑、易审查的 patch
- 测试生成的延迟高于 explain，但仍然保持在低风险节省区间
- 上下文更大的文档任务节省更高，因为 `Codex-only` 模式下的上下文成本更高

---

## 路由规则

### 适合委派给 DeepSeek 的任务

- 仓库扫描和代码搜索
- 代码解释与总结
- 编写单元测试
- 修复 lint / type error
- 文档更新
- 样板代码生成
- 小范围局部重构

### 应该保留给 Codex 的任务

- 架构决策
- 认证、安全、支付、账单、权限逻辑
- 数据库迁移
- 部署和生产操作
- 模糊需求
- 最终审核

### 为什么有些中风险任务仍然会委派

smartRoute 问的不是：

```text
这是不是编码任务？
```

它问的是：

```text
这是不是一个足够便宜、又不会损失判断质量的编码任务？
```

所以它会形成一个刻意的不对称：

- 只读理解型工作可以尽量便宜
- 敏感域里的写操作，哪怕改动很小，风险也会迅速升高
- 一旦任务模糊，默认交回 Codex，而不是默认下放

这也是为什么 `Explain auth code` 还有机会走 DeepSeek，而 `Refactor auth service`
必须留给 Codex。

---

## 工作原理

```text
User
  ↓
Codex
  ↓ MCP tool call
smartRoute
  ├─ Router
  ├─ Context Packer
  ├─ Worker LLM Provider
  ├─ Verifier
  └─ Cost Estimator
  ↓
Codex review / apply / finalize
```

核心模块：

- `Router`：任务分类和风险判断
- `ContextPacker`：在委派前裁剪文件上下文
- `ProviderClient`：调用已配置的 worker 模型
- `Verifier`：检查返回结构、受保护路径和建议命令
- `CostEstimator`：估算相对节省区间

---

## 安全与持久化

- `python cli.py auth set --provider ... --api-key ...` 会把 provider 配置保存到 `~/.codexsaver/config.json`
- 配置文件会使用仅本地用户可读写的权限
- `doctor` 会告诉你 key 是来自环境变量还是本地配置，并且只显示脱敏预览
- 如果没有导出环境变量，真实调用会自动使用本地配置
- 只要验证失败，smartRoute 就会回退为 `needs_codex`

---

## 常用命令

```bash
python cli.py auth providers
python cli.py auth set --provider deepseek --api-key YOUR_API_KEY
python cli.py install
python cli.py install --project
python cli.py doctor
python cli.py delegate "Explain the routing logic briefly" --files codexsaver/router.py --workspace .
```

---

## Roadmap

- [x] MCP server
- [x] 规则路由
- [x] 上下文裁剪
- [x] DeepSeek 默认 worker 集成
- [x] 多 provider OpenAI-compatible worker 支持
- [x] 本地 API key 持久化
- [x] 可感知的交互返回
- [x] 端到端验证流程
- [ ] 成本感知动态路由
- [ ] 成本感知 provider 选择

---

## 如果它真的帮你省钱了

点个 Star。
