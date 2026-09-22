---
name: astrbot-plugin-hot-reloading
description: '热重载 AstrBot 插件（同步源码 + 插件级重载）。仅在用户主动提出时使用。'
---

热重载 AstrBot 插件（同步源码 + 插件级重载）

**使用约定：仅当用户主动提出（如「热重载插件」「热更新 AstrBot 插件」）时才使用本 skill，不得在普通改动流程中自动执行。**

参数：`SRC`=插件源码目录、`PLUGIN_ID`=插件目录名、`CONTAINER`=AstrBot 容器名（默认 `astrbot`）、`DASHBOARD`=WebUI 地址（默认 `http://127.0.0.1:6185`）。目标目录由容器挂载推导：

```bash
docker inspect $CONTAINER --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'
```

取 `data` 挂载源，拼成 `<data源>/plugins/$PLUGIN_ID`。插件目录是宿主机挂载进容器的，**禁止 `docker cp`**。

## 一、同步

```bash
rsync -a --delete --exclude=.git --exclude=.notes --exclude='__pycache__' --exclude='*.pyc' "$SRC" "$DST"
diff -rq --exclude=.git --exclude=__pycache__ --exclude=.notes "$SRC" "$DST"
```

`diff` 必须无输出，有输出即同步失败。

## 二、签发 Dashboard JWT（在容器内执行，容器自带 PyJWT）

```bash
TOKEN=$(docker exec $CONTAINER python3 -c "
import json, datetime, jwt
cfg = json.load(open('/AstrBot/data/cmd_config.json', encoding='utf-8-sig'))
dbc = cfg['dashboard']
p = {'username': dbc['username'], 'exp': datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=7)}
t = jwt.encode(p, dbc['jwt_secret'], algorithm='HS256')
print(t if isinstance(t,str) else t.decode())")
```

`cmd_config.json` 带 UTF-8 BOM，必须 `encoding='utf-8-sig'`，否则 JSONDecodeError。payload 仅需 `username` + `exp`，不需要 scopes。参考实现：容器内 `/AstrBot/data/plugins/astrbot_plugin_restart/core/dashboard_client.py` 的 `_generate_jwt()`。

## 三、重载

```bash
curl -s -X POST "$DASHBOARD/api/v1/plugins/$PLUGIN_ID/reload" -H "Authorization: Bearer $TOKEN"
```

成功返回 `{"status":"ok","message":"重载成功。"}`。前缀必须是 `/api/v1`，写成 `/api` 返回 405 Method Not Allowed；401 说明 JWT 无效，多半是 config 路径或 `jwt_secret` 取错。

## 四、验证

```bash
sleep 3
docker logs $CONTAINER --since 20s 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -iE "$PLUGIN_ID|error|traceback"
```

通过标准：
- 出现 `Removed handler ... from plugin $PLUGIN_ID`
- 出现 `Loading plugin $PLUGIN_ID`
- 出现「插件已初始化」及后续就绪日志
- 无 `error` / `traceback`
- 未出现 `watchdog enabled`（出现即 AstrBot 进程被重启，视为失败）
- `Removed handler` 中只允许出现本插件一个名字

**禁止**：`docker restart`、`kill` 进程、改 `docker-compose.yml` 或 `cmd_config.json` 等用户配置、修改任何既有参数。

## 背景事实（勿重新论证）

容器可能已装 `watchfiles`，但只有 `ASTRBOT_RELOAD=1` 时 star_manager 才启动文件监听热重载；未设置时插件不会自动重载，必须显式调 reload API。若改动纯 Python 逻辑且插件自带 `tests_offline.py`，可先在部署目录跑 `python3 tests_offline.py` 验证再重载。
