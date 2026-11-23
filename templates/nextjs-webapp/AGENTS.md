# AGENTS.md — Next.js Web 应用模板

> 本文件是任何 AI 编码代理（agent）进入 **Next.js Web 应用项目** 时的**必读**工作说明书。
> 它约定项目的架构、UI 规范、国际化、文档维护规则。任何对代码、配置、行为的改动，都必须同时遵守本文档的规则。
>
> 适用项目：基于 Next.js + React + TypeScript + Tailwind CSS 的 Web 应用。
>
> **模板版本**：v0.2.2（2026-11-24） —— 本行标记本文件对应的 `nextjs-webapp` 模板版本。回填项目内容时**不要改动本行**；只有从上游合并到新版本时才把它更新为合并到的版本。
> **来源**：本文件是 [agent-templates](https://github.com/XTsat/agent-templates) 的 `templates/nextjs-webapp/AGENTS.md` 副本，最新版见该仓库 `main` 分支。
> 用户说「更新 AGENTS」时按此流程：① 打开来源仓库该模板的 `AGENTS.md`，比对头部「模板版本」与本地是否一致——一致说明已是最新，直接结束，不必拉取逐节比对 → ② 不一致才拉取来源模板最新版 → ③ 与本地逐节比对（含 `docs/` 下各细则页）→ ④ 合并（保留本项目已回填的项目名、目录结构、环境变量与项目特有约定）→ ⑤ 展示 diff 与改动清单，等用户确认后再落盘，并把头部「模板版本」同步改为合并到的版本。**禁止整文件覆盖**。

---

## 1. 项目概览

**Next.js Web 应用** — 基于 Next.js 框架的全栈 Web 应用，支持 React 服务端组件与客户端组件、国际化、API 路由。核心技术栈：

- **框架**：Next.js（App Router）
- **语言**：TypeScript 严格模式
- **样式**：Tailwind CSS（v4，`@import "tailwindcss"`）+ `cn()` 工具函数
- **组件库**：shadcn/ui 风格（Radix UI + CVA + `cn()`）
- **国际化**：next-intl（或类似方案）
- **包管理**：pnpm

---

## 2. 目录结构与架构

### 2.1 标准目录结构

```
project-root/
├── src/
│   ├── app/
│   │   ├── [locale]/           # 国际化路由
│   │   │   ├── page.tsx
│   │   │   ├── layout.tsx
│   │   │   └── ...
│   │   ├── globals.css         # Tailwind 主题变量（@theme）
│   │   └── ...
│   ├── components/
│   │   ├── ui/                 # 基础 UI 组件（shadcn/ui 风格）
│   │   │   ├── Button.tsx
│   │   │   ├── Card.tsx
│   │   │   └── ...
│   │   └── ...                 # 业务组件
│   ├── lib/
│   │   ├── utils.ts            # cn() 工具函数
│   │   └── ...
│   └── ...
├── messages/                   # 国际化语言文件
│   ├── en.json
│   └── zh-CN.json
├── public/
│   └── ...
├── package.json
├── tsconfig.json
├── next.config.ts
├── tailwind.config.ts          # 仅 Tailwind v3 兼容；v4 用 globals.css 的 @theme
├── CHANGELOG.md
├── README.md                   # 中文 README（权威版本）
└── README_en.md                # 英文 README（可选，有则必须与中文版同步）
```

### 2.2 组件边界

| 类型 | 约定 |
|------|------|
| 服务端组件 | 默认，纯展示组件不加 `'use client'` |
| 客户端组件 | 交互组件以 `'use client'` 开头，包含状态/事件/副作用 |
| 页面组件 | 默认导出 `export default function Page()` |
| 其它组件 | 命名导出 `export const X = ...` |

---

## 3. 技术栈与依赖

- **Next.js**：最新稳定版（App Router）
- **React**：19+
- **TypeScript**：严格模式，**禁止** `any`、`@ts-ignore`、`@ts-expect-error`
- **Tailwind CSS**：v4（`@import "tailwindcss"`），**禁止** v3 的 `tailwind.config` 扩展写法
- **组件库**：shadcn/ui 风格（Radix Primitive + `forwardRef` + CVA `variant`/`size` 变体）
- **国际化**：next-intl（`useTranslations('Namespace')` 或 `getTranslations`）
- **动效**：只使用 `tailwindcss-animate` / CSS transition，不引入新的动效库
- **包管理**：pnpm
- **类名合并**：统一使用 `@/lib/utils` 中的 `cn()`，禁止字符串拼接

---

## 4. 核心代码规范

### 4.1 样式统一规范

#### 组件使用规则

- **尽量复用** `src/components/ui/` 中的现有组件（Button / Card / Input / Badge / Dialog / Select 等）与既有页面写法，保持整体风格一致
- 若决定**新建基础组件或更改现有组件/页面写法**，必须先向用户询问确认，再动手实现
- 新 UI 组件建在 `src/components/ui/` 下时，风格对齐现有 shadcn/ui 模式（Radix Primitive + `forwardRef` + CVA `variant`/`size` 变体）

#### Tailwind 与样式写法

- 类名合并一律使用 `@/lib/utils` 中的 `cn()`，禁止字符串拼接
- 主题色、圆角、字体全部取自 `src/app/globals.css` 中的 `@theme` 变量（`--color-primary`、`--radius` 等），**禁止**硬编码十六进制颜色或魔数圆角
- 颜色语义化：`primary` / `muted` / `destructive` / `border` / `card` 等，按 Tailwind 语义类（`bg-primary`、`text-muted-foreground`、`border-border`）使用

### 4.2 国际化（i18n）规则

- **先判断项目是否已做国际化，再决定本规则是否执行**：动手前先检查项目现状——是否存在 `messages/`（或 `locales/`、`i18n/`）语言文件、是否有 `src/app/[locale]/` 这类 locale 路由、`package.json` 里是否有 `next-intl`（或同类库）依赖与对应配置。**项目本身已做多语言** → 下述各条全部强制执行；**项目本身是单语言**（上述痕迹一个都没有）→ 本规则不适用，**不要**为此引入 i18n 依赖、不要新建语言文件、不要加 locale 路由，文案按项目现有语言写即可。判断不清时先问用户，不得自行改造项目语言架构。
- **所有页面的文本都必须双语言**（仅对已做国际化的项目）：任何面向用户的文案（页面标题、按钮、提示、错误信息、占位符等）必须同时提供中文与英文，**禁止**只写单一语言或硬编码文案到组件里
- 文案统一走 next-intl：`useTranslations('Namespace')` 或 `getTranslations`，禁止把中英文写死在组件中
- 新增文案必须**同步**修改两个语言文件，键名保持一致（camelCase），两个文件缺一不可
- 页面/区块文案按命名空间组织（如 `HomePage`、`RankPage`），新功能追加到对应命名空间，不新建碎片命名空间
- 修改语言文件后必须用 `tsc --noEmit` / `pnpm build` 校验 key 类型

### 4.3 代码风格

- TypeScript 严格模式，**禁止** `any`、`@ts-ignore`、`@ts-expect-error`
- 函数组件 + Hook，统一单引号、行尾无分号（与现有代码一致），格式化以 ESLint/Prettier 配置为准
- 文件组织遵循现有目录：页面 `src/app/[locale]/...`、业务组件 `src/components/`、工具 `src/lib/`
- **修改涉及多文件时，必须检查并遵循相邻相似文件的既有写法，保持整体一致性**

### 4.4 注释规范

- **注释只写 non-obvious reason**：解释「为什么这么做」，而不是「做了什么」（代码本身应自文档化）
- **禁止残留 intermediate attempts**：不保留被注释掉的旧代码、TODO 但未完成的方案、调试输出

---

## 5. 文档维护规范（强制，不可省略）

任何改动在合并前必须同步维护 `README.md` 与 `CHANGELOG.md`。**未同步文档 = 任务未完成。**

| 你要做的事 | 先读 |
|---|---|
| 写 / 改 `CHANGELOG.md`（流程、格式、写作视角、版本号联动） | [`docs/changelog.md`](docs/changelog.md) |
| 写 / 改 `README.md`（板块结构、写作视角、双语） | [`docs/readme.md`](docs/readme.md) |
| 写代码注释 | §4.4 注释规范（见下） |
| 写 PR 描述 | [`docs/notes.md`](docs/notes.md) |

**多会话并行**：改 `CHANGELOG.md` / `README.md` 前必须先读当前内容，只做定位式追加，**严禁整文件覆盖**（会盖掉他人条目）。

---

## 6. 提交与发布流程（要点，细则见 [`docs/commit.md`](docs/commit.md)）

- **提交前必须先向用户展示**：待提交文件清单 + `git diff --stat` + **2–3 个候选提交标题**（注明侧重并标出推荐项），用户选定后才 commit。
- **只有用户明确要求时才 commit**；**禁止自动推送**：commit 后停手汇报，不得顺势 push；推送须复述用户本轮原话、展示待推提交（hash + 标题）与目标分支/tag，取得本轮确认后才推；授权一次性，不延续（确认 commit ≠ 授权 push）。
- **提交信息**：Conventional Commits，`<type>(<scope>): <subject>`；subject 中文动宾短句、≤ 28 汉字、只讲一件事；正文可选，只写 diff 看不出来的取舍。
- **版本号只在准备发布时递增**：日常提交不碰 `package.json` 的 `version`；一次发版汇总多个提交后才确认版本号，并把 README 徽章、i18n 等辅助位置同步到同一新号。
- **提交前必须跑**：`pnpm build`（或 `pnpm lint`）通过。

---

## 7. 最终检查清单

### 7.1 每次改动完成时（写完代码就查）

- [ ] 样式：优先复用现有 ui 组件与相邻页面写法；新建/更改组件或页面写法前已询问用户
- [ ] i18n：项目做多语言时，页面文案双语言、两个语言文件同步新增 key、无硬编码文案；单语言时未引入 i18n 依赖、未新建语言文件或 locale 路由
- [ ] 注释：只写 non-obvious reason，无残留中间状态、无被注释掉的旧代码
- [ ] README：涉及用户可见变更时已同步（多语言项目需同步两文件），且面向用户书写
- [ ] 构建：`pnpm build` 通过

### 7.2 提交前（只在 commit 前查一次，不提交就不用过）

- [ ] CHANGELOG：`[Unreleased]` 已同步且**只写相对上一版的变化**，同一变化合并为一条，条目面向用户，保留他人既有记录
- [ ] 提交信息：Conventional Commits + §6 内容标准——type 按「用户得到什么」选、scope 一个页面/模块词或无、subject ≤ 28 汉字只讲一件事、正文只在 diff 看不出来时才写、空话已删
- [ ] 提交粒度：一个提交只做一件事，文档与代码同提交，i18n 两语言文件的同一 key 同提交，无半成品 / 中间态
- [ ] 提交前展示：已给出文件清单、`git diff --stat`、2–3 个候选标题，并取得本轮明确确认
- [ ] 推送：未在本轮取得 push 授权不得推送，commit 后即停手汇报

### 7.3 按需检查（只在改动涉及该区域时）

- [ ] 发版 → 只改 `package.json` 的 `version`（与 CHANGELOG 版本段、tag 一致），并同步 README 徽章、正文版本字样、`messages/*.json` 版本文案
- [ ] 新建项目 → 未自行创建 `LICENSE`、README 无许可证章节
