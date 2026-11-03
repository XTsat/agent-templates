---
name: astrbot-plugin-hot-reloading-rsync
description: '热重载 AstrBot 插件：用 rsync 直接写宿主挂载目录（需要宿主侧写权限，沙箱环境需一次授权）。仅在用户主动提出时使用。'
---

部署 AstrBot 插件并热重载（rsync 写宿主挂载目录版）

> 与 `astrbot-plugin-hot-reloading-exec` 只有写入通道不同，通过标准一致。宿主目录不可写（例如 DSH 沙箱内、root 也 `Permission denied`）时，改用 `astrbot-plugin-hot-reloading-exec`。

**使用约定：仅当用户主动提出（如「热重载插件」「热更新 AstrBot 插件」）时才使用本 skill，不得在普通改动流程中自动执行。**

## 一步执行（默认路径）

一条 bash 调用跑完 前置检查 → 同步 → diff 校验 → JWT → reload → 验证，因此只需一次授权：

```bash
SRC=/abs/path/to/astrbot_plugin_xxx bash "<skill base>/run.sh"
```

`<skill base>` 是本 skill 目录的绝对路径（加载本 skill 时头部已给出）。退出码 `0` 即通过；非 `0` 时末行 `✗` 就是原因，按「失败处置」处理。`run.sh` 是本 skill 全部可执行逻辑的唯一实现，不要另拼一套命令替代它。

| 环境变量 | 默认 | 作用 |
|---|---|---|
| `CONTAINER` | `astrbot` | 容器名 |
| `DASHBOARD` | `http://127.0.0.1:6185` | WebUI 地址 |
| `DATA_IN_CONTAINER` | `/AstrBot/data` | 容器内数据目录，用于反查宿主挂载 |
| `PLUGIN_ID` | `basename $SRC` | 插件目录名 |
| `SYNC_DELETE` | `0` | 置 `1` 才给 rsync 加 `--delete` |
| `ALLOW_FULL_RELOAD` | `0` | 首次装载（插件未注册）时必须显式置 `1` |
| `LOG_WINDOW` | `60s` | 验证阶段回看的日志窗口 |

单阶段重跑（排障用，同为一次授权）：`bash run.sh sync|token|reload|verify`。

## 通过标准（四条硬校验）

1. reload 响应 `status == "ok"`。**HTTP 恒为 200**，失败也是 200，只看 `status` 字段。
2. `GET /api/v1/plugins` 里出现该插件（按 `root_dir_name` 或 `name` 匹配目录名），且 `version`、`display_name` 与 `metadata.yaml` 一致、`activated` 为真。这是主判据，比 grep 日志确定。
3. 日志窗口内出现 `Loading plugin <id> ...`；同批次（前后 20s）只加载本插件 = 单插件重载，一并加载了几十个 = 全量重载（首次装载或进程重启）。
4. 无 `Failed to import plugin <id>`、无 `Plugin <id> did not terminate cleanly`。

## reload 语义（决定要警惕什么）

`POST /api/v1/plugins/<目录名>/reload` 分两种：

- **插件已在注册表**：只 terminate 并重载这一个插件，其它插件不受影响。日常路径。
- **插件名不在注册表**（首次装载，或目录刚同步进来）：走全量 reload——terminate 并重载**所有**插件，会打断其它插件正在跑的 LLM 请求、触发各插件 `terminate()` 里的清理（如删 `.part`）。日志里随之出现的其它插件 `CancelledError`、`Traceback`、请求取消**不是本插件失败**。首次装载前征得用户同意或挑空闲时段，`run.sh` 会拦住并要求 `ALLOW_FULL_RELOAD=1`。

所以 `grep -iE "error|traceback"` 在全量 reload 的窗口里必然命中噪声，只能参考，不作判据。方向相反的事实也成立：目标目录原本不存在时，`mkdir` + 同步 + 直接调 reload 就能**首次装载**新插件，不需要任何安装接口。

## 目录与同步约定

部署目录 = 容器内 `DATA_IN_CONTAINER` 的宿主挂载源 + `/plugins/<目录名>`；插件目录是宿主挂载进容器的，**禁止 `docker cp`**：

```bash
docker inspect astrbot --format '{{json .Mounts}}'   # 取 Destination 为 /AstrBot/data 那条的 Source
```

- 首次安装时目标目录不存在，必须先 `mkdir -p "$DST"`。
- rsync 写 `"$SRC"/ "$DST"/`：源码侧尾斜杠表示「拷内容而非目录本身」，目标侧尾斜杠表示「放进这个目录」。漏掉源码侧的 `/` 又遇到 `$DST` 不存在时，会多套一层 `$DST/<目录名>/`。
- `--delete` 默认关闭（镜像删除会被安全策略拦，写错代价高）：需要时用 `SYNC_DELETE=1` 显式开启。平时靠 `diff -rq` 兜底——它报 `Only in <DST>` 的多余文件，在该插件目录内逐个删掉再重跑，不要镜像删、不要 `docker cp` 绕。

## JWT 与 401

- 签一次即落 `/tmp/<plugin_id>_token.txt`（chmod 600），每轮先 `GET /api/v1/plugins` 探测：200 复用，401 或空文件才重签（脚本已做）。
- payload 只需 `username` + `exp`，不需要 scopes；`cmd_config.json` 带 UTF-8 BOM，必须 `encoding='utf-8-sig'`，否则 `JSONDecodeError`。
- 401 的常见原因：token 过期、`jwt_secret` 取错、`DASHBOARD` 指向了别的实例。路由前缀必须是 `/api/v1`（写 `/api` 返回 405）。

## 失败处置

| 现象 | 处置 |
|---|---|
| 写部署目录报 `Permission denied` / `[sandbox: file access denied]` | 向用户申请一次性授权（workspace-write 或 danger-full-access 放行）后重跑同一条命令；不要改用 `docker cp`，不要拆成多条命令多弹几次授权 |
| `rsync` 的 `--delete` 被安全策略拒绝 | 去掉 `--delete` 重跑，改用 `diff -rq` 报出的多余文件逐个删 |
| `diff -rq` 有输出 | `Only in <DST>` 的是多余文件，删掉；其余是内容不一致，说明 rsync 没写成功 |
| reload 返回 `status=error` | `message` 只有「插件重载失败」这类泛化文案，真实错误在容器日志的 `Traceback` 里：`docker logs --since 60s astrbot` 找本插件的 import 报错 |
| 日志里没有 `Loading plugin <id>` | 目录名与 `metadata.yaml` 的 `name` 对不上，或日志窗口太短（加大 `LOG_WINDOW` 重跑 `verify`） |
| 插件在列表里但 `activated=false` | 插件在 `inactivated_plugins` 里，需在面板启用 |

## 背景事实（勿重新论证）

- 容器可能装了 `watchfiles`，但只有 `ASTRBOT_RELOAD=1` 时 star_manager 才启动文件监听；未设置时改动不会自动生效，必须显式调 reload API。`watchdog` 是事件循环诊断日志，与进程重启无关，不能当判据。
- 改动纯 Python 逻辑时，若仓库有离线测试入口（`tests_offline.py`、`tests/*.py`、`pytest`、`make test` 任一），先在部署目录跑最接近的那个，再重载。

**禁止**：`docker restart`、kill 进程、改 `docker-compose.yml` / `cmd_config.json` 等用户配置、调整既有参数。
