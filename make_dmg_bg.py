#!/usr/bin/env python3
"""
Generate a clean, minimalist, Retina-sharp DMG background for PodQuick.
Supports macOS Retina displays via multi-resolution TIFF (1x and 2x).
"""
import os
import subprocess
from PIL import Image, ImageDraw, ImageFont, ImageFilter

def render_canvas(scale=1):
    w, h = 660 * scale, 420 * scale
    img = Image.new("RGBA", (w, h), (255, 255, 255, 255))
    draw = ImageDraw.Draw(img)

    # 1. Subtle, elegant light gradient
    for y in range(h):
        progress = y / h
        r = int(248 - 14 * progress)
        g = int(249 - 13 * progress)
        b = int(251 - 12 * progress)
        draw.line([(0, y), (w, y)], fill=(r, g, b, 255))

    # 1px border around the window
    draw.rectangle([(0, 0), (w - 1, h - 1)], outline=(220, 224, 230, 255), width=1 * scale)

    # 2. Center Drag Guide between PodQuick (x=175) and Applications (x=485)
    center_x = 330 * scale
    center_y = 205 * scale

    # Pill container dimensions
    pill_w = 114 * scale
    pill_h = 46 * scale
    px1 = center_x - pill_w // 2
    py1 = center_y - pill_h // 2
    px2 = center_x + pill_w // 2
    py2 = center_y + pill_h // 2
    corner_radius = 14 * scale

    # Soft drop shadow for the pill
    shadow_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shadow_layer)
    s_draw.rounded_rectangle(
        [(px1, py1 + 2 * scale), (px2, py2 + 3 * scale)],
        radius=corner_radius,
        fill=(0, 0, 0, 16)
    )
    shadow_layer = shadow_layer.filter(ImageFilter.GaussianBlur(3 * scale))
    img = Image.alpha_composite(img, shadow_layer)
    draw = ImageDraw.Draw(img)

    # Pill white card
    draw.rounded_rectangle(
        [(px1, py1), (px2, py2)],
        radius=corner_radius,
        fill=(255, 255, 255, 245),
        outline=(218, 222, 228, 255),
        width=1 * scale
    )

    # Clean modern arrow pointing right
    arrow_color = (0, 113, 227, 245) # Apple Blue
    arrow_y = center_y - 7 * scale
    line_start_x = center_x - 18 * scale
    line_end_x = center_x + 14 * scale
    line_width = max(2, int(2.5 * scale))

    draw.line([(line_start_x, arrow_y), (line_end_x, arrow_y)], fill=arrow_color, width=line_width)

    # Arrow head
    head_size = int(5.5 * scale)
    draw.line([(line_end_x - head_size, arrow_y - head_size), (line_end_x, arrow_y)], fill=arrow_color, width=line_width)
    draw.line([(line_end_x - head_size, arrow_y + head_size), (line_end_x, arrow_y)], fill=arrow_color, width=line_width)

    # Label text: "拖拽安装"
    font_path_pingfang = "/System/Library/Fonts/PingFang.ttc"
    try:
        label_font = ImageFont.truetype(font_path_pingfang, 11 * scale, index=2) # Medium
    except Exception:
        label_font = ImageFont.load_default()

    label_text = "拖拽安装"
    bbox = draw.textbbox((0, 0), label_text, font=label_font)
    text_w = bbox[2] - bbox[0]
    draw.text((center_x - text_w // 2, center_y + 4 * scale), label_text, font=label_font, fill=(110, 115, 125, 240))

    return img.convert("RGB")

def create_dmg_background():
    os.makedirs("assets", exist_ok=True)
    
    # 1. Render 1x and 2x versions
    img_1x = render_canvas(scale=1)
    img_2x = render_canvas(scale=2)
    
    tmp_1x = "/tmp/dmg_bg_1x.tiff"
    tmp_2x = "/tmp/dmg_bg_2x.tiff"
    tiff_out = "assets/dmg_background.tiff"
    png_out = "assets/dmg_background.png"
    
    img_1x.save(tmp_1x)
    img_2x.save(tmp_2x)
    
    # Save standard PNG
    img_1x.save(png_out, "PNG", dpi=(72, 72))
    
    # 2. Combine into Retina multi-resolution TIFF
    cmd = ["tiffutil", "-cathidpicheck", tmp_1x, tmp_2x, "-out", tiff_out]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode == 0:
        print(f"✓ Created Retina multi-resolution background: {tiff_out}")
    else:
        print(f"⚠️ tiffutil error: {res.stderr}")
        
    print(f"✓ Created fallback PNG background: {png_out}")

if __name__ == "__main__":
    create_dmg_background()
