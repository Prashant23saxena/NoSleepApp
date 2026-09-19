#!/usr/bin/env python3
"""
generate_dmg_background.py
Generates a pristine, Apple-grade light silver DMG installer background.
Features subtle frosted cards, clean typography, and a refined directional arrow.
"""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

def create_dmg_background(output_path="assets/dmg_background.png"):
    # Window dimensions in points: 660 x 420
    # Retina resolution @2x: 1320 x 840
    width = 1320
    height = 840

    # 1. Apple-grade Silver/Platinum Canvas (#F8F9FB to #EBF0F7)
    base = Image.new("RGBA", (width, height), (255, 255, 255, 255))
    draw_base = ImageDraw.Draw(base)

    for y in range(height):
        ratio = y / height
        # Very gentle, elegant transition from clean bright silver to soft slate
        r = int(248 - (248 - 235) * (ratio ** 1.1))
        g = int(249 - (249 - 240) * (ratio ** 1.1))
        b = int(252 - (252 - 247) * (ratio ** 1.1))
        draw_base.line([(0, y), (width, y)], fill=(r, g, b, 255))

    # Outer 1px subtle boundary border
    draw_base.rectangle([(0, 0), (width - 1, height - 1)], outline=(218, 224, 233, 255), width=2)

    # 2. Font Loader
    def get_font(size, bold=False):
        candidates = [
            "/System/Library/Fonts/SFCompact.ttf",
            "/System/Library/Fonts/Helvetica.ttc",
            "/System/Library/Fonts/Supplemental/Arial.ttf"
        ]
        for p in candidates:
            if os.path.exists(p):
                try:
                    return ImageFont.truetype(p, size)
                except Exception:
                    continue
        return ImageFont.load_default()

    font_title = get_font(56, bold=True)
    font_sub = get_font(28)
    font_badge = get_font(22, bold=True)
    font_hint = get_font(24)

    # 3. Header Text (Dark Charcoal #111827 & Muted Slate #4B5563)
    title_text = "Install NoSleepApp"
    bbox_title = draw_base.textbbox((0, 0), title_text, font=font_title)
    w_title = bbox_title[2] - bbox_title[0]
    draw_base.text(((width - w_title) // 2, 72), title_text, font=font_title, fill=(17, 24, 39, 255))

    sub_text = "Drag the app into Applications to complete installation"
    bbox_sub = draw_base.textbbox((0, 0), sub_text, font=font_sub)
    w_sub = bbox_sub[2] - bbox_sub[0]
    draw_base.text(((width - w_sub) // 2, 142), sub_text, font=font_sub, fill=(75, 85, 99, 255))

    # 4. Soft Frosted Cards behind the icons (Centering at 160 & 500 points -> 320 & 1000 in @2x)
    # Icon size is 120 points (240 in @2x).
    # Card size: 280 x 280 in @2x, radius: 48
    cx_left = 320
    cx_right = 1000
    cy_icons = 390
    card_size = 280

    # Draw ambient shadows behind cards
    shadow_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_shadow = ImageDraw.Draw(shadow_layer)

    for cx in (cx_left, cx_right):
        shadow_box = [
            cx - card_size // 2, cy_icons - card_size // 2 + 8,
            cx + card_size // 2, cy_icons + card_size // 2 + 8
        ]
        draw_shadow.rounded_rectangle(shadow_box, radius=48, fill=(0, 0, 0, 28))

    shadow_blurred = shadow_layer.filter(ImageFilter.GaussianBlur(radius=16))
    base = Image.alpha_composite(base, shadow_blurred)

    # Draw the white frosted cards
    card_layer = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_card = ImageDraw.Draw(card_layer)

    for cx in (cx_left, cx_right):
        card_box = [
            cx - card_size // 2, cy_icons - card_size // 2,
            cx + card_size // 2, cy_icons + card_size // 2
        ]
        # Crisp white card with clean border
        draw_card.rounded_rectangle(card_box, radius=48, fill=(255, 255, 255, 235), outline=(226, 232, 240, 255), width=2)

    # 5. Clean Connecting Directional Arrow
    # Spans between cx_left and cx_right: from x = 490 to x = 830, cy = 390
    arrow_start_x = 490
    arrow_end_x = 830
    arrow_y = cy_icons

    # Subtle arrow glow / drop shadow
    draw_card.line([(arrow_start_x, arrow_y + 3), (arrow_end_x - 24, arrow_y + 3)], fill=(0, 0, 0, 18), width=6)

    # Crisp vibrant Emerald / Teal arrow shaft
    draw_card.line([(arrow_start_x, arrow_y), (arrow_end_x - 24, arrow_y)], fill=(16, 185, 129, 255), width=5)

    # Arrowhead
    head_len = 32
    head_h = 20
    arrowhead = [
        (arrow_end_x, arrow_y),
        (arrow_end_x - head_len, arrow_y - head_h),
        (arrow_end_x - head_len * 0.72, arrow_y),
        (arrow_end_x - head_len, arrow_y + head_h)
    ]
    draw_card.polygon(arrowhead, fill=(16, 185, 129, 255))

    # Badge above arrow: "DRAG & DROP"
    badge_text = "DRAG & DROP"
    bbox_badge = draw_card.textbbox((0, 0), badge_text, font=font_badge)
    w_badge = bbox_badge[2] - bbox_badge[0]
    badge_cx = (arrow_start_x + arrow_end_x) // 2
    badge_cy = arrow_y - 62
    badge_box = [
        badge_cx - w_badge // 2 - 18, badge_cy - 14,
        badge_cx + w_badge // 2 + 18, badge_cy + 22
    ]
    draw_card.rounded_rectangle(badge_box, radius=16, fill=(255, 255, 255, 250), outline=(16, 185, 129, 220), width=2)
    draw_card.text((badge_cx - w_badge // 2, badge_cy - 10), badge_text, font=font_badge, fill=(5, 150, 105, 255))

    # 6. Footer Hint
    hint_text = "Or double-click NoSleepApp to install automatically"
    bbox_hint = draw_card.textbbox((0, 0), hint_text, font=font_hint)
    w_hint = bbox_hint[2] - bbox_hint[0]
    draw_card.text(((width - w_hint) // 2, 735), hint_text, font=font_hint, fill=(107, 114, 128, 255))

    # Composite final image
    final_img = Image.alpha_composite(base, card_layer)
    
    os.makedirs(os.path.dirname(output_path) if os.path.dirname(output_path) else ".", exist_ok=True)
    final_img.convert("RGB").save(output_path, "PNG", dpi=(144, 144))
    print(f"✅ Generated Apple-grade Light DMG background at: {output_path} ({width}x{height} @ 144 DPI)")

    # Also save 1x version
    img_1x = final_img.resize((660, 420), Image.Resampling.LANCZOS)
    path_1x = output_path.replace(".png", "_1x.png")
    img_1x.convert("RGB").save(path_1x, "PNG", dpi=(72, 72))

if __name__ == "__main__":
    import sys
    out = sys.argv[1] if len(sys.argv) > 1 else "assets/dmg_background.png"
    create_dmg_background(out)
