#!/usr/bin/env bash
# 部署 AstrBot 插件并热重载（docker 写入版）：
# 一条命令跑完 前置检查 → 逐文件写入容器挂载目录 → 哈希校验 → JWT → reload → 验证。
# 用法：SRC=/abs/插件源码 bash run.sh [all|sync|token|reload|verify]
# 环境变量见 SKILL.md「一步执行」。退出码 0 = 通过。
set -euo pipefail

STAGE=${1:-all}
CONTAINER=${CONTAINER:-astrbot}
DASHBOARD=${DASHBOARD:-http://127.0.0.1:6185}
DATA_IN_CONTAINER=${DATA_IN_CONTAINER:-/AstrBot/data}
SYNC_DELETE=${SYNC_DELETE:-0}
ALLOW_FULL_RELOAD=${ALLOW_FULL_RELOAD:-0}
LOG_WINDOW=${LOG_WINDOW:-60s}
RELOAD_WAIT=${RELOAD_WAIT:-3}
TMPDIR_=${TMPDIR:-/tmp}

: "${SRC:?必须给出插件源码绝对路径：SRC=/abs/path bash run.sh}"
[ -d "$SRC" ] || { echo "✗ SRC 不存在：$SRC"; exit 1; }
SRC=${SRC%/}
PLUGIN_ID=${PLUGIN_ID:-$(basename "$SRC")}
DST_IN_CONTAINER=${DST:-$DATA_IN_CONTAINER/plugins/$PLUGIN_ID}
TOKEN_FILE=${TOKEN_FILE:-$TMPDIR_/${PLUGIN_ID}_token.txt}
PLUGINS_JSON=$(mktemp "$TMPDIR_/${PLUGIN_ID}_plugins.XXXXXX.json")
LOG_FILE=$(mktemp "$TMPDIR_/${PLUGIN_ID}_log.XXXXXX.txt")
LOCAL_LIST=$(mktemp "$TMPDIR_/${PLUGIN_ID}_local.XXXXXX.txt")
REMOTE_LIST=$(mktemp "$TMPDIR_/${PLUGIN_ID}_remote.XXXXXX.txt")
trap 'rm -f "$PLUGINS_JSON" "$LOG_FILE" "$LOCAL_LIST" "$REMOTE_LIST"' EXIT

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# 本地/容器内共用的排除规则（容器侧用 sh 的通配写法，保持一致）
local_files() {
  ( cd "$SRC" && find . -type f \
      -not -path './.git/*' -not -path './.notes/*' \
      -not -path '*/__pycache__/*' -not -path './.venv/*' \
      -not -path './.mypy_cache/*' -not -path './.pytest_cache/*' \
      -not -name '*.pyc' -not -name '.DS_Store' \
      | sed 's|^\./||' | sort )
}

remote_files() {
  docker exec "$CONTAINER" sh -c 'cd "$1" 2>/dev/null || exit 0
    find . -type f \
      -not -path "./.git/*" -not -path "./.notes/*" \
      -not -path "*/__pycache__/*" -not -path "./.venv/*" \
      -not -path "./.mypy_cache/*" -not -path "./.pytest_cache/*" \
      -not -name "*.pyc" -not -name ".DS_Store" \
      | sed "s|^\./||" | sort' _ "$DST_IN_CONTAINER"
}

api_code() { curl -s -o /dev/null -w '%{http_code}' "$DASHBOARD/api/v1/plugins" -H "Authorization: Bearer $1"; }

meta_get() {
  SRC="$SRC" python3 - "$1" <<'PYEOF'
import os, re, sys
key = sys.argv[1]
src = os.environ["SRC"]
for name in ("metadata.yaml", "metadata.yml"):
    path = os.path.join(src, name)
    if os.path.exists(path):
        break
else:
    sys.exit(0)
pat = re.compile(r"^" + re.escape(key) + r"\s*:\s*(.+?)\s*$")
for line in open(path, encoding="utf-8"):
    m = pat.match(line)
    if m:
        v = m.group(1)
        if len(v) > 1 and v[0] in "\"'" and v[-1] == v[0]:
            v = v[1:-1]
        print(v)
        break
PYEOF
}

preflight() {
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" \
    || die "容器 $CONTAINER 未在运行（docker ps 里没有这个名字）"
  docker exec "$CONTAINER" sh -c 'exit 0' \
    || die "无法在容器 $CONTAINER 内执行命令"
  say "· 容器=$CONTAINER  目标目录（容器内）=$DST_IN_CONTAINER  插件=$PLUGIN_ID"
  [ -f "$SRC/metadata.yaml" ] || [ -f "$SRC/metadata.yml" ] \
    || say "· 警告：$SRC 下没有 metadata.yaml，验证阶段将跳过元数据比对"
}

do_sync() {
  local rel h_local h_remote count=0

  docker exec "$CONTAINER" mkdir -p "$DST_IN_CONTAINER" \
    || die "无法在容器内创建目录 $DST_IN_CONTAINER"
  say "· 目录就绪：$DST_IN_CONTAINER"

  local_files > "$LOCAL_LIST"
  [ -s "$LOCAL_LIST" ] || die "SRC 下没有可同步的文件：$SRC"

  while IFS= read -r rel; do
    case "$rel" in
      ""|..|../*|/*) die "非法相对路径：$rel" ;;
    esac
    docker exec -i "$CONTAINER" sh -c 'cat > "$1"' _ "$DST_IN_CONTAINER/$rel" < "$SRC/$rel" \
      || die "写入失败：$rel"
    count=$((count+1))
  done < "$LOCAL_LIST"
  say "· 已写入 $count 个文件（经容器内进程，未写宿主路径）"

  while IFS= read -r rel; do
    h_local=$(sha256sum "$SRC/$rel" | cut -d' ' -f1)
    h_remote=$(docker exec "$CONTAINER" sha256sum "$DST_IN_CONTAINER/$rel" 2>/dev/null | cut -d' ' -f1 || true)
    [ "$h_local" = "$h_remote" ] || die "哈希不一致（写入被截断？）：$rel"
  done < "$LOCAL_LIST"
  say "· 哈希校验通过（$count/$count 一致）"

  remote_files > "$REMOTE_LIST"
  local extra
  extra=$(comm -13 "$LOCAL_LIST" "$REMOTE_LIST" || true)
  if [ -n "$extra" ]; then
    say "· 容器内存在本地没有的文件："
    printf '%s\n' "$extra" | sed 's/^/    /'
    if [ "$SYNC_DELETE" = "1" ]; then
      while IFS= read -r rel; do
        [ -n "$rel" ] || continue
        docker exec "$CONTAINER" rm -f "$DST_IN_CONTAINER/$rel"
      done <<< "$extra"
      say "· 已删除上述多余文件（SYNC_DELETE=1）"
    else
      say "· 未删除（需要时用 SYNC_DELETE=1 bash run.sh sync）"
    fi
  else
    say "· 容器内无多余文件"
  fi
}

do_token() {
  local code="" token=""
  if [ -s "$TOKEN_FILE" ]; then
    token=$(cat "$TOKEN_FILE")
    code=$(api_code "$token" || true)
    if [ "$code" = "200" ]; then
      say "· 复用已缓存的 token（$TOKEN_FILE）"
      printf '%s' "$token"
      return 0
    fi
  fi
  token=$(docker exec -i "$CONTAINER" python3 - "$DATA_IN_CONTAINER/cmd_config.json" <<'PY'
import base64, hashlib, hmac, json, sys, time
cfg = json.load(open(sys.argv[1], encoding="utf-8-sig"))
dash = cfg.get("dashboard") or {}
secret = dash.get("jwt_secret")
if not secret:
    sys.exit("cmd_config.json 里没有 dashboard.jwt_secret")
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=")
now = int(time.time())
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
body = b64(json.dumps({"username": dash.get("username", ""), "exp": now + 7 * 86400, "iat": now}).encode())
sig = b64(hmac.new(secret.encode(), head + b"." + body, hashlib.sha256).digest())
print((head + b"." + body + b"." + sig).decode())
PY
) || die "签发 token 失败（检查 cmd_config.json 的 dashboard 配置）"
  [ -n "$token" ] || die "签发 token 为空"
  : > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE" 2>/dev/null || true
  printf '%s' "$token" > "$TOKEN_FILE"
  code=$(api_code "$token" || true)
  [ "$code" = "200" ] || die "新 token 仍不通（HTTP $code）：检查 DASHBOARD=$DASHBOARD 是否指向本实例"
  say "· 已签发并验证 token（$TOKEN_FILE）"
  printf '%s' "$token"
}

do_reload() {
  local token status
  token=$(do_token | tail -n1)
  say "· 调用插件级 reload：/$PLUGIN_ID"
  status=$(curl -s -X POST "$DASHBOARD/api/v1/plugins/$PLUGIN_ID/reload" \
      -H "Authorization: Bearer $token" \
    | python3 -c 'import json,sys; print((json.load(sys.stdin) or {}).get("status",""))' 2>/dev/null || echo "")
  if [ "$status" = "ok" ]; then
    say "· reload ok"
    sleep "$RELOAD_WAIT"
    return 0
  fi
  if [ "$ALLOW_FULL_RELOAD" != "1" ]; then
    die "reload 未成功（status=${status:-空}）。插件可能尚未注册，首次装载属于全量 reload：确认后 ALLOW_FULL_RELOAD=1 重跑"
  fi
  say "· 全量 reload 模式（ALLOW_FULL_RELOAD=1）重试"
  curl -s -X POST "$DASHBOARD/api/v1/plugins/reload" -H "Authorization: Bearer $token" >/dev/null || true
  sleep "$RELOAD_WAIT"
}

do_verify() {
  local token want_version want_name
  token=$(do_token | tail -n1)
  curl -s "$DASHBOARD/api/v1/plugins" -H "Authorization: Bearer $token" > "$PLUGINS_JSON" \
    || die "拉取插件列表失败"

  want_version=$(meta_get version || true)
  want_name=$(meta_get display_name || true)

  PLUGIN_ID="$PLUGIN_ID" WANT_VERSION="$want_version" WANT_NAME="$want_name" \
  python3 - "$PLUGINS_JSON" <<'PY' || die "插件列表校验未通过"
import json, os, sys
plugin_id = os.environ["PLUGIN_ID"]
want_version = os.environ.get("WANT_VERSION", "")
want_name = os.environ.get("WANT_NAME", "")
data = json.load(open(sys.argv[1], encoding="utf-8"))
items = data.get("data") if isinstance(data, dict) else data
if isinstance(items, dict):
    items = items.get("plugins") or items.get("items") or []
entry = None
for it in items or []:
    if plugin_id in (it.get("root_dir_name"), it.get("name")):
        entry = it
        break
if entry is None:
    sys.exit(f"插件列表里没有 {plugin_id}")
problems = []
if entry.get("activated") is False:
    problems.append("activated=false（在 inactivated_plugins 里，需在面板启用）")
if want_version and entry.get("version") != want_version:
    problems.append(f"version={entry.get('version')} != metadata {want_version}")
if want_name and entry.get("display_name") not in (None, "", want_name):
    problems.append(f"display_name={entry.get('display_name')} != metadata {want_name}")
if problems:
    sys.exit("; ".join(problems))
print(f"· 列表校验通过：{plugin_id} {entry.get('version')} activated={entry.get('activated')}")
PY

  docker logs --since "$LOG_WINDOW" "$CONTAINER" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$LOG_FILE" || true
  grep -q "Loading plugin $PLUGIN_ID" "$LOG_FILE" \
    || die "日志窗口（$LOG_WINDOW）内没有 'Loading plugin $PLUGIN_ID'：多半是距上次 reload 已超过该窗口（先跑 reload，或 LOG_WINDOW=10m 重跑 verify）；也可能目录名与 metadata.yaml 的 name 不一致"
  say "· 日志校验通过：Loading plugin $PLUGIN_ID"
  if grep -qE "Failed to import plugin $PLUGIN_ID|Plugin $PLUGIN_ID did not terminate cleanly" "$LOG_FILE"; then
    die "日志里出现本插件的失败/未干净退出记录，详情见容器日志"
  fi
  local loads
  loads=$(grep -c "Loading plugin" "$LOG_FILE" || true)
  [ "${loads:-0}" -gt 1 ] && say "· 注意：同窗口内加载了 $loads 个插件 = 全量 reload，其它插件的报错不是本插件失败"
  say "✓ 部署与热重载完成：$PLUGIN_ID"
}

case "$STAGE" in
  all) preflight; do_sync; do_reload; do_verify ;;
  sync) preflight; do_sync ;;
  token) do_token >/dev/null && say "· token 可用" ;;
  reload) do_reload ;;
  verify) do_verify ;;
  *) die "未知阶段：$STAGE（可用：all/sync/token/reload/verify）" ;;
esac
