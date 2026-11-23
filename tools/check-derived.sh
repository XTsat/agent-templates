#!/usr/bin/env bash
# 扫描本机派生项目，报告其 AGENTS.md 的模板版本相对上游的状态。
#
# 用法：
#   tools/check-derived.sh                 # 扫描默认根目录
#   tools/check-derived.sh ~/workspace     # 扫描指定根目录（可多个）
#   tools/check-derived.sh --format=markdown
#   tools/check-derived.sh --stale=minor   # 只报告落后到 minor/major 档的（推荐用于推送前）
#   tools/check-derived.sh --quiet         # 只输出非最新的
#
# 判定原则：模板发版频繁（实测 19 天 11 个版本），派生项目"落后几个 patch"
# 是常态而非故障。因此按落后档位分级，只有跨 minor/major 才值得关注。
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM="$(cd "$SELF_DIR/.." && pwd)"
FORMAT="text"
QUIET=0
STALE_FILTER=""
ROOTS=()

for arg in "$@"; do
  case "$arg" in
    --format=*)  FORMAT="${arg#--format=}" ;;
    --stale=*)   STALE_FILTER="${arg#--stale=}" ;;
    --quiet)     QUIET=1 ;;
    -h|--help)   sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "未知参数: $arg" >&2; exit 2 ;;
    *)           ROOTS+=("$arg") ;;
  esac
done

if [ ${#ROOTS[@]} -eq 0 ]; then
  ROOTS=("$(dirname "$UPSTREAM")")
fi

# ---- 上游版本序列（从 git 历史提取，用于计算落后多少个版本）----
declare -A UPSTREAM_VER=()
declare -A UPSTREAM_SEQ=()
declare -A UPSTREAM_SINCE=()

load_upstream() {
  local tpl="$1"
  local f="$UPSTREAM/templates/$tpl/AGENTS.md"
  [ -f "$f" ] || { UPSTREAM_VER["$tpl"]="未知"; UPSTREAM_SEQ["$tpl"]=""; return; }
  UPSTREAM_VER["$tpl"]="$(grep -m1 '模板版本' "$f" 2>/dev/null | grep -oE 'v[0-9]+(\.[0-9]+)*' | head -1)"
  # 从该文件的 git 历史收集去重后的版本序列（旧→新）。
  # 注意：子 shell 看不到 local 变量，这里显式用环境变量传入。
  local seq
  seq="$(TPL="$tpl" UP_ROOT="$UPSTREAM" bash -c '
    cd "$UP_ROOT" || exit 0
    for c in $(git log --format=%h -- "templates/$TPL/AGENTS.md" 2>/dev/null | head -80); do
      git show "$c:templates/$TPL/AGENTS.md" 2>/dev/null \
        | grep -m1 "模板版本" | grep -oE "v[0-9]+\.[0-9]+\.[0-9]+"
    done | awk "!seen[\$0]++" | tac | tr "\n" " "
  ')" 
  UPSTREAM_SEQ["$tpl"]="$seq"
  # 当前版本段的起始日：版本号最近一次被改动的那天
  local since cur_ver
  cur_ver="${UPSTREAM_VER[$tpl]:-}"
  since=""
  if [ -n "$cur_ver" ]; then
    since="$(cd "$UPSTREAM" && git log -1 --format=%ad --date=short -S"$cur_ver" -- "templates/$tpl/AGENTS.md" 2>/dev/null)"
  fi
  UPSTREAM_SINCE["$tpl"]="${since:-}"
}

for tpl_dir in "$UPSTREAM"/templates/*/; do
  [ -d "$tpl_dir" ] || continue
  load_upstream "$(basename "$tpl_dir")"
done

# ---- 版本比较：0 相同 / 1 落后 / 2 领先 ----
compare_ver() {
  local a="$1" b="$2"
  [ "$a" = "$b" ] && return 0
  local IFS=. ; local -a A=(${a#v}) B=(${b#v}) ; unset IFS
  local i n=${#A[@]}; [ ${#B[@]} -gt $n ] && n=${#B[@]}
  for ((i=0;i<n;i++)); do
    local x="${A[i]:-0}" y="${B[i]:-0}"
    [[ "$x" =~ ^[0-9]+$ ]] || return 2
    [[ "$y" =~ ^[0-9]+$ ]] || return 2
    ((10#$x < 10#$y)) && return 1
    ((10#$x > 10#$y)) && return 2
  done
  return 0
}

# ---- 落后档位：patch / minor / major ----
gap_level() {
  local local_v="$1" up_v="$2"
  local IFS=. ; local -a A=(${local_v#v}) B=(${up_v#v}) ; unset IFS
  if [ "${A[0]:-0}" != "${B[0]:-0}" ]; then echo "major"
  elif [ "${A[1]:-0}" != "${B[1]:-0}" ]; then echo "minor"
  else echo "patch"; fi
}

# ---- 落后多少个版本（在版本序列里数）----
gap_count() {
  local tpl="$1" local_v="$2"
  local seq="${UPSTREAM_SEQ[$tpl]:-}"
  [ -z "$seq" ] && { echo "?"; return; }
  local n=0 found=0
  for v in $seq; do
    if [ "$found" = "1" ]; then n=$((n+1)); fi
    [ "$v" = "$local_v" ] && found=1
  done
  [ "$found" = "0" ] && { echo "?"; return; }
  echo "$n"
}

# ---- 检查单个项目 ----
inspect_project() {
  local agents="$1"
  local local_ver tpl_name

  local_ver="$(grep -m1 '模板版本' "$agents" 2>/dev/null | grep -oE 'v[0-9]+(\.[0-9]+)*' | head -1)"

  tpl_name="$(grep -m3 -E '来源|派生' "$agents" 2>/dev/null \
    | grep -oE 'templates/[a-z0-9-]+' | head -1 | sed 's|templates/||')"

  if [ -z "$tpl_name" ]; then
    if grep -qm1 'agent-templates' "$agents" 2>/dev/null; then
      case "$(basename "$(dirname "$agents")")" in
        astrbot_plugin_*) tpl_name="astrbot-plugin" ;;
        *)                tpl_name="generic" ;;
      esac
    else
      echo "||NOT_DERIVED||"; return
    fi
  fi

  local up_ver="${UPSTREAM_VER[$tpl_name]:-未知}"

  if [ -z "$local_ver" ]; then
    echo "${tpl_name}|(无版本行)|PRE_VERSION|${up_ver}|0"; return
  fi

  compare_ver "$local_ver" "$up_ver"
  local rc=$?
  if [ $rc -eq 0 ]; then
    echo "${tpl_name}|${local_ver}|CURRENT|${up_ver}|0"
  elif [ $rc -eq 2 ]; then
    echo "${tpl_name}|${local_ver}|AHEAD|${up_ver}|0"
  else
    local lvl cnt
    lvl="$(gap_level "$local_ver" "$up_ver")"
    cnt="$(gap_count "$tpl_name" "$local_ver")"
    echo "${tpl_name}|${local_ver}|${lvl}|${up_ver}|${cnt}"
  fi
}

ROWS=()
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r agents; do
    proj_dir="$(dirname "$agents")"
    [ "$proj_dir" = "$UPSTREAM" ] && continue
    case "$proj_dir" in *agent-templates*) continue ;; esac
    IFS='|' read -r tpl local_ver status up_ver cnt <<< "$(inspect_project "$agents")"
    [ "$status" = "NOT_DERIVED" ] && continue
    ROWS+=("${proj_dir}|${tpl}|${local_ver}|${status}|${up_ver}|${cnt}")
  done < <(find "$root" -maxdepth 3 -name AGENTS.md -type f 2>/dev/null | sort)
done

# ---- 分级文案 ----
# CURRENT        最新
# patch          落后几个 patch —— 常态，不告警
# minor          跨 minor —— 值得安排合并
# major          跨 major —— 必须迁移
# PRE_VERSION    早于版本行引入（2026-10-21），合并一次即补齐
# AHEAD          本地比上游新（可能是本地改过版本行）
label_of() {
  case "$1" in
    CURRENT)     echo "✅ 最新" ;;
    patch)       echo "○ 落后 patch" ;;
    minor)       echo "⚠️ 跨 minor" ;;
    major)       echo "❗跨 major" ;;
    PRE_VERSION) echo "◻ 早于版本行" ;;
    AHEAD)       echo "❓ 领先上游" ;;
    *)           echo "$1" ;;
  esac
}

# ---- 过滤 ----
passes() {
  local st="$1"
  [ "$QUIET" = "1" ] && [ "$st" = "CURRENT" ] && return 1
  case "$STALE_FILTER" in
    "")      return 0 ;;
    minor)   case "$st" in minor|major) return 0 ;; *) return 1 ;; esac ;;
    major)   [ "$st" = "major" ] && return 0 || return 1 ;;
    *)       return 0 ;;
  esac
}

# ---- 输出 ----
c_total=0; c_current=0; c_patch=0; c_minor=0; c_major=0; c_pre=0; c_ahead=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r _ _ _ st _ _ <<< "$row"
  c_total=$((c_total+1))
  case "$st" in
    CURRENT) c_current=$((c_current+1)) ;;
    patch)   c_patch=$((c_patch+1)) ;;
    minor)   c_minor=$((c_minor+1)) ;;
    major)   c_major=$((c_major+1)) ;;
    PRE_VERSION) c_pre=$((c_pre+1)) ;;
    AHEAD)   c_ahead=$((c_ahead+1)) ;;
  esac
done

if [ "$FORMAT" = "markdown" ]; then
  echo "<!-- 由 tools/check-derived.sh 于 $(date '+%Y-%m-%d %H:%M') 生成，请勿手改 -->"
  echo
  echo "| 派生项目 | 模板 | 本地 | 上游 | 差几版 | 状态 |"
  echo "|---|---|---|---|---|---|"
  for row in "${ROWS[@]}"; do
    IFS='|' read -r proj tpl local_ver st up_ver cnt <<< "$row"
    passes "$st" || continue
    echo "| \`$(basename "$proj")\` | ${tpl} | ${local_ver} | ${up_ver} | ${cnt} | $(label_of "$st") |"
  done
else
  printf "%-44s %-16s %-10s %-9s %-6s %s\n" "派生项目" "模板" "本地" "上游" "差几版" "状态"
  printf '%.0s─' {1..104}; echo
  for row in "${ROWS[@]}"; do
    IFS='|' read -r proj tpl local_ver st up_ver cnt <<< "$row"
    passes "$st" || continue
    printf "%-44s %-16s %-10s %-9s %-6s %s\n" \
      "$(basename "$proj")" "$tpl" "$local_ver" "$up_ver" "$cnt" "$(label_of "$st")"
  done
fi

echo
echo "扫描 ${c_total} 个：最新 ${c_current} · 落后patch ${c_patch} · 跨minor ${c_minor} · 跨major ${c_major} · 早于版本行 ${c_pre} · 领先 ${c_ahead}"

# ---- 传播期：上游刚发版时，派生项目来不及跟进是正常的 ----
# 实测上游 19 天发 11 个版本，若一升版就要求全部派生项目同步，告警会永远满屏。
# 因此当前版本段发布不足 GRACE_DAYS 天时，所有落后项降级为"传播期内"。
GRACE_DAYS="${GRACE_DAYS:-7}"
today_ts=$(date +%s)
in_grace=0
newest_since=""
for tpl in "${!UPSTREAM_SINCE[@]}"; do
  s="${UPSTREAM_SINCE[$tpl]}"
  [ -z "$s" ] && continue
  s_ts=$(date -d "$s" +%s 2>/dev/null) || continue
  age=$(( (today_ts - s_ts) / 86400 ))
  if [ "$age" -lt "$GRACE_DAYS" ]; then in_grace=1; newest_since="$s"; fi
done

if [ "$in_grace" = "1" ]; then
  echo
  echo "ℹ️  上游 ${newest_since} 刚发版（不足 ${GRACE_DAYS} 天），派生项目处于传播期；"
  echo "    此期间落后不计为异常。用 GRACE_DAYS=0 tools/check-derived.sh 可查看全部差距。"
fi

# 退出码：传播期内恒为 0；否则只有跨 minor/major 才算需要处理。
if [ "$in_grace" = "1" ]; then exit 0; fi
[ $((c_minor + c_major)) -eq 0 ]
