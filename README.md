# cover-pipeline

视频/教程封面批量生成器，基于 Inkscape + SVG 模板。

## 模板规格

| 模板 | 尺寸 | 用途 |
|------|------|------|
| youtube | 1280x720 | YouTube 视频封面 |
| bilibili | 1146x717 | Bilibili 视频封面 |
| tutorial | 1920x1080 | 教程/课程封面 |
| podcast | 3000x3000 | 播客专辑封面 |
| wordpress-official | 1920x1080 | WordPress 官方风格演示封面 |

## 用法

```bash
./scripts/generate-covers.sh \
  --icon assets/icon.png \
  --title "Basic WordPress Settings" \
  --subtitle "Online Workshop" \
  --primary "#4f46e5"
```

输出目录默认为 `output/covers/`。
