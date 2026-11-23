"""App Store screenshots for Swish Alley.

Usage: python -X utf8 scripts/compose-screens.py <raw-dir> <out-dir> <iphone|ipad|duo-outer|duo-inner> [--fold] [--rotate 90|-90]

iPhone, iPad and the folded iPhone Duo: headline, subline and the simulator screenshot on a warm arcade gradient.

iPhone Duo inner display: the app ran half open with a simulated viewer eye and wrote <name>.json (eye, hinge,
window and fold in points). The two halves of the raw screenshot are drawn onto a half-open iPhone Duo seen from
exactly that eye; because the app rendered each half with an off-axis projection from that eye, the hoop stands up
out of the phone in the picture. With --fold a dashed line marks the fold and an "iPhone Duo" label names it. The
duel shot (phone flat) is shown flat with the fold marked as the centre line.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BOLD = 'C:/Windows/Fonts/segoeuib.ttf'
SEMI = 'C:/Windows/Fonts/segoeui.ttf'

# raw name → (title, subtitle on Duo, subtitle elsewhere)
TEXT = {
    '1-stage': ('Basketball on the fold', 'Stand iPhone Duo half open: the hoop pops out', ''),
    '2-fire': ('Get on fire', 'Three in a row and every basket is worth 3', 'Three in a row and every basket is worth 3'),
    '3-final': ('Last 10 seconds: double!', 'Every basket counts twice and the hoop moves', ''),
    '4-duel': ('Face-to-face duel', 'Open it flat: one half each, free forever', ''),
    '5-menu': ('Flick to shoot', 'Speed sets the power, direction sets the aim', ''),
    '1-play': ('Flick to shoot', 'Arcade basketball in 60-second rounds', 'Arcade basketball in 60-second rounds'),
    '3-duel': ('Face-to-face duel', 'Two players, one phone, free forever', 'Two players, one phone, free forever'),
    '4-results': ('Beat your best', 'One more run? Always one more run', 'One more run? Always one more run'),
    '5-locker': ('Neon arenas and balls', 'A warm retro arcade, original look and music', 'A warm retro arcade, original look and music'),
    '6-paywall': ('Free, no ads', 'Pro is a one-time thank-you, no subscription', 'Pro is a one-time thank-you, no subscription'),
}
ORDER_DUO_INNER = ['1-stage', '2-fire', '3-final', '4-duel', '5-menu']
ORDER_OTHER = ['1-play', '2-fire', '3-duel', '4-results', '5-locker']
ORDER_DUO_OUTER = ['1-play', '3-duel', '4-results']


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.truetype('C:/Windows/Fonts/arial.ttf', size)


def gradient(w, h, top=(46, 16, 64), bottom=(10, 5, 18)):
    g = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    img = g.resize((w, h))
    glow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w * 0.1, h * 0.55, w * 0.9, h * 1.2], fill=(255, 130, 60, 60))
    glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
    img.paste(glow, (0, 0), glow)
    return img


def headline(canvas, title, sub, k, y, width=None, x=None):
    d = ImageDraw.Draw(canvas)
    w = width or canvas.size[0]
    f1, f2 = font(BOLD, int(98 * k)), font(SEMI, int(54 * k))
    while d.textlength(title, font=f1) > w - 120 * k and f1.size > 40:
        f1 = font(BOLD, f1.size - 4)
    while sub and d.textlength(sub, font=f2) > w - 120 * k and f2.size > 28:
        f2 = font(SEMI, f2.size - 2)
    x0 = x if x is not None else 0
    for text, f, fill, gap in ((title, f1, (255, 244, 230), 22 * k), (sub, f2, (255, 120, 190), 0)):
        if not text:
            continue
        tw = d.textlength(text, font=f)
        d.text((x0 + (w - tw) / 2, y), text, font=f, fill=fill)
        y += f.size + gap + 14 * k
    return y


def rounded(img, r):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), r, fill=255)
    out = Image.new('RGBA', img.size)
    out.paste(img, (0, 0), mask)
    return out


def framed(canvas, shot, top, k, max_h=None):
    w, h = canvas.size
    sh = min(max_h or int(h * 0.8), h - top - int(50 * k))
    sw = int(sh * shot.size[0] / shot.size[1])
    if sw > w * 0.9:
        sw = int(w * 0.9)
        sh = int(sw * shot.size[1] / shot.size[0])
    r = int(min(sw, sh) * 0.06)
    x = (w - sw) // 2
    pad = int(60 * k)
    shadow = Image.new('RGBA', (sw + 2 * pad, sh + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + 12, sw + pad, sh + pad + 12), r + 10, fill=(0, 0, 0, 170))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(int(34 * k))), (x - pad, top - pad))
    b = max(6, int(9 * k))
    border = Image.new('RGBA', (sw + 2 * b, sh + 2 * b), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((0, 0, sw + 2 * b - 1, sh + 2 * b - 1), r + b, fill=(22, 24, 32, 255))
    canvas.alpha_composite(border, (x - b, top - b))
    canvas.alpha_composite(rounded(shot.resize((sw, sh), Image.LANCZOS).convert('RGB'), r), (x, top))


def compose_flat(raw, title, sub, out):
    shot = Image.open(raw).convert('RGB')
    w, h = shot.size
    k = min(w, h) / 1206 * (1 if h >= w else 0.8)
    canvas = gradient(w, h).convert('RGBA')
    y = headline(canvas, title, sub, k, int(150 * k) if h > w else int(80 * k))
    framed(canvas, shot, int(y + 70 * k), k)
    canvas.convert('RGB').save(out, optimize=True)


# ---------- half-open hologram mockup ----------

def coeffs(src, dst):
    A, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()


def warp(img, quad, size):
    w, h = img.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]   # TL, TR, BR, BL
    out = img.convert('RGBA').transform(size, Image.PERSPECTIVE, coeffs(src, quad), Image.BICUBIC)
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).polygon(quad, fill=255)
    out.putalpha(mask)
    return out


def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = np.array(eye, float), np.array(target, float), np.array(up, float)
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, r, u, f


def project(p, cam, focal, cx, cy):
    eye, r, u, f = cam
    d = np.array(p, float) - eye
    z = d @ f
    return (cx + focal * (d @ r) / z, cy - focal * (d @ u) / z)


def compose_stage(raw_path, meta_path, title, sub, out, rotate, fold_mark=True):
    m = json.load(open(meta_path))
    raw = Image.open(raw_path).convert('RGB')
    if rotate:
        raw = raw.rotate(rotate, expand=True)
    win_w, win_h = m['size']
    fx, fy, fw, fh = m['fold']
    s = raw.size[0] / win_w
    upper_img = raw.crop((0, 0, raw.size[0], int(fy * s)))
    lower_img = raw.crop((0, int((fy + fh) * s), raw.size[0], raw.size[1]))
    hinge = math.radians(m['hinge'])
    uw, uh = m['upper']
    lw, lh = m['lower']
    udir = np.array([0, math.sin(hinge), math.cos(hinge)])
    # Corners (TL, TR, BR, BL as seen in each half's image).
    U = [np.array([-uw / 2, 0, 0]) + udir * uh, np.array([uw / 2, 0, 0]) + udir * uh, np.array([uw / 2, 0, 0]), np.array([-uw / 2, 0, 0])]
    L = [np.array([-lw / 2, 0, 0]), np.array([lw / 2, 0, 0]), np.array([lw / 2, 0, lh]), np.array([-lw / 2, 0, lh])]

    W, H = 2853, 2007
    canvas = gradient(W, H).convert('RGBA')
    k = H / 1206 * 0.8
    # Text on the left third, device on the right two thirds.
    text_w = int(W * 0.36)
    headline_y = int(H * 0.36)
    # Viewer camera at the simulated eye, looking at the middle of the stage.
    cam = look_at(m['eye'], (0, 0.028, 0.012))
    pts = [project(p, cam, 1, 0, 0) for p in U + L]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    avail_w, avail_h = W - text_w - 120, H * 0.86
    focal = min(avail_w / (max(xs) - min(xs)), avail_h / (max(ys) - min(ys)))
    cx = text_w + 40 + avail_w / 2 - focal * (max(xs) + min(xs)) / 2
    cy = H * 0.5 - focal * (max(ys) + min(ys)) / 2
    P = lambda p: project(p, cam, focal, cx, cy)

    # Table shadow under the lower half, then bezels, then screens.
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    grow = 0.012
    Lb = [L[0] + [-grow, 0, -grow], L[1] + [grow, 0, -grow], L[2] + [grow, 0, grow], L[3] + [-grow, 0, grow]]
    ImageDraw.Draw(sh).polygon([P(p + [0, -0.002, 0.01]) for p in Lb], fill=(0, 0, 0, 200))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(40)))
    bez = 0.0035
    Ub = [U[0] + [-bez, 0, 0] + udir * bez, U[1] + [bez, 0, 0] + udir * bez, U[2] + [bez, 0, 0], U[3] + [-bez, 0, 0]]
    Lbz = [L[0] + [-bez, 0, 0], L[1] + [bez, 0, 0], L[2] + [bez, 0, bez], L[3] + [-bez, 0, bez]]
    dev = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dev)
    dd.polygon([P(p - udir * 0.0005 + np.array([0, 0, -0.0015])) for p in Ub], fill=(28, 30, 38, 255))
    dd.polygon([P(p + np.array([0, -0.0015, 0])) for p in Lbz], fill=(34, 36, 46, 255))
    canvas.alpha_composite(dev)
    canvas.alpha_composite(warp(upper_img, [P(p) for p in U], (W, H)))
    canvas.alpha_composite(warp(lower_img, [P(p) for p in L], (W, H)))
    if fold_mark:
        a, b = np.array(P(U[3])), np.array(P(U[2]))
        dashed_fold(canvas, a, b, k, 'iPhone Duo')
    headline(canvas, title, sub, k * 0.95, headline_y, width=text_w, x=40)
    canvas.convert('RGB').save(out, optimize=True)


def dashed_fold(canvas, a, b, k, label):
    """A dashed white line along the fold from a to b, and a pill label at its right end."""
    W, H = canvas.size
    over = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    n = 28
    for i in range(n):
        if i % 2 == 0:
            p0, p1 = a + (b - a) * i / n, a + (b - a) * (i + 1) / n
            od.line([tuple(p0), tuple(p1)], fill=(0, 0, 0, 110), width=11)
            od.line([tuple(p0), tuple(p1)], fill=(255, 255, 255, 235), width=6)
    f = font(BOLD, int(42 * k))
    tw = od.textlength(label, font=f)
    lx = min(W - tw - 70, b[0] - tw * 0.15)
    ly = b[1] + 30
    od.rounded_rectangle((lx - 22, ly - 8, lx + tw + 22, ly + f.size + 20), radius=(f.size + 28) / 2, fill=(255, 255, 255, 240))
    od.text((lx, ly), label, font=f, fill=(40, 18, 60, 255))
    canvas.alpha_composite(over)


def compose_duel(raw_path, meta_path, title, sub, out, fold_mark):
    """The duel: the inner display flat, turned so the two players sit left and right, fold marked."""
    m = json.load(open(meta_path))
    raw = Image.open(raw_path).convert('RGB')
    win_w, win_h = m['size']
    fx, fy, fw, fh = m['fold']
    portrait = win_h > win_w
    shot = raw.rotate(90, expand=True) if portrait else raw
    W, H = 2853, 2007
    canvas = gradient(W, H).convert('RGBA')
    k = H / 1206 * 0.8
    y = headline(canvas, title, sub, k * 0.95, int(50 * k))
    top = int(y + 30 * k)
    sh = H - top - int(60 * k)
    sw = int(sh * shot.size[0] / shot.size[1])
    if sw > W * 0.92:
        sw = int(W * 0.92)
        sh = int(sw * shot.size[1] / shot.size[0])
    x0 = (W - sw) // 2
    r = int(sh * 0.05)
    pad = 50
    shadow = Image.new('RGBA', (sw + 2 * pad, sh + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + 14, sw + pad, sh + pad + 14), r + 12, fill=(0, 0, 0, 170))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)), (x0 - pad, top - pad))
    b = 14
    border = Image.new('RGBA', (sw + 2 * b, sh + 2 * b), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((0, 0, sw + 2 * b - 1, sh + 2 * b - 1), r + b, fill=(22, 20, 30, 255))
    canvas.alpha_composite(border, (x0 - b, top - b))
    canvas.alpha_composite(rounded(shot.resize((sw, sh), Image.LANCZOS), r), (x0, top))
    if fold_mark:
        # Portrait raw rotated 90° counter-clockwise: the fold (horizontal at fy) becomes vertical.
        frac = (fy + fh / 2) / win_h if portrait else (fx + fw / 2) / win_w
        xf = x0 + sw * (frac if not portrait else frac)
        dashed_fold(canvas, np.array([xf, top + 10.0]), np.array([xf, top + sh - 10.0]), k, 'iPhone Duo')
    canvas.convert('RGB').save(out, optimize=True)


def main():
    raw, out, kind = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    rotate = int(sys.argv[sys.argv.index('--rotate') + 1]) if '--rotate' in sys.argv else 0
    fold_mark = '--fold' in sys.argv
    out.mkdir(parents=True, exist_ok=True)
    order = {'duo-inner': ORDER_DUO_INNER, 'duo-outer': ORDER_DUO_OUTER}.get(kind, ORDER_OTHER)
    i = 0
    for name in order:
        src = raw / f'{name}.png'
        if not src.exists():
            print('missing', name)
            continue
        i += 1
        title, sub_duo, sub = TEXT[name]
        dst = out / f'{i}-{name[2:]}.png'
        meta = raw / f'{name}.json'
        info = json.load(open(meta)) if meta.exists() else {}
        if kind == 'duo-inner' and 'upper' in info:
            compose_stage(src, meta, title, sub_duo, dst, rotate, fold_mark)
        elif kind == 'duo-inner' and info.get('presentation') == 'duel':
            compose_duel(src, meta, title, sub_duo, dst, fold_mark)
        else:
            compose_flat(src, title, sub_duo if kind.startswith('duo') else (sub or sub_duo), dst)
        print('saved', dst.name, Image.open(dst).size)


if __name__ == '__main__':
    main()
