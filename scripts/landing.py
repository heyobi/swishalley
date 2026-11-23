"""GitHub Pages landing page (docs/index.html) for Swish Alley, from heyobi/querly scripts/landing-pages.py. Usage: python -X utf8 scripts/landing.py"""
import html, json

BADGE = 'app-store-badge.svg'

CSS = """
:root{--bg:#fbf5f0;--fg:#1d1026;--muted:#6b5a72;--card:#f3e8ee;--line:#e6d3de;--accent:#c4207a}
@media (prefers-color-scheme:dark){:root{--bg:#0d0716;--fg:#fff3ea;--muted:#b9a4c4;--card:#1a1028;--line:#2d1d42;--accent:#ff5fb4}}
h1,h2{font-weight:700}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:17px/1.6 -apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif}
main{max-width:1040px;margin:0 auto;padding:40px 16px 64px}
header{text-align:center}header img.icon{width:112px;height:112px;border-radius:24px;box-shadow:0 10px 30px rgba(0,0,0,.18)}
h1{font-size:clamp(30px,5vw,46px);line-height:1.15;margin:18px 0 10px;letter-spacing:-.02em}
.lead{font-size:clamp(17px,2.2vw,20px);color:var(--muted);max-width:720px;margin:0 auto 22px}
.badge img{height:54px}
.shots{display:flex;gap:14px;overflow-x:auto;padding:28px 0 8px;scroll-snap-type:x mandatory}
.shots img{height:min(560px,70vh);border-radius:18px;scroll-snap-align:center;flex:none;box-shadow:0 8px 24px rgba(0,0,0,.15)}
h2{font-size:28px;margin:48px 0 12px;letter-spacing:-.01em}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:14px}
.card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px}
.card b{display:block;margin-bottom:4px}
details{background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px 18px;margin:10px 0}
summary{font-weight:600;cursor:pointer}
a{color:var(--accent)}code{font:15px ui-monospace,Menlo,monospace;background:var(--card);padding:1px 6px;border-radius:6px}
.wide img{width:100%;border-radius:18px;box-shadow:0 8px 24px rgba(0,0,0,.15)}
footer{color:var(--muted);font-size:14px;margin-top:56px;text-align:center}
"""


def page(app):
    faq_ld = {"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": [
        {"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in app['faq']]}
    app_ld = {"@context": "https://schema.org", "@type": "SoftwareApplication", "name": app['name'],
              "operatingSystem": "iOS, iPadOS", "applicationCategory": app['category'],
              "description": app['description'], "url": app['store'], "downloadUrl": app['store'],
              "image": app['site'] + 'icon.png', "screenshot": [app['site'] + s for s, _ in app['shots']],
              "offers": {"@type": "Offer", "price": "0", "priceCurrency": "USD"},
              "author": {"@type": "Person", "name": "heyobi", "url": "https://github.com/heyobi"}}
    e = html.escape
    shots = '\n'.join(f'    <img src="{s}" alt="{e(alt)}" loading="lazy">' for s, alt in app['shots'])
    feats = '\n'.join(f'    <div class="card"><b>{e(t)}</b>{e(d)}</div>' for t, d in app['features'])
    faq = '\n'.join(f'  <details><summary>{e(q)}</summary><p>{e(a)}</p></details>' for q, a in app['faq'])
    extra = app.get('extra', '')
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{e(app['title'])}</title>
<meta name="description" content="{e(app['description'])}">
<meta name="keywords" content="{e(app['keywords'])}">
<link rel="canonical" href="{app['site']}">
<link rel="icon" href="icon.png">
<meta name="apple-itunes-app" content="app-id={app['id']}">
<meta property="og:type" content="website">
<meta property="og:title" content="{e(app['title'])}">
<meta property="og:description" content="{e(app['description'])}">
<meta property="og:url" content="{app['site']}">
<meta property="og:image" content="{app['site']}{app['shots'][0][0]}">
<meta name="twitter:card" content="summary_large_image">
<script type="application/ld+json">{json.dumps(app_ld, ensure_ascii=False)}</script>
<script type="application/ld+json">{json.dumps(faq_ld, ensure_ascii=False)}</script>
<style>{CSS}</style>
</head>
<body>
<main>
<header>
  <img class="icon" src="icon.png" alt="{e(app['name'])} app icon" width="112" height="112">
  <h1>{e(app['h1'])}</h1>
  <p class="lead">{e(app['lead'])}</p>
  <a class="badge" href="{app['store']}"><img src="{BADGE}" alt="Download {e(app['name'])} on the App Store"></a>
</header>
<div class="shots">
{shots}
</div>
<h2>{e(app['features_title'])}</h2>
<div class="grid">
{feats}
</div>
{extra}
<h2>Questions</h2>
{faq}
<footer>
  <p><a href="{app['store']}">{e(app['name'])} on the App Store</a> · <a href="{app['repo']}">Source code on GitHub</a> · {app['sibling']}</p>
  <p>{e(app['legal'])}</p>
</footer>
</main>
</body>
</html>
"""


import os
APP_ID = os.environ.get('APP_ID', 'APPID')

app = dict(
    id=APP_ID, name='Swish Alley', category='GameApplication',
    store=f'https://apps.apple.com/app/id{APP_ID}',
    site='https://heyobi.github.io/swishalley/', repo='https://github.com/heyobi/swishalley',
    title='Swish Alley: arcade basketball for iPhone Duo, iPhone and iPad with a head-tracked 3D hoop',
    h1='Arcade basketball on the fold of iPhone Duo',
    lead='Stand iPhone Duo half open: the upright half becomes the backboard, the lower half the floor, and the rim hangs right above the fold. Flick to shoot, get on fire, beat your best in 60 seconds, or open it flat for a face-to-face duel. Plays on every iPhone and iPad too.',
    description='Arcade basketball made for iPhone Duo: flick to shoot, a 3D hoop drawn from the live hinge angle and the real fold, optional head tracking, a free face-to-face duel on one phone. Also on iPhone and iPad. Free, no ads.',
    keywords='basketball game iPhone Duo, arcade basketball, iPhone Duo games, two player basketball one phone, flick basketball, head tracking 3D game, foldable phone games, basketball shooting game offline',
    shots=[('screens/duo-1-stage.jpg', 'iPhone Duo half open: the hoop stands on the fold, the floor lies flat'),
           ('screens/duo-2-fire.jpg', 'On fire: three in a row and baskets are worth 3'),
           ('screens/duo-4-duel.jpg', 'iPhone Duo opened flat: a face-to-face duel, the fold is the centre line'),
           ('screens/iphone-1-play.jpg', 'Swish Alley on iPhone'),
           ('screens/iphone-4-results.jpg', 'A new personal best'),
           ('screens/ipad-1-play.jpg', 'Swish Alley on iPad')],
    features_title='The phone becomes an arcade lane',
    features=[('Real hinge, real fold', 'The live hinge angle tilts the 3D world and the fold position comes from the system, so the backboard stands upright and the floor lies flat at 90, 110 or 130 degrees, with the rim right above the crease.'),
              ('One flick', 'Flick speed sets the power, direction sets the aim. The same flick feels the same on every device.'),
              ('A hoop that pops out', 'Optional head tracking draws the hoop from your point of view; lean to look around the backboard. Frames never leave the phone.'),
              ('On fire, double, moving hoop', 'Three in a row and baskets are worth 3. The last 10 seconds count double and the hoop starts to glide.'),
              ('Face-to-face duel, free', 'Open iPhone Duo flat between two players: race at the same time or take turns.'),
              ('Arcade sound', 'Net swish, rim rattle, board thump and a haptic tap for every bounce, with original instrumental music synthesized on the device.'),
              ('Every iPhone and iPad', 'Without a fold, the screen is a window into a neon arcade lane with the same physics.'),
              ('Fair', 'The whole game is free with no ads or account. One optional purchase for more arenas, balls and modes.')],
    faq=[('Is there a basketball game for iPhone Duo?', 'Swish Alley stands the backboard on the upright half of a half-open iPhone Duo and lays the floor on the lower half, using the live hinge angle and the real fold position, so the hoop looks right at any angle.'),
         ('Can two people play basketball on one phone?', 'Yes. Open iPhone Duo flat between you (or use any iPhone or iPad) and each player gets one half. Race at the same time or take turns. The duel is free.'),
         ('How does the 3D hoop work?', 'Each half of the display is rendered with an off-axis projection from your eye position, found by the front camera. The hoop stays fixed in space as you move your head. Head tracking is optional.'),
         ('Does Swish Alley work offline and without ads?', 'Yes. No account, no ads, no tracking, no internet needed.'),
         ('What does Swish Alley Pro add?', 'Three more arenas, four more balls and two more modes (Overtime and Drift), for one payment. No subscription.')],
    sibling='<a href="https://heyobi.github.io/tinyfolk/">Tinyfolk: a pocket hologram for iPhone Duo</a> · <a href="https://heyobi.github.io/pleats/">Pleats: an accordion for iPhone Duo</a>',
    legal='iPhone and iPhone Duo are trademarks of Apple Inc. Swish Alley, its arenas and its music are original works by heyobi.',
)

out = os.path.join(os.path.dirname(__file__), '..', 'docs', 'index.html')
open(out, 'w', encoding='utf-8', newline=chr(10)).write(page(app))
print('ok')
