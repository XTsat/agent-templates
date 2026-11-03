---
name: astrbot-plugin-hot-reloading-exec
description: '部署 AstrBot 插件并热重载：源码经容器内进程写入挂载目录（不写宿主路径、不用 rsync），宿主侧无写权限时也能用。仅在用户主动提出时使用。'
---

部署 AstrBot 插件并热重载（容器 exec 写入版）

> 与 `astrbot-plugin-hot-reloading-rsync` 只有写入通道不同，通过标准一致。宿主可写、且想要更严格的同步校验（多余文件立即失败、首次装载前置拦截）时，改用 `astrbot-plugin-hot-reloading-rsync`。

**使用约定：仅当用户主动提出（如「部署插件」「热重载插件」「更新线上代码」）时才使用本 skill，不得在普通改动流程中自动执行。**

## 为什么有这条路径

插件目录是**宿主挂载进容器**的（`docker inspect astrbot` 里 `Destination=/AstrBot/data` 那条的 `Source`）。正常工作区（`workspace-write`）下，宿主侧对该目录写入会被拦：即使以 root 执行 `touch` 也是 `Permission denied`（`rsync` 同样会失败）。而由容器内进程写入同一个挂载点不受该限制——本 skill 就只走这条路。

因此：

- **不写宿主路径**：不 `rsync`、不 `cp`、不 `touch` 部署目录。
- **不用 `docker cp`**：逐文件 `docker exec -i ... cat >` 写入，内容由 stdin 直传，可逐文件核对哈希。
- 写入内容 = `SRC` 里的真实文件，所以等价于同步，不存在「只改容器内副本」的漂移。

## 一步执行

一条 bash 调用跑完 前置检查 → 写入 → 哈希校验 → JWT → reload → 验证：

```bash
SRC=/abs/path/to/astrbot_plugin_xxx bash "<skill base>/run.sh"
```

`<skill base>` 是本 skill 目录的绝对路径（加载本 skill 时头部已给出）。退出码 `0` 即通过；非 `0` 时末行 `✗` 就是原因，按「失败处置」处理。`run.sh` 是全部可执行逻辑的唯一实现，不要另拼命令替代它。

| 环境变量 | 默认 | 作用 |
|---|---|---|
| `CONTAINER` | `astrbot` | 容器名 |
| `DASHBOARD` | `http://127.0.0.1:6185` | WebUI 地址（宿主侧可直连） |
| `DATA_IN_CONTAINER` | `/AstrBot/data` | 容器内数据目录 |
| `DST` | `$DATA_IN_CONTAINER/plugins/<目录名>` | 直接指定容器内目标目录 |
| `PLUGIN_ID` | `basename $SRC` | 插件目录名 |
| `SYNC_DELETE` | `0` | 置 `1` 才删容器内多余文件（默认只报告） |
| `ALLOW_FULL_RELOAD` | `0` | 首次装载（插件未注册）时必须显式置 `1` |
| `LOG_WINDOW` | `60s` | 验证阶段回看的日志窗口 |

单阶段重跑（排障用）：`bash run.sh sync|token|reload|verify`。

## 通过标准（四条硬校验）

1. reload 响应 `status == "ok"`。**HTTP 恒为 200**，失败也是 200，只看 `status` 字段。
2. `GET /api/v1/plugins` 里出现该插件（按 `root_dir_name` 或 `name` 匹配目录名），且 `version`、`display_name` 与 `metadata.yaml` 一致、`activated` 为真。这是主判据。
3. 日志窗口内出现 `Loading plugin <id> ...`；同批次只加载本插件 = 单插件重载，一并加载了几十个 = 全量重载（首次装载或进程重启）。
4. 无 `Failed to import plugin <id>`、无 `Plugin <id> did not terminate cleanly`。

## 同步实现（run.sh 的做法）

1. `docker exec <容器> mkdir -p <目标目录>`（首次安装时目录可能不存在）。
2. 本地枚举要同步的文件（排除 `.git/`、`.notes/`、`__pycache__/`、`*.pyc`、`.venv/`、`.mypy_cache/`、`.pytest_cache/`、`.DS_Store`），逐个：
   ```bash
   docker exec -i <容器> sh -c 'cat > "$1"' _ "<目标目录>/<相对路径>" < "<SRC>/<相对路径>"
   ```
   路径作为参数传入，避免引号与空格问题；`find` 产出的相对路径不含 `..`，写前会再校验一次。
3. 逐文件比对 `sha256`（本地 vs 容器内 `sha256sum`），不一致即失败。
4. 列出容器内存在但本地没有的文件：默认只打印；`SYNC_DELETE=1` 时逐个 `rm -f` 删除。**不做整目录镜像删除。**

## reload 语义（决定要警惕什么）

`POST /api/v1/plugins/<目录名>/reload` 分两种：

- **插件已在注册表**：只 terminate 并重载这一个插件，其它插件不受影响。日常路径。
- **插件名不在注册表**（首次装载，或目录刚同步进来）：走全量 reload——terminate 并重载**所有**插件，会打断其它插件正在跑的 LLM 请求、触发各插件 `terminate()` 里的清理（如删 `.part`）。此时日志里其它插件的 `CancelledError`、`Traceback`、请求取消**不是本插件的失败**。首次装载前征得用户同意或挑空闲时段，`run.sh` 会拦住并要求 `ALLOW_FULL_RELOAD=1`。

所以 `grep -iE "error|traceback"` 在全量 reload 窗口里必然命中噪声，只能参考、不作判据。

## JWT 与 401

- 在容器内用 `python3` 读 `cmd_config.json`（**必须 `encoding='utf-8-sig'`**，文件带 BOM）取 `dashboard.username` + `dashboard.jwt_secret`，HS256 签 `{"username","exp"}`，落 `/tmp/<插件目录名>_token.txt`（chmod 600）；每轮先 `GET /api/v1/plugins` 探测：200 复用，401 才重签。
- 路由前缀必须是 `/api/v1`（写 `/api` 返回 405）。payload 不需要 scopes。

## 失败处置

| 现象 | 处置 |
|---|---|
| `docker ps` 里没有容器 | 容器名写错或未启动；用 `CONTAINER=` 指定，不要 `docker restart` |
| `cat >` 写入报错 / 容器内 `Permission denied` | 容器内目标目录属主异常；用 `docker exec <容器> ls -ld <目标目录>` 核实，必要时 `docker exec <容器> mkdir -p` 重建目录 |
| 哈希校验不一致 | 说明写入被截断（大文件、管道超时）；重跑 `sync`，仍失败则 `docker exec <容器> wc -c <文件>` 与本地比对定位 |
| 容器内有多余文件 | 报告里列出；确认是残留旧文件后再 `SYNC_DELETE=1 bash run.sh sync` |
| reload 返回 `status=error` | `message` 只有泛化文案，真实错误在 `docker logs --since 60s <容器>` 的 `Traceback` 里找本插件 import 报错 |
| 日志无 `Loading plugin <id>` | 最常见是距上次 reload 已超过 `LOG_WINDOW`（先 `bash run.sh reload`，或 `LOG_WINDOW=10m bash run.sh verify`）；其次才是目录名与 `metadata.yaml` 的 `name` 不一致 |
| 插件在列表但 `activated=false` | 插件在 `inactivated_plugins` 里，需在面板启用 |

## 背景事实（勿重新论证）

- 容器装了 `watchfiles` 但只有 `ASTRBOT_RELOAD=1` 时 star_manager 才启动文件监听；未设置时改动不会自动生效，必须显式调 reload API。`watchdog` 是事件循环诊断日志，与进程重启无关。
- 写入走容器进程，因此宿主侧的 `rsync`/`cp` 失败**不代表**部署不可行；不要再退回 rsync 反复试，也不要为此向用户索要宿主写权限。
- 改 Python 逻辑时，若仓库有离线测试入口（`tests_offline.py`、`tests/*.py`、`pytest`、`make test` 任一），先在本地跑最接近的那个，再部署。

**禁止**：`docker restart`、kill 进程、改 `docker-compose.yml` / `cmd_config.json` 等用户配置、`docker cp` 整目录覆盖、整目录镜像删除。
