# AGENTS.md — Next.js Web 应用模板

> 本文件是任何 AI 编码代理（agent）进入 **Next.js Web 应用项目** 时的**必读**工作说明书。
> 它约定项目的架构、UI 规范、国际化、文档维护规则。任何对代码、配置、行为的改动，都必须同时遵守本文档的规则。
>
> 适用项目：基于 Next.js + React + TypeScript + Tailwind CSS 的 Web 应用。

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
├── README.md
└── README_zh.md                # 中文 README（可选，但有则必须同步）
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

- **所有页面的文本都必须双语言**：任何面向用户的文案（页面标题、按钮、提示、错误信息、占位符等）必须同时提供中文与英文，**禁止**只写单一语言或硬编码文案到组件里
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

- 注释规范见第 5 章「文档维护规范」的 [5.3 注释规范](#53-注释规范)

---

## 5. 文档维护规范（强制，不可省略）

### 5.1 CHANGELOG 维护

#### 流程

- 日常改动先记在 `## [Unreleased]` 段（顶部固定）。**发版时**再把内容移动到带版本号的新段。
- 多个不相关改动在同一工作周期内，各自独立记入 `[Unreleased]`，**不要**合并为一条。

#### 格式

统一使用 **扁平前缀式**：

```markdown
# Changelog

## [Unreleased]

- 新增：功能 A
- 修复：问题 B
- 变更：行为 C

## v0.3.0 (2026-07-06)

- 新增：功能 D
```

前缀分类：`新增` / `修复` / `变更` / `移除` / `性能`

> 若 changelog 是在页面中渲染的（如 `src/app/[locale]/changelog/page.tsx`），则 changelog 变更需要 **三处同步**：页面 `entries` 数组最上方新增记录 + `messages/zh-CN.json` 新增文案键 + `messages/en.json` 新增同键名英文条目。

#### 版本号联动

涉及功能新增/删除、行为变化时，**各处同步递增**：

| 文件 | 位置 |
|------|------|
| `package.json` | `version` 字段 |
| `CHANGELOG.md` | 发版时从 `[Unreleased]` 移入 `## vX.Y.Z (YYYY-MM-DD)` |
| i18n 文件 | 新增版本对应的文案 key |

#### 多会话并行开发

**⚠️ 更新 `CHANGELOG.md` 前必须先读取当前文件内容**，识别并保留其他会话已写入的既有条目（含 `[Unreleased]` 下未提交的功能），只追加自己的条目，**严禁整文件覆盖或删除他人记录**。

### 5.2 README 维护

#### 双语文档同步

如果项目维护多个语言的 README（如 `README.md` + `README_zh.md`），任何修改必须两文件同步：

- 章节结构必须保持一致，新增章节两个文件都要加
- 中文版使用自然中文，英文版使用地道英文，**禁止**逐字机翻、禁止留下半翻译的句子
- 修改时逐条 diff，确保无内容遗漏或错位

#### 何时必须更新 README

| 改动类型 | 必须更新的位置 |
|----------|--------------|
| 新增用户可见功能 | 功能列表 / 截图 |
| 修改快速开始步骤、部署方式、环境变量 | 快速开始章节 |
| 技术栈变更（框架版本升级、新增主要依赖） | 技术栈章节 |
| 项目定位/标语/链接变化 | 项目简介 |

**何时不需要更新 README：**
- 纯内部重构、样式调整、bug 修复（除非修复改变了用户可见行为）

### 5.3 注释规范

- **注释只写 non-obvious reason**：解释「为什么这么做」，而不是「做了什么」（代码本身应自文档化）
- **禁止残留 intermediate attempts**：不保留被注释掉的旧代码、TODO 但未完成的方案、调试输出

### 5.4 PR 描述规范

- **PR 描述只写最终行为**：描述最终完成了什么，而不是过程中尝试了什么
- 禁止提及：尝试过的方案、被否定的设计、从未合入的中间状态
- 只写 diff 里看不出来的取舍理由（如「选用方案A因为性能比B高20%」）

---

## 6. 提交与发布流程

### 6.1 提交规范

- **提交信息用中文短句式**，与现有历史风格一致（如 `模型真实性测试`、`bug fix`）
- **禁止**将未完成的功能、多轮迭代的中间状态、被废弃的方案写进提交信息
- 推荐顺序：完成功能代码 → 跑通验证 → 更新 CHANGELOG 与 README → 提交
- 文档更新与代码改动**在同一提交中完成**（不单独拆「补文档」提交）
- **推送（push）必须先经用户确认**：任何推送动作前必须向用户展示：提交 hash、提交信息、改动内容概要；等待用户明确同意后再推送

### 6.2 版本号规范

- 采用 **SemVer**：新功能 → `minor` 递增；bug 修复/小改进 → `patch` 递增
- `package.json` version 与 `CHANGELOG.md` 最新版本必须一致
- 发版时打 `git tag vX.Y.Z`，tag 推送同样需用户确认

### 6.3 构建验证

完成任何代码/文档修改后，运行验证：

```bash
pnpm build     # 构建 + 类型检查
```

确保无 TypeScript 错误、next-intl key 类型检查通过。

---

## 7. 最终检查清单（每次任务完成前）

- [ ] 样式：优先复用现有 ui 组件与相邻页面写法；若新建/更改组件或页面写法，已先询问用户
- [ ] i18n：所有页面文案均双语言，两个语言文件已同步新增 key，无硬编码文案
- [ ] 注释：只写 non-obvious reason，无残留中间状态、无被注释掉的旧代码
- [ ] CHANGELOG：`[Unreleased]` 已追加条目，保留了他人的既有记录
- [ ] README：涉及用户可见变更时已同步更新（多语言项目需同步两文件）
- [ ] 版本号：`package.json` version 与 `CHANGELOG` 最新版本一致
- [ ] 构建：`pnpm build` 通过
- [ ] 提交信息：中文短句式，只描述最终行为
- [ ] 推送：已展示改动概要并等待用户确认