#!/usr/bin/env bash
set -euo pipefail

# 教程/视频封面批量生成器 — 沿用 V4 设计语言
# 用法: ./generate-covers.sh --icon ICON_PNG --title "TITLE" [--primary COLOR] [--output-dir DIR]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE_DIR="$PROJECT_DIR/templates/covers"
OUTPUT_DIR="$PROJECT_DIR/output/covers"
WENPAI_LOGO_PNG="$(realpath "$PROJECT_DIR/assets/wenpai-logo.png")"

ICON_PATH=""
TITLE=""
SUBTITLE=""
PRIMARY="#4f46e5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --icon)        ICON_PATH="$2"; shift 2 ;;
    --title)       TITLE="$2"; shift 2 ;;
    --subtitle)    SUBTITLE="$2"; shift 2 ;;
    --primary)     PRIMARY="$2"; shift 2 ;;
    --output-dir)  OUTPUT_DIR="$2"; shift 2 ;;
    -h|--help)
      echo "用法: $0 --icon ICON_PNG --title \"TITLE\" [--subtitle \"SUBTITLE\"] [--primary COLOR] [--output-dir DIR]"
      exit 0
      ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

if [[ -z "$ICON_PATH" || -z "$TITLE" ]]; then
  echo "错误: --icon 和 --title 必须提供" >&2
  echo "用法: $0 --icon ICON_PNG --title \"TITLE\" [--subtitle \"SUBTITLE\"] [--primary COLOR] [--output-dir DIR]" >&2
  exit 1
fi

if [[ ! -f "$ICON_PATH" ]]; then
  echo "错误: 图标文件不存在: $ICON_PATH" >&2
  exit 1
fi

for cmd in inkscape; do
  command -v "$cmd" >/dev/null || { echo "缺少依赖: $cmd"; exit 1; }
done

ICON_PATH="$(realpath "$ICON_PATH")"
mkdir -p "$OUTPUT_DIR"

# 文件名化简：取标题前 20 字符，替换特殊字符
SAFE_TITLE=$(echo "$TITLE" | tr -cd '[:alnum:] _-' | cut -c1-40)
[[ -z "$SAFE_TITLE" ]] && SAFE_TITLE="cover"

TEMPLATES=("youtube" "bilibili" "tutorial" "podcast" "wordpress-official")

echo ""
echo "=== 封面生成: $TITLE ==="
echo ""

for tmpl in "${TEMPLATES[@]}"; do
  svg_in="$TEMPLATE_DIR/cover-${tmpl}.svg"
  svg_tmp="$OUTPUT_DIR/${SAFE_TITLE}_${tmpl}.svg"
  png_out="$OUTPUT_DIR/${SAFE_TITLE}_${tmpl}.png"

  sed \
    -e "s|{{PRIMARY}}|$PRIMARY|g" \
    -e "s|{{ICON_PNG}}|$ICON_PATH|g" \
    -e "s|{{WENPAI_LOGO_PNG}}|$WENPAI_LOGO_PNG|g" \
    -e "s|{{TITLE}}|$TITLE|g" \
    -e "s|{{SUBTITLE}}|$SUBTITLE|g" \
    "$svg_in" > "$svg_tmp"

  inkscape "$svg_tmp" --export-type=png --export-filename="$png_out" 2>/dev/null
  echo "  OK ${SAFE_TITLE}_${tmpl}.png"
done

echo ""
echo "=== 生成完成 ==="
echo "输出目录: $OUTPUT_DIR"
find "$OUTPUT_DIR" -name "${SAFE_TITLE}_*.png" | wc -l | xargs -I{} echo "PNG 文件数: {}"
