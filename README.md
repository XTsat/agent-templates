# agent-templates

> 一套**可直接被 AI 编码代理（agent）自动读取并遵循**的项目规范模板仓库。
> 每个模板目录都是**自包含**的：agent 只需读取对应模板的 `AGENTS.md`，即可一次性学会该类项目的全部约定（架构、代码规范、文档维护、提交流程）。

本仓库是**个人开源项目规范收敛中心**，用于消除各项目之间 AGENTS.md 的碎片化与不一致。

---

## 为什么需要这个仓库

有多类项目，各自有独立的 AGENTS.md 规范，但存在规范不一致：

| 项目类型 | 代表仓库 | 现状 |
|---|---|---|
| AstrBot 插件（Python） | `astrbot_plugin_*` | 部分有 AGENTS.md，但 CHANGELOG/README 格式不统一 |
| Web 应用（TypeScript/Next.js） | `LM-Speed-X` | 有完整 AGENTS.md（i18n 双语、changelog 三件套） |

本仓库把每类项目的规范**收敛成一份权威模板**，新项目直接引用对应模板即可，老项目逐步对齐。

---

## 模板选择指南

| 你的新项目是… | 使用模板 | 说明 |
|---|---|---|
| AstrBot 插件（Python，`astrbot_plugin_*`） | [`templates/astrbot-plugin/`](templates/astrbot-plugin/) | 覆盖 Star 插件、命令组、配置 schema、CHANGELOG/README 维护 |
| Web 应用（Next.js + TypeScript + Tailwind） | [`templates/nextjs-webapp/`](templates/nextjs-webapp/) | 覆盖 i18n 双语、shadcn/ui、changelog 三件套、README 双语 |
| 其它（通用 Python 库 / 脚本 / 文档站） | 暂未提供 | 可参考 `astrbot-plugin` 的通用部分（CHANGELOG/README 约定） |

---

## 如何让 agent 自动学习规范

### 方式一：新项目直接引用（推荐）

在新项目仓库里放一个 `AGENTS.md`，内容指向本模板：

```markdown
# AGENTS.md

> 本项目遵循 agent-templates 插件规范模板。
> 请先阅读并遵守：https://github.com/XTsat/agent-templates/blob/main/templates/astrbot-plugin/AGENTS.md
> 然后按 `scaffold/` 目录下的骨架文件初始化本项目。
```

agent 打开新项目时，会先读到这份 `AGENTS.md`，再跳转到模板仓库学习完整规范。

### 方式二：直接告诉 agent

在对话中直接指示：

> 去 https://github.com/XTsat/agent-templates 仓库，读取 `templates/astrbot-plugin/AGENTS.md`，并严格遵循其中的全部约定来开发本项目。

### 方式三：复制模板到项目

把 `templates/<类型>/` 下的 `AGENTS.md` 和 `scaffold/` 骨架文件复制到新项目根目录，作为项目自身的规范文件（适合需要离线/独立维护的项目）。

---

## 目录结构

```
agent-templates/
├── README.md                    # 本文件：总索引 + 模板选择指南
├── AGENTS.md                    # 本仓库自身的维护规范
└── templates/
    ├── astrbot-plugin/          # AstrBot 插件（Python）
    │   ├── AGENTS.md            #   完整规范（agent 必读）
    │   └── scaffold/            #   项目骨架文件
    │       ├── main.py.template
    │       ├── metadata.yaml.template
    │       ├── _conf_schema.json.template
    │       ├── CHANGELOG.md.template
    │       ├── README.md.template
    │       ├── README_en.md.template
    │       ├── requirements.txt.template
    │       └── i18n.example      # .astrbot-plugin/i18n 国际化示例
    └── nextjs-webapp/           # Web 应用（Next.js + TS + Tailwind）
        ├── AGENTS.md            #   完整规范（agent 必读）
        └── scaffold/            #   项目骨架文件
            ├── CHANGELOG.md.template
            ├── README.md.template
            └── i18n.example             # i18n 语言文件示例（zh-CN / en 成对）
├── skills/
│   ├── astrbot-plugin-hot-reloading/ # 热重载 AstrBot 插件（SKILL.md，仅用户主动提出时使用）
│   │   └── SKILL.md
│   └── astrbot-plugin-readme-cleaner/ # 精简 AstrBot 插件 README（SKILL.md，仅用户主动提出时使用）
│       └── SKILL.md
```

---

## Skills

| Skill | 用途 | 触发方式 |
|---|---|---|
| [`astrbot-plugin-hot-reloading`](skills/astrbot-plugin-hot-reloading/SKILL.md) | 热重载 AstrBot 插件（同步源码 + 插件级重载） | **仅用户主动提出时使用**（如「热重载插件」），不自动触发 |
| [`astrbot-plugin-readme-cleaner`](skills/astrbot-plugin-readme-cleaner/SKILL.md) | 精简 AstrBot 插件 README（删原理、留功能，双语同步） | **仅用户主动提出时使用**（如「精简文档」「README 太复杂」），不自动触发 |

`skills/` 下的 `SKILL.md` 与运行环境 `dsh-data/skills/` 保持同步。

---

## 维护本仓库

修改本仓库时，请遵循根目录的 [`AGENTS.md`](AGENTS.md)。