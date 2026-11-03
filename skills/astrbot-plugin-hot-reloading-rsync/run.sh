#!/usr/bin/env bash
# 热重载 AstrBot 插件：一条命令跑完 前置检查 → 同步 → 校验 → JWT → reload → 验证。
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
TOKEN_FILE=${TOKEN_FILE:-$TMPDIR_/${PLUGIN_ID}_token.txt}
PLUGINS_JSON=$(mktemp "$TMPDIR_/${PLUGIN_ID}_plugins.XXXXXX.json")
LOG_FILE=$(mktemp "$TMPDIR_/${PLUGIN_ID}_log.XXXXXX.txt")
trap 'rm -f "$PLUGINS_JSON" "$LOG_FILE"' EXIT

say() { printf '%s\n' "$*"; }
die() { printf '✗ %s\n' "$*" >&2; exit 1; }

# 同步/比对共用的排除项（diff 与 rsync 都接受 --exclude=GLOB）
EXCLUDES=(.git .notes __pycache__ '*.pyc' .venv .mypy_cache .pytest_cache)
EXCLUDE_ARGS=()
for e in "${EXCLUDES[@]}"; do EXCLUDE_ARGS+=("--exclude=$e"); done

api_code() { curl -s -o /dev/null -w '%{http_code}' "$DASHBOARD/api/v1/plugins" -H "Authorization: Bearer $1"; }

preflight() {
  docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" \
    || die "容器 $CONTAINER 未在运行（docker ps 里没有这个名字）"
  DATA_SRC=$(docker inspect "$CONTAINER" --format '{{json .Mounts}}' | python3 -c '
import json, sys
want = sys.argv[1]
for m in json.load(sys.stdin):
    if m.get("Destination") == want:
        print(m.get("Source") or "")
        break
' "$DATA_IN_CONTAINER")
  [ -n "${DATA_SRC:-}" ] || die "容器内 $DATA_IN_CONTAINER 没有宿主挂载，无法推导部署目录（不要改用 docker cp）"
  DST=${DST:-$DATA_SRC/plugins/$PLUGIN_ID}
  [ -f "$SRC/metadata.yaml" ] || [ -f "$SRC/metadata.yml" ] \
    || say "· 警告：$SRC 下没有 metadata.yaml，验证阶段将跳过元数据比对"
  say "· 容器=$CONTAINER  宿主数据目录=$DATA_SRC  部署目录=$DST"
}

do_sync() {
  local extra=()
  if [ "$SYNC_DELETE" = "1" ]; then extra+=(--delete); say "· 已显式开启 --delete（镜像删除）"; fi
  mkdir -p "$DST"
  rsync -a ${extra[@]+"${extra[@]}"} "${EXCLUDE_ARGS[@]}" "$SRC"/ "$DST"/
  local out
  out=$(diff -rq "${EXCLUDE_ARGS[@]}" "$SRC" "$DST" || true)
  if [ -n "$out" ]; then
    printf '%s\n' "$out"
    die "同步后 diff 不为空：上面 Only in 的多余文件需在 $DST 内逐个删除后重跑（不要用 docker cp 兜底）"
  fi
  say "✓ 同步一致：$SRC/ → $DST/"
}

do_token() {
  if [ -s "$TOKEN_FILE" ] && [ "$(api_code "$(cat "$TOKEN_FILE")")" = "200" ]; then
    TOKEN=$(cat "$TOKEN_FILE")
    say "✓ 复用缓存 token：$TOKEN_FILE"
    return
  fi
  docker exec "$CONTAINER" python3 -c '
import datetime, json, sys
import jwt
cfg = json.load(open(sys.argv[1], encoding="utf-8-sig"))["dashboard"]
payload = {
    "username": cfg["username"],
    "exp": datetime.datetime.now(datetime.timezone.utc) + datetime.timedelta(days=7),
}
tok = jwt.encode(payload, cfg["jwt_secret"], algorithm="HS256")
print(tok if isinstance(tok, str) else tok.decode())
' "$DATA_IN_CONTAINER/cmd_config.json" > "$TOKEN_FILE" || die "容器内签发 JWT 失败"
  chmod 600 "$TOKEN_FILE"
  TOKEN=$(cat "$TOKEN_FILE")
  [ -n "$TOKEN" ] || die "签发的 token 为空（检查 $DATA_IN_CONTAINER/cmd_config.json 是否存在）"
  [ "$(api_code "$TOKEN")" = "200" ] \
    || die "新 token 仍打不通 $DASHBOARD/api/v1/plugins：多为 DASHBOARD 地址不对或 jwt_secret 取错"
  say "✓ 新签 token 并已落盘：$TOKEN_FILE"
}

is_registered() {
  curl -s "$DASHBOARD/api/v1/plugins" -H "Authorization: Bearer $TOKEN" -o "$PLUGINS_JSON"
  python3 - "$PLUGINS_JSON" "$PLUGIN_ID" <<'PY'
import json, sys
data = json.load(open(sys.argv[1])).get("data") or []
if isinstance(data, dict):
    data = data.get("plugins") or []
pid = sys.argv[2]
raise SystemExit(0 if any((p.get("root_dir_name") or p.get("name")) == pid for p in data) else 1)
PY
}

do_reload() {
  if is_registered; then
    say "· $PLUGIN_ID 已注册：本次 reload 只 terminate + 重载它，其它插件不受影响"
  else
    if [ "$ALLOW_FULL_RELOAD" != "1" ]; then
      say "· $PLUGIN_ID 尚未注册（首次装载）：reload 会 terminate 并重载**全部**插件，"
      say "  打断其它插件正在跑的请求、触发各插件 terminate() 清理。"
      say "  征得用户同意后重跑：ALLOW_FULL_RELOAD=1 SRC=$SRC bash $0"
      exit 3
    fi
    say "· $PLUGIN_ID 尚未注册（首次装载）：本次 reload 会 terminate 并重载全部插件"
  fi
  local resp status msg
  resp=$(curl -s -X POST "$DASHBOARD/api/v1/plugins/$PLUGIN_ID/reload" -H "Authorization: Bearer $TOKEN")
  status=$(printf '%s' "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("status"))' 2>/dev/null) \
    || die "reload 请求没有返回 JSON：$resp"
  msg=$(printf '%s' "$resp" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("message") or "")')
  [ "$status" = "ok" ] \
    || die "reload 失败：status=$status message=$msg（HTTP 仍是 200，失败详情看容器日志里的 Traceback）"
  say "✓ reload：$msg"
}

do_verify() {
  sleep "$RELOAD_WAIT"
  curl -s "$DASHBOARD/api/v1/plugins" -H "Authorization: Bearer $TOKEN" -o "$PLUGINS_JSON"
  python3 - "$PLUGINS_JSON" "$SRC" "$PLUGIN_ID" <<'PY'
import json, os, re, sys

json_path, src, pid = sys.argv[1:4]
data = json.load(open(json_path)).get("data") or []
if isinstance(data, dict):
    data = data.get("plugins") or []
hit = [p for p in data if (p.get("root_dir_name") or p.get("name")) == pid]
if not hit:
    print(f"✗ /api/v1/plugins 的 {len(data)} 个插件里没有 {pid}：目录名或 metadata.yaml 的 name 不对")
    raise SystemExit(1)

p = hit[0]
print(f"· API：name={p.get('name')} display_name={p.get('display_name')} "
      f"version={p.get('version')} activated={p.get('activated')}")

meta_path = next((os.path.join(src, n) for n in ("metadata.yaml", "metadata.yml")
                  if os.path.exists(os.path.join(src, n))), None)
problems = []
if meta_path:
    try:
        import yaml
        meta = yaml.safe_load(open(meta_path, encoding="utf-8")) or {}
    except Exception:
        text = open(meta_path, encoding="utf-8").read()
        meta = {}
        for key in ("name", "version", "display_name"):
            m = re.search(rf"^{key}\s*:\s*(.+?)\s*$", text, re.M)
            if m:
                meta[key] = m.group(1).strip().strip("'\"")
    for key in ("version", "display_name"):
        want = meta.get(key)
        if want and str(want) != str(p.get(key)):
            problems.append(f"{key} 与 metadata.yaml 不一致：文件={want} API={p.get(key)}")
    if meta.get("name") and str(meta["name"]) != pid:
        print(f"· 注意：metadata.yaml 的 name={meta['name']} 与目录名 {pid} 不同，reload 用目录名即可")
    if not problems:
        print("✓ metadata.yaml 与 API 一致")
else:
    print("· 无 metadata.yaml，跳过元数据比对")

if not p.get("activated"):
    problems.append("插件在注册表里但未激活（多半在 inactivated_plugins 中），需在面板启用后再验")

if problems:
    print("✗ " + "；".join(problems))
    raise SystemExit(1)
PY

  docker logs --since "$LOG_WINDOW" "$CONTAINER" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' > "$LOG_FILE" || true
  python3 - "$LOG_FILE" "$PLUGIN_ID" <<'PY'
import re, sys

log_path, pid = sys.argv[1:3]
lines = open(log_path, encoding="utf-8", errors="replace").read().splitlines()


def ts(line):
    m = re.match(r"\[(\d{2}):(\d{2}):(\d{2})\.(\d{3})\]", line)
    if not m:
        return None
    h, mi, s, ms = (int(x) for x in m.groups())
    return h * 3600 + mi * 60 + s + ms / 1000


loads = [(ts(line), m.group(1))
         for line in lines
         for m in [re.search(r"Loading plugin (\S+) \.\.\.", line)] if m]
problems = []
mine = [t for t, name in loads if name == pid]
if not mine:
    problems.append(f"日志窗口内没有 'Loading plugin {pid} ...'（包没被加载，或窗口太短，加大 LOG_WINDOW 重跑 verify）")
for marker, label in (
    (f"Failed to import plugin {pid}", "导入失败"),
    (f"Plugin {pid} did not terminate cleanly", "terminate 未干净退出"),
):
    if any(marker in line for line in lines):
        problems.append(f"{label}：{marker}")

# 同一批次（本插件加载前后 20s 内）还加载了谁：多于本插件即全量重载/进程重启
batch = {name for t, name in loads
         if t is not None and mine and mine[-1] - 20 <= t <= mine[-1] + 20}
others = sorted(batch - {pid})
noise = sum(1 for line in lines if "Traceback" in line or "CancelledError" in line)
scope = ("本次只重载了本插件" if not others
         else f"本次是全量重载：同时加载了 {len(others)} 个其它插件（如 {others[0]}）")

print(f"· 日志窗口 {len(lines)} 行，本插件加载 {len(mine)} 次 → {scope}")
print(f"· 窗口内 Traceback/CancelledError 共 {noise} 处；全量重载时其它插件被 terminate 抛出的取消/中断属正常，判定以 API 校验 + 本插件日志为准")
related = [line for line in lines if pid in line]
if related:
    print("· 提到本插件的日志（末 10 行）：")
    for line in related[-10:]:
        print("  " + line)
else:
    print("· 窗口内没有提到本插件的日志行")

if problems:
    print("✗ " + "；".join(problems))
    raise SystemExit(1)
print("✓ 日志校验通过")
PY
}

case "$STAGE" in
  all)    preflight; do_sync; do_token; do_reload; do_verify; say "✓ 全流程通过：$PLUGIN_ID → $DST" ;;
  sync)   preflight; do_sync ;;
  token)  preflight; do_token ;;
  reload) preflight; do_token; do_reload ;;
  verify) preflight; do_token; do_verify ;;
  *)      die "未知阶段：$STAGE（可用 all|sync|token|reload|verify）" ;;
esac
