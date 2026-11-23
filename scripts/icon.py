"""App icon for Swish Alley (1024x1024, no alpha): a neon backboard, an orange rim with a net and a ball dropping
in, on a deep arcade-purple gradient with a warm floor glow. Usage: python -X utf8 scripts/icon.py"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

S = 4096  # supersampled
OUT = Path(__file__).resolve().parent.parent / 'SwishAlley' / 'Assets.xcassets' / 'AppIcon.appiconset' / 'icon-1024.png'


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def main():
    img = Image.new('RGB', (S, S))
    top, bottom = (44, 18, 82), (10, 6, 22)
    g = Image.new('RGB', (1, S))
    for y in range(S):
        g.putpixel((0, y), lerp(top, bottom, y / (S - 1)))
    img = g.resize((S, S))

    def glow(draw_fn, blur, alpha=1.0):
        layer = Image.new('RGBA', (S, S), (0, 0, 0, 0))
        draw_fn(ImageDraw.Draw(layer))
        blurred = layer.filter(ImageFilter.GaussianBlur(blur))
        if alpha < 1:
            a = blurred.split()[3].point(lambda v: int(v * alpha))
            blurred.putalpha(a)
        img.paste(blurred, (0, 0), blurred)

    # Warm floor glow.
    glow(lambda d: d.ellipse([S * 0.05, S * 0.78, S * 0.95, S * 1.25], fill=(255, 140, 60, 120)), S * 0.06)
    # Backboard: neon pink frame with a cyan inner square.
    bx0, by0, bx1, by1 = S * 0.2, S * 0.16, S * 0.8, S * 0.54
    pink, cyan = (255, 64, 164, 255), (55, 227, 255, 255)
    board = lambda d, w: d.rounded_rectangle([bx0, by0, bx1, by1], radius=S * 0.04, outline=pink, width=int(w))
    glow(lambda d: board(d, S * 0.035), S * 0.03)
    glow(lambda d: d.rounded_rectangle([bx0, by0, bx1, by1], radius=S * 0.04, fill=(255, 255, 255, 26)), 2)
    glow(lambda d: board(d, S * 0.018), 6)
    sq = [S * 0.38, S * 0.30, S * 0.62, S * 0.47]
    glow(lambda d: d.rectangle(sq, outline=cyan, width=int(S * 0.02)), S * 0.02)
    glow(lambda d: d.rectangle(sq, outline=(200, 250, 255, 255), width=int(S * 0.008)), 4)

    # Net (white cords) under the rim.
    rim_y, rim_rx, rim_ry = S * 0.56, S * 0.17, S * 0.045
    cx = S * 0.5
    def net(d):
        n = 9
        for i in range(n + 1):
            t = i / n
            x0 = cx - rim_rx + 2 * rim_rx * t
            x1 = cx - rim_rx * 0.6 + 2 * rim_rx * 0.6 * t
            d.line([(x0, rim_y), (x1 + (S * 0.03 if i % 2 else -S * 0.03), rim_y + S * 0.2)], fill=(245, 245, 255, 230), width=int(S * 0.008))
        for k in range(1, 4):
            yy = rim_y + S * 0.05 * k
            w = rim_rx * (1 - 0.13 * k)
            d.arc([cx - w, yy - rim_ry * 0.8, cx + w, yy + rim_ry * 0.8], 0, 180, fill=(245, 245, 255, 200), width=int(S * 0.007))
    glow(net, 3)

    # Ball dropping into the rim (drawn before the rim's front edge).
    br = S * 0.13
    bc = (cx + S * 0.02, rim_y - S * 0.06)
    def ball(d):
        d.ellipse([bc[0] - br, bc[1] - br, bc[0] + br, bc[1] + br], fill=(236, 112, 30, 255))
    glow(lambda d: d.ellipse([bc[0] - br * 1.25, bc[1] - br * 1.25, bc[0] + br * 1.25, bc[1] + br * 1.25], fill=(255, 150, 60, 110)), S * 0.03)
    glow(ball, 2)
    def seams(d):
        w = int(S * 0.012)
        col = (40, 18, 8, 255)
        d.arc([bc[0] - br, bc[1] - br, bc[0] + br, bc[1] + br], 0, 360, fill=col, width=w)
        d.line([(bc[0] - br, bc[1]), (bc[0] + br, bc[1])], fill=col, width=w)
        d.arc([bc[0] - br * 0.45, bc[1] - br, bc[0] + br * 0.45, bc[1] + br], 90, 270, fill=col, width=w)
        d.arc([bc[0] - br * 0.45, bc[1] - br, bc[0] + br * 0.45, bc[1] + br], 270, 90, fill=col, width=w)
        d.arc([bc[0] - br * 1.6, bc[1] - br * 0.9, bc[0] - br * 0.35, bc[1] + br * 0.9], 300, 60, fill=col, width=w)
        d.arc([bc[0] + br * 0.35, bc[1] - br * 0.9, bc[0] + br * 1.6, bc[1] + br * 0.9], 120, 240, fill=col, width=w)
    glow(seams, 2)
    # Highlight.
    glow(lambda d: d.ellipse([bc[0] - br * 0.6, bc[1] - br * 0.75, bc[0] - br * 0.05, bc[1] - br * 0.3], fill=(255, 220, 180, 90)), S * 0.012)

    # Rim: orange ring, front half drawn over the ball.
    rim = (255, 106, 31, 255)
    glow(lambda d: d.ellipse([cx - rim_rx, rim_y - rim_ry, cx + rim_rx, rim_y + rim_ry], outline=rim, width=int(S * 0.026)), S * 0.012)
    glow(lambda d: d.arc([cx - rim_rx, rim_y - rim_ry, cx + rim_rx, rim_y + rim_ry], 0, 180, fill=(255, 150, 80, 255), width=int(S * 0.03)), 3)

    # Neon floor line.
    glow(lambda d: d.line([(S * 0.1, S * 0.86), (S * 0.9, S * 0.86)], fill=cyan, width=int(S * 0.016)), S * 0.012)
    glow(lambda d: d.line([(S * 0.1, S * 0.86), (S * 0.9, S * 0.86)], fill=(210, 250, 255, 255), width=int(S * 0.006)), 3)

    out = img.resize((1024, 1024), Image.LANCZOS).convert('RGB')
    OUT.parent.mkdir(parents=True, exist_ok=True)
    out.save(OUT)
    out.resize((256, 256), Image.LANCZOS).save(Path(__file__).resolve().parent.parent / 'docs' / 'icon.png')
    print('saved', OUT)


if __name__ == '__main__':
    main()
