#!/usr/bin/env bash
# 单个派生项目的内容同步检查：一条命令拿到「缺哪几节、缺哪几个 docs」。
#
# 用法：
#   tools/sync-check.sh ~/Projects/某派生项目
#   tools/sync-check.sh .                      # 当前目录（在派生项目里就地跑）
#   tools/sync-check.sh ~/x --no-content       # 只看版本（其余参数原样透传给 check-derived.sh）
#
# 与 check-derived.sh 的关系：本脚本只是它的 --project 模式入口，
# 检测逻辑只有一份，避免两个脚本各写一套判定而互相漂移。
#
# 退出码同 check-derived.sh：0 无问题 / 1 跨 minor-major / 2 关键锚点缺失。
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ $# -lt 1 ]; then
  sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 2
fi

case "$1" in
  -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
esac

target="$1"; shift
exec "$SELF_DIR/check-derived.sh" --project "$target" "$@"
