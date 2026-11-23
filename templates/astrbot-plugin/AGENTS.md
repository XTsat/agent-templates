# AGENTS.md — AstrBot 插件模板

> 本文件是任何 AI 编码代理（agent）进入 **AstrBot 插件项目** 时的**必读**工作说明书。
> 它约定插件的架构、代码规范、文档维护规则。任何对代码、配置、行为的改动，都必须同时遵守本文档的规则。
>
> 适用项目：`astrbot_plugin_*` 命名的 AstrBot 插件（Python）。
>
> **模板版本**：v0.2.0（2026-11-23） —— 本行标记本文件对应的 `astrbot-plugin` 模板版本。回填项目内容时**不要改动本行**；只有从上游合并到新版本时才把它更新为合并到的版本。
> **来源**：本文件是 [agent-templates](https://github.com/XTsat/agent-templates) 的 `templates/astrbot-plugin/AGENTS.md` 副本，最新版见该仓库 `main` 分支。
> 用户说「更新 AGENTS」时按此流程：① 打开来源仓库该模板的 `AGENTS.md`，比对头部「模板版本」与本地是否一致——一致说明已是最新，直接结束，不必拉取逐节比对 → ② 不一致才拉取来源模板最新版 → ③ 与本地逐节比对（含 `docs/` 下各细则页）→ ④ 合并（保留本项目已回填的插件名、命令前缀、目录结构与项目特有约定）→ ⑤ 展示 diff 与改动清单，等用户确认后再落盘，并把头部「模板版本」同步改为合并到的版本。**禁止整文件覆盖**。

---

## 1. 项目概览

**AstrBot 插件**是基于 `astrbot.api.star` 框架的 Python 插件，以 `Star` 子类为核心，通过装饰器注册指令组、事件监听器、过滤器，在 AstrBot 运行时中加载。

核心文件清单：

| 文件 | 必选 | 职责 |
|------|------|------|
| `main.py` | ✅ | 插件主体，全部后端逻辑 |
| `metadata.yaml` | ✅ | 插件元数据（必填 `name`/`desc`/`version`/`author`；推荐 `display_name`/`repo`；可选 `support_platforms`/`tags`（**全量、单概念**关键词，README 头部只挑重点）、`short_desc`，`astrbot_version` 只在能明确最低版本时才填） |
| `_conf_schema.json` | ✅ | WebUI 配置 Schema（扁平 `{key: {type, description, default, ...}}`，定义所有可配置项） |
| `README.md` | ✅ | 中文文档（功能说明、命令表、配置说明） |
| `CHANGELOG.md` | ✅ | 变更日志 |
| `LICENSE` | 可选 | 许可证——**仅在用户明确指定许可证时创建**，禁止自行套用默认许可证 |
| `logo.png` | ✅ | 插件图标（1:1，推荐 256×256） |
| `requirements.txt` | 可选 | 运行时依赖 |
| `.gitignore` | 可选 | Git 忽略规则 |
| `.astrbot-plugin/` | 可选 | 插件 i18n 目录（`i18n/<locale>.json`：`metadata` 插件名/描述、`config` 配置项文案、`views` 视图标题） |
| `views/` | 可选 | WebUI 可视化视图目录（原生 JS + bridge；AstrBot 4.x 首选，`pages/` 只是兼容别名） |

> **许可证按需，且不进 README**：用户没明确说要「用哪个许可证」时，**不创建 `LICENSE` 文件、不在 metadata 或代码里标注许可证**，禁止默认套用 AGPL-3.0、MIT、Apache-2.0 等常见许可证；只有用户明确指定某个许可证时才新建 `LICENSE`。**README 一律不放许可证章节**——即使项目已有 `LICENSE` 文件，也不在 README 里写许可证小节。

---

## 2. 目录结构与架构

### 2.1 项目结构

插件以目录形式存放于 AstrBot 的 `data/plugins/` 目录下，目录名即插件名（AstrBot 4.x；`addons/` 是 3.x 旧路径，已废弃）。

```
astrbot_plugin_xxx/
├── main.py                 # 全部后端逻辑（单文件优先，复杂项目可拆分为多文件）
├── metadata.yaml           # 插件元数据
├── _conf_schema.json       # 插件配置 Schema
├── CHANGELOG.md            # 变更日志
├── README.md               # 中文文档
├── LICENSE                 # 许可证（可选，用户明确指定时才创建）
├── logo.png                # 插件图标
├── requirements.txt        # 运行时依赖
├── .gitignore
├── .astrbot-plugin/i18n/   # 可选：插件 i18n（zh-CN.json / en-US.json：metadata / config / views）
└── views/<view>/           # 可选：WebUI 可视化视图（原生 JS + bridge，零构建）
    ├── index.html          # 唯一入口（AstrBot 只认这个文件名）
    ├── app.js              # 外部 type="module" 脚本（不用内联脚本）
    ├── style.css           # 主题变量 + 组件样式
    └── assets/             # 相对路径引用的静态资源
```

### 2.2 架构倾向

AstrBot 插件有两种主流架构风格，**新建项目时二选一，并在整个生命周期内保持一致**：

| 风格 | 适用场景 | 参考项目 |
|---|---|---|
| **单文件** | 逻辑简单（< 1500 行） | `astrbot_plugin_msg_forward_cc`、`astrbot_plugin_model_status` |
| **分层多文件** | 逻辑复杂，需模块化 | `astrbot_plugin_help_panel_typst`（main.py → core → utils → domain） |

**单文件风格**：
- 所有逻辑在 `main.py` 一个文件中，通过注释分隔条组织：`# 内部工具方法 → # Web API → # 数据持久化 → # 执行与调度 → # 聊天命令 → # 生命周期`
- 新增方法按职责放入对应分区

**分层多文件风格**：
- 依赖方向严格单向：`main.py → core → utils / domain`；`utils → domain`；`domain` 不依赖任何人
- `domain/`：数据定义层（constants、config、schemas），最底层，无内部依赖
- `utils/`：通用工具层（font、image、hash 等），禁止 import core/ 或 main
- `core/`：核心业务层（analyzer、renderer、worker），纯 Python 逻辑
- 新增常量 → 放 `domain/constants.py`，禁止散落硬编码
- 新增配置项 → 改 `domain/config.py` 的 dataclass 字段 + 兜底逻辑 + `_conf_schema.json`

---

## 3. 技术栈与依赖

- **Python 3.10+**（AstrBot 4.x 最低要求）
- **AstrBot API**：`astrbot.api.star`（Context, Star, register, StarTools）、`astrbot.api.event`（filter, AstrMessageEvent）、`astrbot.api`（logger, AstrBotConfig）
- **依赖管理**：`requirements.txt` 中声明，复杂依赖优先 **惰性 import**（在方法内 import，避免启动时强制加载）
- **禁止引入**：不引入与原功能无关的依赖；非必要不新增 `requirements.txt` 声明
- **日志库**：唯一来源是 `from astrbot.api import logger`（AstrBot 官方插件文档要求「使用 `astrbot.api` 的 logger，而不是 `logging` 模块」）。**禁止** `import logging` / `logging.getLogger(...)` / `logging.basicConfig(...)`，也禁止 `loguru` 等第三方日志库、禁止把日志库写进 `requirements.txt`。理由与分层项目的写法见 4.5
- AstrBot 运行时已自带的依赖（如 `aiohttp`、`certifi`）可在惰性 import 中引用，import 失败时优雅降级

---

## 4. 核心代码规范

### 4.1 插件骨架

最小骨架见 `scaffold/main.py.template`（复制即用）。要点：

- 入口是 `Star` 子类，用 `@register(PLUGIN_NAME, 作者, 描述, 版本)` 注册；`__init__` 收 `Context` 与 `AstrBotConfig`。
- 命令用 `@filter.command_group` / `@xxx_group.command` 注册；管理类命令加 `@filter.permission_type(filter.PermissionType.ADMIN)`。
- `@register` 的版本参数**不是版本源**——插件版本以 `metadata.yaml` 的 `version` 为准（见 [`docs/changelog.md`](docs/changelog.md)）。

### 4.2 命名约定

| 元素 | 约定 |
|------|------|
| 模块级常量 | `UPPER_SNAKE`（`DEFAULT_TIMEOUT`、`MAX_CONCURRENCY`） |
| 私有方法 | `_` 前缀 + `snake_case`（`_rebuild_media_component`） |
| Web API 方法 | `api_` 前缀 |
| 命令方法 | `cmd_` 前缀 |
| 类名 | `PascalCase`（`MsgForward`、`ModelStatusPlugin`） |
| 文件名 | `snake_case`（`main.py`、`_conf_schema.json`） |

### 4.3 类型与语法

- Python 3.10+ 现代联合类型写法（`dict \| None`、`list[dict]`、`tuple[str, str]`）
- 函数签名**必须完整类型注解**（参数 + 返回类型）；用 `yield` 返回结果的命令/事件处理方法标注为 `AsyncGenerator[MessageEventResult, None]`
- 禁止 `Any` 作为类型注解（除非调用方签名强制要求）
- 禁止 `# type: ignore`（无理由的类型作弊）

### 4.4 注释规范

- 注释规范见第 7 章「文档维护规范」的 [7.3 注释规范](#73-注释规范)

### 4.5 日志

- **日志来源唯一**：`from astrbot.api import logger`。**禁止** `import logging` / `logging.getLogger(...)`（含「SDK 缺失时退回标准库」这类降级分支），**禁止** `loguru` 等第三方日志库。它按调用位置路由到 `astrbot.plugin.<插件名>`，自建 logger 名字对不上，插件详情页的独立日志等级与按插件筛选都会失效。
- **分层项目里要脱离 AstrBot 单测的层**：不要退回标准库 logging；留一个可注入出口（如 `core/logger.py` 的 `get_logger()`/`set_logger()`），由 `main.py` 在 `initialize()` 注入 `astrbot.api.logger`，未注入时写 stderr 兜底。用一条 AST 测试守住「全仓无 `import logging`/`loguru`」。
- 统一 `logger.info/warning/error`，**必须带 `[{PLUGIN_NAME}]` 前缀**
- 错误信息带 emoji 前缀（如 `❌`、`⚠️`）
- 精确捕获异常类型（`asyncio.TimeoutError`），禁止空 `except: pass`（除非注释说明理由）
- 异常分类记录：ValueError = 非法参数，OSError = 文件/IO 错误，各自记录，单规则失败不影响其它规则

### 4.6 错误处理与防御性编程

- 面对不规范的输入必须优雅 fallback（参考 `_get_safe_plugin_info` 风格）
- 外部 IO 必须 try/except 并记录日志，**不允许静默吞异常**
- 配置值防御式校验：`max(1, int(...))`、`(TypeError, ValueError)` → 默认值
- 降级链路清晰：首选方案 → 兜底方案 → 占位文本

### 4.7 并发

- 异步方法使用 `async/await`，**禁止阻塞事件循环**
- 并发限制用 `asyncio.Semaphore(MAX_CONCURRENCY)` + `asyncio.as_completed`，`finally` 中取消未完成任务
- 渲染/计算重活必须走 `asyncio.to_thread` 或子进程
- `ProcessPoolExecutor` 即用即销（`with ProcessPoolExecutor(...)`），子进程结束强制释放内存

### 4.8 回复消息

- 统一 `yield event.plain_result(...)`
- 用户可读输出用中文 + emoji 图标风格

### 4.9 权限控制

- 管理类命令加 `@filter.permission_type(filter.PermissionType.ADMIN)`

### 4.10 插件可视化视图（views/）

> 本模板有 `views/` 时按 [`docs/views.md`](docs/views.md) 执行：目录结构、bridge 通信、脚本加载方式、错误兜底与验收点都在那里。**改或新增 `views/` 前先读它**。


## 5. 配置与数据文件

### 5.1 配置 Schema（_conf_schema.json）

> 字段格式、类型取值、默认值与 WebUI 呈现规则见 [`docs/config.md`](docs/config.md)。**新增或修改配置项前先读它**，并确认三处同步：`_conf_schema.json` + 代码读取 + README 配置表。


### 5.2 配置读取模式

```python
DEFAULT_SETTINGS = {
    "timeout": 30,
    "max_retries": 3,
}

# 合并：只保留已知字段，丢弃未知字段
settings = {k: self.config.get(k, v) for k, v in DEFAULT_SETTINGS.items()}
```

---

## 6. 指令注册与命令清单

### 6.1 指令注册模式

```python
@filter.command_group("pfx")           # 指令前缀 /pfx
def pfx_group(self) -> None:
    pass

@pfx_group.command("sub")              # 子命令 /pfx sub
@filter.permission_type(filter.PermissionType.ADMIN)
async def cmd_sub(
    self, event: AstrMessageEvent
) -> AsyncGenerator[MessageEventResult, None]:
    yield event.plain_result("结果")
```

### 6.2 事件监听

```python
@filter.event_message_type(filter.EventMessageType.ALL)
async def on_message(
    self, event: AstrMessageEvent
) -> AsyncGenerator[MessageEventResult, None]:
    # 处理全部消息（若不 yield，则标注 -> None）
    pass
```

### 6.3 命令表格式（README 中呈现）

| 命令 | 权限 | 说明 |
|------|------|------|
| `/pfx help` | 全部 | 显示帮助 |
| `/pfx sub` | 管理员 | 子功能说明 |
| `/pfx sub <参数>` | 管理员 | 带参说明 |

---

## 7. 文档维护规范（强制，不可省略）

任何改动在合并前，必须同步维护 `README.md` 与 `CHANGELOG.md`。**未同步文档 = 任务未完成。**

细则按主题拆开，动手前读对应文件：

| 你要做的事 | 先读 |
|---|---|
| 写 / 改 `CHANGELOG.md`（流程、写作视角、版本号时机） | [`docs/changelog.md`](docs/changelog.md) |
| CHANGELOG 分组格式、加粗、破坏性标记、老版本折叠 | [`docs/changelog-format.md`](docs/changelog-format.md) |
| 写 / 改 `README.md`（写作视角、何时必须更新、双语） | [`docs/readme.md`](docs/readme.md) |
| README 头部表头与四大板块结构（含示例） | [`docs/readme-structure.md`](docs/readme-structure.md) |
| 写代码注释、写 PR 描述 | [`docs/notes.md`](docs/notes.md) |

**多会话并行**：改 `CHANGELOG.md` / `README.md` 这类共享文件前必须先读取当前内容，只做定位式追加，**严禁整文件覆盖**（会盖掉他人条目）。触发条件与完整协议见 [`docs/changelog.md`](docs/changelog.md) 的「多会话并行开发」节。

---

## 8. 提交与发布流程（要点，细则见 [`docs/commit.md`](docs/commit.md)）

- **提交前必须先向用户展示**：待提交文件清单 + `git diff --stat` + **2–3 个候选提交标题**（注明侧重并标出推荐项），用户选定后才 commit。
- **只有用户明确要求时才 commit / push**；授权一次性，不延续（确认 commit ≠ 授权 push）。
- **提交信息**：Conventional Commits，`<type>(<scope>): <subject>`；subject 中文动宾短句、≤ 28 汉字、只讲一件事；正文可选，只写 diff 看不出来的取舍。
- **版本号只在准备发布时递增**：日常提交不碰 `metadata.yaml` 的 `version`；一次发版汇总多个提交后才确认版本号，并把 README 徽章、i18n 等辅助位置同步到同一新号。
- **提交前必须跑**：`python -c "import main"` 无语法错误（或 `ruff check` 通过）；有测试则测试通过。

---

## 9. 最终检查清单（每次任务完成前）

- [ ] 架构：所选风格（单文件 / 分层多文件）与既有代码一致
- [ ] 注释：只写 non-obvious reason，无残留中间状态、无被注释掉的旧代码
- [ ] 日志：来源只有 `astrbot.api` 的 logger（无 `import logging` / `logging.getLogger` / 第三方日志库），`[{PLUGIN_NAME}]` 前缀，异常分类记录，无空 catch
- [ ] CHANGELOG：`[Unreleased]` 已同步（新增则追加、同一变化则合并、发版前被撤销则删除对应条目，不残留相对上一版不成立的内容），**只写相对上一版（上一次发布）的变化**、同一变化已合并为一条（无重复条目），条目面向用户（无内部实现细节、无复杂形容即可看懂），保留了他人的既有记录
- [ ] CHANGELOG 折叠：`[Unreleased]` 与最近 3 个版本段展开，第 4 个起每个版本段各自一个 `<details>`，首个折叠前有 `---` 分隔；带 `⚠️ 破坏性变更`（或含 `### 移除`）的版本永不折叠（细则见 [`docs/changelog-format.md`](docs/changelog-format.md)）
- [ ] README：涉及用户可见变更时已同步更新，且面向用户书写（无实现原理与内部细节）
- [ ] README 配置板块：> 4 项时按类别分组，单类 ≥ 4 项用 `<details>` 折叠且 summary 自解释，首次必填项没被藏进折叠
- [ ] README 头部：首行是 `<img src="logo.png" alt="插件名" width="160" />`，中英两版都有，`alt` 已填，头部元素间无空行
- [ ] 标签：`metadata.yaml` 的 `tags` 是全量关键词且一个标签一个概念；中英 README 头部只列重点功能（可为 tags 变体，不虚构能力）
- [ ] README 安装：未写分步「快速开始/安装」；版本与协议端仅在确有明确限制时才写，最低版本写进 `metadata.yaml` 的 `astrbot_version`
- [ ] 许可证：未自行创建 `LICENSE`、README 中无许可证小节/徽章/许可证名（用户明确指定许可证时才建 `LICENSE`，仍不写进 README）
- [ ] 版本号：日常不递增；仅发版任务改 `metadata.yaml` 的 `version`（与 CHANGELOG 新版本段、tag 一致），并同步 `@register`、README 徽章、i18n
- [ ] 配置：新增配置项已按扁平 `{key: {...}}` 格式写进 `_conf_schema.json`，并在代码中同步读写
- [ ] 视图（改动或新增 `views/` 时）：通信只走 bridge、脚本外部 `type="module"`、bridge 有兜底报错、未用 `localStorage`/`target="_blank"`、上传限了大小、视图标题已进 i18n（细则见 [`docs/views.md`](docs/views.md)）
- [ ] 提交信息：Conventional Commits + 8.1 内容标准——type 按「使用者得到什么」选、scope 一个模块词或无、subject ≤ 28 汉字只讲一件事、正文只在 diff 看不出来时才写、footer 按需补、空话与过程描述已删
- [ ] 提交粒度：一个提交只做一件事，文档与代码同提交，无半成品 / 中间态 / 被废弃方案
- [ ] 提交前展示：已给出待提交文件清单、`git diff --stat`、2–3 个候选提交标题（逐条注明侧重并标出推荐项），并取得用户对本次改动的明确确认（一次性授权，未沿用上一轮）
- [ ] 本地测试：`python -c "import main"` 无语法错误（或 ruff 格式通过）
