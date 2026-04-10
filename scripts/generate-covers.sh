#!/usr/bin/env bash
set -euo pipefail

# 教程/视频封面批量生成器 V4.1
# 用法: ./generate-covers.sh --icon ICON_PNG --title "TITLE" [--subtitle "SUBTITLE"] [--primary COLOR] [--output-dir DIR]

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

# 文件名化简：取标题前 40 字符，替换特殊字符
SAFE_TITLE=$(echo "$TITLE" | tr -cd '[:alnum:] _-' | cut -c1-40)
[[ -z "$SAFE_TITLE" ]] && SAFE_TITLE="cover"

# 计算动态字号（按标题长度适配安全区）
# 输出格式: title_size\tsubtitle_size
compute_font_sizes() {
  local tmpl="$1"
  local title="$2"
  python3 << PYEOF
import sys

tmpl = "$tmpl"
title = """$title"""

# 模板参数: (safe_width_px, base_title, base_subtitle, min_ratio)
specs = {
    "youtube":            (720,  72,  32, 0.55),
    "bilibili":           (640,  68,  30, 0.55),
    "tutorial":           (1100, 120, 48, 0.55),
    "wordpress-official": (1300, 110, 44, 0.55),
    "podcast":            (2400, 140, 56, 0.55),
}

safe_w, base_title, base_subtitle, min_ratio = specs[tmpl]

# 判断文字类型
is_cjk = any(0x4e00 <= ord(c) <= 0x9fff for c in title)
ratio = 1.0 if is_cjk else 0.6

title_len = max(len(title.strip()), 1)
calc_title = int(safe_w / (title_len * ratio))
title_size = max(min(base_title, calc_title), int(base_title * min_ratio))

# 副标题取标题的 0.45 倍，但不超过 base_subtitle
subtitle_size = max(min(base_subtitle, int(title_size * 0.45)), int(base_subtitle * 0.6))

print(f"{title_size}\t{subtitle_size}")
PYEOF
}

TEMPLATES=("youtube" "bilibili" "tutorial" "podcast" "wordpress-official")

echo ""
echo "=== 封面生成: $TITLE ==="
echo ""

for tmpl in "${TEMPLATES[@]}"; do
  svg_in="$TEMPLATE_DIR/cover-${tmpl}.svg"
  svg_tmp="$OUTPUT_DIR/${SAFE_TITLE}_${tmpl}.svg"
  png_out="$OUTPUT_DIR/${SAFE_TITLE}_${tmpl}.png"

  IFS=$'\t' read -r TITLE_SIZE SUBTITLE_SIZE < <(compute_font_sizes "$tmpl" "$TITLE")

  sed \
    -e "s|{{PRIMARY}}|$PRIMARY|g" \
    -e "s|{{ICON_PNG}}|$ICON_PATH|g" \
    -e "s|{{WENPAI_LOGO_PNG}}|$WENPAI_LOGO_PNG|g" \
    -e "s|{{TITLE}}|$TITLE|g" \
    -e "s|{{SUBTITLE}}|$SUBTITLE|g" \
    -e "s|{{TITLE_SIZE}}|$TITLE_SIZE|g" \
    -e "s|{{SUBTITLE_SIZE}}|$SUBTITLE_SIZE|g" \
    "$svg_in" > "$svg_tmp"

  inkscape "$svg_tmp" --export-type=png --export-filename="$png_out" 2>/dev/null
  echo "  OK ${SAFE_TITLE}_${tmpl}.png (title=${TITLE_SIZE}px, subtitle=${SUBTITLE_SIZE}px)"
done

echo ""
echo "=== 生成完成 ==="
echo "输出目录: $OUTPUT_DIR"
find "$OUTPUT_DIR" -name "${SAFE_TITLE}_*.png" | wc -l | xargs -I{} echo "PNG 文件数: {}"
