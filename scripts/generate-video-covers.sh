#!/usr/bin/env bash
set -euo pipefail

# 视频帧封面生成器
# 从视频中提取关键帧，质量评分后生成多平台封面
# 用法: ./generate-video-covers.sh [选项] <视频文件>

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="$PROJECT_DIR/output/video-covers"

require_cmd() {
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null 2>&1 || { echo "需要 $cmd，请先安装" >&2; exit 1; }
    done
}

get_duration() {
    ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null | cut -d. -f1
}

usage() {
    cat << 'EOF'
用法: generate-video-covers.sh [选项] <视频文件>

选项:
    -o, --output-dir DIR   输出目录 (默认: output/video-covers/)
    -p, --platform PLAT    目标平台 (默认: all)
    --title TEXT           封面标题文字
    --method METHOD        关键帧提取: scene | interval (默认: scene)
    --candidates N         候选帧数量 (默认: 10)
    --dry-run              只显示操作
    -h, --help             显示帮助

平台:
    youtube, bilibili, douyin, xiaohongshu, wechat, podcast
EOF
    exit 1
}

# 默认值
INPUT=""
TITLE=""
PLATFORMS="all"
METHOD="scene"
CANDIDATES=10
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -p|--platform)   PLATFORMS="$2"; shift 2 ;;
        --title)         TITLE="$2"; shift 2 ;;
        --method)        METHOD="$2"; shift 2 ;;
        --candidates)    CANDIDATES="$2"; shift 2 ;;
        --dry-run)       DRY_RUN=true; shift ;;
        -h|--help)       usage ;;
        *)               INPUT="$1"; shift ;;
    esac
done

[[ -z "$INPUT" ]] && { echo "错误: 请指定输入视频" >&2; usage; }
[[ -f "$INPUT" ]] || { echo "错误: 文件不存在: $INPUT" >&2; exit 1; }
require_cmd ffmpeg ffprobe convert

mkdir -p "$OUTPUT_DIR"

VIDEO_NAME=$(basename "${INPUT%.*}")
FRAMES_DIR="$OUTPUT_DIR/${VIDEO_NAME}_frames"
mkdir -p "$FRAMES_DIR"

# --- Step 1: 提取候选帧 ---
if $DRY_RUN; then
    echo "[dry-run] 将提取 $CANDIDATES 张候选帧"
else
    case "$METHOD" in
        scene)
            ffmpeg -y -i "$INPUT" \
                -vf "select='gt(scene,0.3)',showinfo" \
                -vsync vfr -frames:v "$CANDIDATES" \
                "$FRAMES_DIR/frame_%04d.jpg" -loglevel warning 2>&1 || true
            ;;
        interval)
            local interval
            interval=$(get_duration "$INPUT")
            interval=$(( interval / (CANDIDATES + 1) ))
            [[ $interval -lt 5 ]] && interval=5
            ffmpeg -y -i "$INPUT" \
                -vf "fps=1/$interval" \
                -frames:v "$CANDIDATES" \
                "$FRAMES_DIR/frame_%04d.jpg" -loglevel warning 2>&1 || true
            ;;
    esac

    FRAME_COUNT=$(ls "$FRAMES_DIR"/frame_*.jpg 2>/dev/null | wc -l)
    if [[ $FRAME_COUNT -eq 0 ]]; then
        echo "场景检测未提取到帧，回退到固定间隔模式"
        DURATION=$(get_duration "$INPUT")
        INTERVAL=$(( DURATION / (CANDIDATES + 1) ))
        [[ $INTERVAL -lt 5 ]] && INTERVAL=5
        ffmpeg -y -i "$INPUT" \
            -vf "fps=1/$INTERVAL" \
            -frames:v "$CANDIDATES" \
            "$FRAMES_DIR/frame_%04d.jpg" -loglevel warning 2>&1 || true
        FRAME_COUNT=$(ls "$FRAMES_DIR"/frame_*.jpg 2>/dev/null | wc -l)
    fi
    echo "提取到 $FRAME_COUNT 张候选帧"
fi

# --- Step 2: 质量评分 → 选最佳帧 ---
if $DRY_RUN; then
    BEST_FRAME="$FRAMES_DIR/frame_0001.jpg"
else
    BEST_FRAME=$(FRAMES_DIR="$FRAMES_DIR" python3 << 'PYEOF'
import os, sys, subprocess

frames_dir = os.environ["FRAMES_DIR"]
scores = []

for f in sorted(os.listdir(frames_dir)):
    if not f.endswith('.jpg'): continue
    path = os.path.join(frames_dir, f)
    try:
        result = subprocess.run(
            ["convert", path, "-colorspace", "Gray", "-convolve", "0,-1,0,-1,4,-1,0,-1,0",
             "-format", "%[fx:standard_deviation]", "info:"],
            capture_output=True, text=True, timeout=10
        )
        sharpness = float(result.stdout.strip()) if result.stdout.strip() else 0
    except Exception:
        sharpness = 0
    try:
        result = subprocess.run(
            ["convert", path, "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"],
            capture_output=True, text=True, timeout=10
        )
        brightness = float(result.stdout.strip()) if result.stdout.strip() else 0.5
    except Exception:
        brightness = 0.5
    brightness_score = 1.0 - abs(brightness - 0.5) * 2
    score = sharpness * 0.7 + brightness_score * 0.3
    scores.append((score, path, sharpness, brightness))

scores.sort(reverse=True)
if scores:
    print(scores[0][1])
    for i, (s, p, sh, br) in enumerate(scores[:5]):
        sys.stderr.write(f"  #{i+1} {os.path.basename(p)}: score={s:.4f} sharp={sh:.4f} bright={br:.2f}\n")
else:
    for f in sorted(os.listdir(frames_dir)):
        if f.endswith('.jpg'):
            print(os.path.join(frames_dir, f))
            break
PYEOF
)
    echo "最佳帧: $(basename "$BEST_FRAME")"
fi

# --- Step 3: 多比例裁切 + 文字叠加 ---
declare -A COVER_SPECS
COVER_SPECS[youtube]="1280:720"
COVER_SPECS[bilibili]="1146:717"
COVER_SPECS[douyin]="1080:1920"
COVER_SPECS[xiaohongshu]="1080:1440"
COVER_SPECS[wechat]="1080:1920"
COVER_SPECS[podcast]="3000:3000"

TARGET_PLATS=()
if [[ "$PLATFORMS" == "all" ]]; then
    TARGET_PLATS=(youtube bilibili douyin xiaohongshu wechat podcast)
else
    IFS=',' read -ra TARGET_PLATS <<< "$PLATFORMS"
fi

FONT="/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
FONTSIZE=72
TITLE_COLOR="white"
STROKE_COLOR="black"
STROKE_WIDTH=3

for plat in "${TARGET_PLATS[@]}"; do
    spec="${COVER_SPECS[$plat]:-1280:720}"
    w="${spec%%:*}"
    h="${spec##*:}"
    out_file="$OUTPUT_DIR/${VIDEO_NAME}_cover_${plat}_${w}x${h}.jpg"

    if $DRY_RUN; then
        echo "[dry-run] $plat: ${w}x${h} → $out_file"
        continue
    fi

    convert "$BEST_FRAME" \
        -resize "${w}x${h}^" \
        -gravity center \
        -extent "${w}x${h}" \
        -quality 95 \
        "$out_file"

    if [[ -n "$TITLE" ]]; then
        adjusted_size=$((FONTSIZE * w / 1280))
        [[ $adjusted_size -lt 24 ]] && adjusted_size=24

        convert "$out_file" \
            -font "$FONT" \
            -pointsize "$adjusted_size" \
            -fill "$TITLE_COLOR" \
            -stroke "$STROKE_COLOR" \
            -strokewidth "$STROKE_WIDTH" \
            -gravity south \
            -annotate +0+$((h/10)) "$TITLE" \
            "$out_file"
    fi

    size_kb=$(( $(stat -c%s "$out_file" 2>/dev/null || echo 0) / 1024 ))
    echo "OK $plat: ${w}x${h} (${size_kb} KB)"
done

rm -rf "$FRAMES_DIR"
echo "封面生成完成: $OUTPUT_DIR"
