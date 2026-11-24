#!/usr/bin/env bash
# 扫描本机派生项目，报告其 AGENTS.md 的模板版本相对上游的状态。
#
# 用法：
#   tools/check-derived.sh                 # 扫描默认根目录
#   tools/check-derived.sh ~/workspace     # 扫描指定根目录（可多个）
#   tools/check-derived.sh --format=markdown
#   tools/check-derived.sh --format=detail # 逐项目分行列出缺失锚点与缺失 docs
#   tools/check-derived.sh --project ~/x   # 只检查一个派生项目（等价 tools/sync-check.sh ~/x）
#   tools/check-derived.sh --stale=minor   # 只报告落后到 minor/major 档的（推荐用于推送前）
#   tools/check-derived.sh --quiet         # 只输出非最新的
#   tools/check-derived.sh --no-content    # 跳过正文内容核验，只看版本（旧行为）
#
# 判定原则：模板发版频繁（实测 19 天 11 个版本），派生项目"落后几个 patch"
# 是常态而非故障。因此按落后档位分级，只有跨 minor/major 才值得关注。
#
# 两个互不相关的判定轴：
#   ① 版本轴：头部「模板版本」行  vs  上游当前版本  → 落后档位（patch 常态，不告警）
#   ② 内容轴：锚点清单（templates/<模板>/check-anchors.txt）→ 关键节是否真的存在
# 版本号是派生项目自报的，正文被重写后版本号照样可以写对，所以两轴必须分开看：
# 版本最新 ≠ 内容齐全。内容轴缺失不受传播期（GRACE_DAYS）豁免。
#
# 退出码：0 无问题 / 1 跨 minor/major（传播期外）/ 2 关键锚点缺失（任何时期）
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM="$(cd "$SELF_DIR/.." && pwd)"
FORMAT="text"
QUIET=0
STALE_FILTER=""
ROOTS=()
CONTENT_CHECK=1
PROJECT=""

need_val() { [ $# -ge 2 ] || { echo "参数 $1 需要一个值" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  arg="$1"
  case "$arg" in
    --format=*)  FORMAT="${arg#--format=}" ;;
    --stale=*)   STALE_FILTER="${arg#--stale=}" ;;
    --project)   need_val "$@"; PROJECT="$2"; shift ;;
    --project=*) PROJECT="${arg#--project=}" ;;
    --no-content) CONTENT_CHECK=0 ;;
    --quiet)     QUIET=1 ;;
    -h|--help)   sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)          echo "未知参数: $arg" >&2; exit 2 ;;
    *)           ROOTS+=("$arg") ;;
  esac
  shift
done

# --project：只检查一个派生项目，默认出详细清单
if [ -n "$PROJECT" ]; then
  [ -f "$PROJECT/AGENTS.md" ] || { echo "不是项目目录（缺 AGENTS.md）：$PROJECT" >&2; exit 2; }
  ROOTS=("$PROJECT")
  [ "$FORMAT" = "text" ] && FORMAT="detail"
fi

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

# ---- 内容轴：锚点校验（与版本轴完全独立）----
# 锚点清单在 templates/<模板>/check-anchors.txt —— 放在模板旁边而不是写死在脚本里：
#   · 改模板正文的人顺手就能改锚点，二者不易漂移；
#   · 不写进 AGENTS.md，不占 16 KB 正文预算；
#   · 不在候选文件名之列，不会被自动注入。
declare -A CONTENT=()        # proj -> OK / WARN / MISS / NA / OFF
declare -A CONTENT_BLOCK=()  # proj -> blocker 缺失行（\n 分隔）
declare -A CONTENT_WARN=()   # proj -> warn 缺失行（\n 分隔）
declare -A STRUCT=()         # proj -> 章节标题缺失数/总数（仅诊断用）

anchors_file() { echo "$UPSTREAM/templates/$1/check-anchors.txt"; }

# 模板章节标题（去掉「## N. 」编号）——派生项目允许回填与增删章节，所以只做倾向提示
template_headings() {
  local f="$UPSTREAM/templates/$1/AGENTS.md"
  [ -f "$f" ] && sed -nE 's/^## +[0-9]+\. +(.+)$/\1/p' "$f"
}

# 「疑似重写」诊断：模板章节标题在派生文件里还剩几个。
# 只提示，绝不影响退出码——派生项目合法地会增删章节，编号也未必一致。
struct_hint() {
  local agents="$1" tpl="$2" proj="$3"
  local miss=0 tot=0 h core
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    tot=$((tot+1))
    core="${h%%（*}"          # 去掉「（强制，不可省略）」这类后缀
    core="$(echo "$core" | sed 's/[[:space:]]*$//')"
    # 双向包含：模板标题「核心代码规范」↔ 派生标题「代码规范」都算命中
    if ! awk -v core="$core" '
        /^#+ / {
          line=$0; sub(/^#+ +([0-9]+\. +)?/, "", line)
          if (index(line, core) || index(core, line)) found=1
        }
        END { exit(found?0:1) }' "$agents"; then
      miss=$((miss+1))
    fi
  done < <(template_headings "$tpl")
  [ "$tot" -gt 0 ] && STRUCT["$proj"]="${miss}/${tot}"
}

content_check() {
  local agents="$1" tpl="$2" proj; proj="$(dirname "$agents")"
  if [ "$CONTENT_CHECK" = "0" ]; then CONTENT["$proj"]="OFF"; return; fi
  local af; af="$(anchors_file "$tpl")"
  if [ ! -f "$af" ]; then CONTENT["$proj"]="NA"; return; fi

  local block="" warn="" kind sev label val
  while IFS='|' read -r kind sev label val; do
    case "$kind" in ''|'#'*) continue ;; esac
    [ -n "${val:-}" ] || continue
    case "$kind" in
      text)
        if ! grep -qF -- "$val" "$agents" 2>/dev/null; then
          if [ "$sev" = "blocker" ]; then block+="${label}｜${val}"$'\n'
          else warn+="${label}｜${val}"$'\n'; fi
        fi
        ;;
      docs)
        # 只在正文真的引用了该路径时才要求文件存在：正文没引用 = 老版本正文内联，
        # 属正常；正文引用了但文件不在 = 悬挂指针，规则静默失效。
        if grep -qF -- "$val" "$agents" 2>/dev/null && [ ! -f "$proj/$val" ]; then
          if [ "$sev" = "blocker" ]; then block+="${label}｜悬挂指针 ${val}"$'\n'
          else warn+="${label}｜悬挂指针 ${val}"$'\n'; fi
        fi
        ;;
    esac
  done < "$af"

  CONTENT_BLOCK["$proj"]="$block"
  CONTENT_WARN["$proj"]="$warn"
  if   [ -n "$block" ]; then CONTENT["$proj"]="MISS"
  elif [ -n "$warn" ];  then CONTENT["$proj"]="WARN"
  else                       CONTENT["$proj"]="OK"; fi
  struct_hint "$agents" "$tpl" "$proj"
}

content_label() {
  case "$1" in
    OK)   echo "✅ 齐全" ;;
    WARN) echo "○ 有提示" ;;
    MISS) echo "❗内容缺失" ;;
    NA)   echo "· 无清单" ;;
    OFF)  echo "· 已跳过" ;;
    *)    echo "·" ;;
  esac
}

# ---- 清单自检：锚点必须真实存在于模板自己的正文里 ----
# 否则「清单」会变成第二份真源：改了模板措辞却忘改清单时，
# 所有派生项目都会被误报缺失，告警可信度立刻归零。只写 stderr，不污染表格。
manifest_audit() {
  local d t af tplf kind sev label val
  for d in "$UPSTREAM"/templates/*/; do
    [ -d "$d" ] || continue
    t="$(basename "$d")"; af="$d/check-anchors.txt"; tplf="$d/AGENTS.md"
    if [ ! -f "$af" ]; then
      echo "⚠️  templates/$t/ 缺 check-anchors.txt —— 该模板跳过内容核验" >&2; continue
    fi
    [ -f "$tplf" ] || continue
    while IFS='|' read -r kind sev label val; do
      case "$kind" in ''|'#'*) continue ;; esac
      [ -n "${val:-}" ] || continue
      case "$kind" in
        text)
          grep -qF -- "$val" "$tplf" 2>/dev/null \
            || echo "⚠️  锚点清单失配：templates/$t 的「$label」= $val 在模板正文中找不到，请同步核对" >&2 ;;
        docs)
          [ -f "$d/$val" ] || echo "⚠️  锚点清单失配：templates/$t/$val 不存在（正文却可能引用它）" >&2 ;;
      esac
    done < "$af"
  done
}

[ "$CONTENT_CHECK" = "1" ] && manifest_audit

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
# 按锚点命中数猜模板：正文被重写时「来源」行常被一起丢掉，
# 但头部「模板版本」行多半留着——此时仍应按派生项目检查，不能静默跳过。
infer_template() {
  local agents="$1" best="" bestn=0 d t af n kind sev label val
  for d in "$UPSTREAM"/templates/*/; do
    [ -d "$d" ] || continue
    t="$(basename "$d")"; af="$d/check-anchors.txt"
    [ -f "$af" ] || continue
    n=0
    while IFS='|' read -r kind sev label val; do
      case "$kind" in
        text) [ -n "${val:-}" ] && grep -qF -- "$val" "$agents" 2>/dev/null && n=$((n+1)) ;;
      esac
    done < "$af"
    [ "$n" -gt "$bestn" ] && { bestn="$n"; best="$t"; }
  done
  [ "$bestn" -ge 2 ] && echo "$best"
}

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
    elif [ -n "$local_ver" ]; then
      # 有模板版本行却没了来源行 = 正文多半被重写过：按锚点反推模板，继续检查而不是跳过
      tpl_name="$(infer_template "$agents")"
      [ -n "$tpl_name" ] || tpl_name="未知"
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
  depth=3
  [ -n "$PROJECT" ] && depth=1
  while IFS= read -r agents; do
    proj_dir="$(dirname "$agents")"
    [ "$proj_dir" = "$UPSTREAM" ] && continue
    case "$proj_dir" in *agent-templates*) continue ;; esac
    IFS='|' read -r tpl local_ver status up_ver cnt <<< "$(inspect_project "$agents")"
    [ "$status" = "NOT_DERIVED" ] && continue
    content_check "$agents" "$tpl"
    ROWS+=("${proj_dir}|${tpl}|${local_ver}|${status}|${up_ver}|${cnt}")
  done < <(find "$root" -maxdepth "$depth" -name AGENTS.md -type f 2>/dev/null | sort)
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
# 内容缺失的行永不被过滤掉：版本号对得上但正文被重写，正是最该看见的情况。
passes() {
  local st="$1" cs="${2:-}"
  [ "$cs" = "MISS" ] && return 0
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
c_cok=0; c_cwarn=0; c_cmiss=0
for row in "${ROWS[@]}"; do
  IFS='|' read -r proj _ _ st _ _ <<< "$row"
  passes "$st" "${CONTENT[$proj]:-}" || continue
  c_total=$((c_total+1))
  case "${CONTENT[$proj]:-}" in
    OK)   c_cok=$((c_cok+1)) ;;
    WARN) c_cwarn=$((c_cwarn+1)) ;;
    MISS) c_cmiss=$((c_cmiss+1)) ;;
  esac
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
  echo "| 派生项目 | 模板 | 本地 | 上游 | 差几版 | 版本 | 内容 |"
  echo "|---|---|---|---|---|---|---|"
  for row in "${ROWS[@]}"; do
    IFS='|' read -r proj tpl local_ver st up_ver cnt <<< "$row"
    passes "$st" "${CONTENT[$proj]:-}" || continue
    echo "| \`$(basename "$proj")\` | ${tpl} | ${local_ver} | ${up_ver} | ${cnt} | $(label_of "$st") | $(content_label "${CONTENT[$proj]:-}") |"
  done
elif [ "$FORMAT" = "detail" ]; then
  for row in "${ROWS[@]}"; do
    IFS='|' read -r proj tpl local_ver st up_ver cnt <<< "$row"
    passes "$st" "${CONTENT[$proj]:-}" || continue
    cs="${CONTENT[$proj]:-}"
    echo "── $(basename "$proj")  [$proj]"
    echo "   模板：${tpl}  声明版本：${local_ver}  上游：${up_ver}  版本：$(label_of "$st")"
    echo "   内容：$(content_label "$cs")"
    if [ -n "${CONTENT_BLOCK[$proj]:-}" ]; then
      printf '%s' "${CONTENT_BLOCK[$proj]}" | while IFS= read -r l; do [ -n "$l" ] && echo "     ❗缺失（关键，须补）：$l"; done
    fi
    if [ -n "${CONTENT_WARN[$proj]:-}" ]; then
      printf '%s' "${CONTENT_WARN[$proj]}" | while IFS= read -r l; do [ -n "$l" ] && echo "     ○缺失（提示）：$l"; done
    fi
    if [ -n "${STRUCT[$proj]:-}" ]; then
      echo "   结构：章节标题缺 ${STRUCT[$proj]}（仅提示；缺失较多时疑似重写，请确认关键节未被丢弃）"
    fi
    if [ "$CONTENT_CHECK" = "1" ] && [ "$tpl" != "未知" ] && [ -d "$UPSTREAM/templates/$tpl/docs" ]; then
      echo "   上游 docs：$(cd "$UPSTREAM/templates/$tpl/docs" && echo *.md | tr ' ' ',')"
    fi
    echo
  done
else
  printf "%-40s %-16s %-8s %-8s %-5s %-14s %s\n" "派生项目" "模板" "本地" "上游" "差几版" "版本" "内容"
  printf '%.0s─' {1..110}; echo
  for row in "${ROWS[@]}"; do
    IFS='|' read -r proj tpl local_ver st up_ver cnt <<< "$row"
    passes "$st" "${CONTENT[$proj]:-}" || continue
    printf "%-40s %-16s %-8s %-8s %-5s %-14s %s\n" \
      "$(basename "$proj")" "$tpl" "$local_ver" "$up_ver" "$cnt" "$(label_of "$st")" "$(content_label "${CONTENT[$proj]:-}")"
  done
fi

echo
echo "扫描 ${c_total} 个：最新 ${c_current} · 落后patch ${c_patch} · 跨minor ${c_minor} · 跨major ${c_major} · 早于版本行 ${c_pre} · 领先 ${c_ahead}"
if [ "$CONTENT_CHECK" = "1" ]; then
  echo "内容核验：齐全 ${c_cok} · 有提示 ${c_cwarn} · ❗关键锚点缺失 ${c_cmiss}"
fi

# ---- 内容缺失明细（与「落后版本」分开列，两者含义不同）----
if [ "$c_cmiss" -gt 0 ] && [ "$FORMAT" != "detail" ]; then
  echo
  echo "❗关键锚点缺失（${c_cmiss} 个）——版本号对不对都不影响这条，缺了就是规则失效："
  for row in "${ROWS[@]}"; do
    IFS='|' read -r proj tpl local_ver st up_ver cnt <<< "$row"
    [ "${CONTENT[$proj]:-}" = "MISS" ] || continue
    while IFS= read -r l; do
      [ -n "$l" ] && echo "   $(basename "$proj")  →  $l"
    done <<< "${CONTENT_BLOCK[$proj]:-}"
  done
  echo "   修法：cd 到上游仓库跑 tools/sync-check.sh <该项目路径> 看完整差异，"
  echo "         再按上游同名节逐节补回（禁止整文件覆盖，禁止改已回填内容）。"
fi

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
  if [ "$c_cmiss" -gt 0 ]; then
    echo "    注意：内容缺失不享受传播期豁免——刚发版也不会让已有章节凭空补上。"
  fi
fi

# ---- 退出码 ----
# 2 = 关键锚点缺失（任何时期都算，不受传播期与 --stale 过滤影响）
# 1 = 传播期外且跨 minor/major
# 0 = 无问题（落后几个 patch 恒为 0）
if [ "$CONTENT_CHECK" = "1" ] && [ "$c_cmiss" -gt 0 ]; then exit 2; fi
if [ "$in_grace" = "1" ]; then exit 0; fi
[ $((c_minor + c_major)) -eq 0 ]
