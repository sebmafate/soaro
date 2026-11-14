# Website

The website is plain HTML and CSS in the `site/` folder. There is no build step, no script and no external font or request, which fits the privacy promise of the app.

| Path | What it is |
| --- | --- |
| `site/index.html` | English page (`https://soaro.app/`) |
| `site/fr/index.html` | French page (`https://soaro.app/fr/`) |
| `site/style.css` | The only stylesheet. Light and dark mode follow the visitor's system |
| `site/screenshots/` | WebP screenshots, each in two sizes (`name.webp` at 2x, `name-946.webp` at 1x) used with `srcset` |
| `site/og-en.png`, `site/og-fr.png` | Social cards (1200 x 630) shown when the page is shared |
| `site/favicon.ico`, `favicon-32.png`, `icon.svg`, `apple-touch-icon.png`, `icon-192.png`, `icon-512.png`, `icon-512-maskable.png` | Favicons and app icons |
| `site/site.webmanifest` | Web app manifest (name, colors, icons) |
| `site/flags/` | Flag images for the language selector and the list of languages. They come from [flag-icons](https://github.com/lipis/flag-icons) (MIT, license in the folder); `es.svg` is a simplified drawing |
| `site/404.html` | Page shown for an unknown address |
| `site/.well-known/security.txt` | How to report a vulnerability. Renew its `Expires` date every year |
| `site/_headers`, `site/_redirects` | Security headers, cache rules and redirections (Cloudflare Pages). `/download` and `/github` are short links |
| `site/robots.txt`, `site/sitemap.xml` | Search engines. The sitemap links the two languages and has a `lastmod` date |
| `site/appcast.xml` | The Sparkle update feed. It is added at each release, see [releasing.md](releasing.md) |

The Content Security Policy in `_headers` blocks inline styles and scripts. Keep styles in `style.css`.

## Hosting on Cloudflare Pages

1. In Cloudflare, create a Pages project and connect it to the GitHub repository.
2. Build command: none. Output directory: `site`.
3. Add the custom domain `soaro.app`.

Each push to `main` deploys the site. Pull requests get a preview address.

## Screenshots

The screenshots use the **demo mode** of the app: a made-up Mac, so nothing personal appears (no computer name, serial number, IP address, Wi-Fi name or process).

```bash
scripts/build-app.sh
scripts/make-screenshots.sh site/screenshots en fr
```

The script opens the app once per screen and per language, and captures its window. A few notes:

- The Mac must have a Retina screen to get sharp (2x) images. The app moves the window there for the capture.
- The window uses the current appearance (light or dark) of the Mac.
- It converts the images to WebP (2x and 1x) if `cwebp` is installed (`brew install webp`), and removes the PNG files.
- Run it with nothing else on top of the Soaro window, and do not touch the keyboard during the capture.

To try the demo mode by hand: `SOARO_DEMO=1 build/Soaro.app/Contents/MacOS/Soaro`. In this mode the app measures nothing, writes nothing, and sends no notification. The made-up data is in `Sources/Soaro/DemoData.swift`.

## SEO

Each page has, in its `<head>`: a title (about 50-60 characters) and a description (about 150), the canonical address, `hreflang` links between the two languages, Open Graph and Twitter Card tags, icons, and structured data (JSON-LD, type `SoftwareApplication`). The page has one `<h1>`, descriptive `alt` texts, a "skip to content" link, and the first image loads with high priority while the others are lazy.

Things to do when something changes:

- **New release or new screenshots:** update `lastmod` in `sitemap.xml`.
- **New language page:** add its `hreflang` links to every page and to the sitemap.
- **Change of text in a page:** keep the title and description in sync with the Open Graph and JSON-LD copies (they repeat the same sentences).
- **Search Console:** add the property `soaro.app` (domain verification with a DNS record), then submit `https://soaro.app/sitemap.xml`. Do the same in Bing Webmaster Tools.
- **Check a share card** after a change: paste the address in a chat or a social network, or use the tools of the networks.

The structured data must stay true. There is no rating or review in it, and there will be none unless real ones exist.

## Visit statistics

The website counts visits with [Umami](https://umami.is), hosted by the maintainer at `https://stats.sferrand.fr` (website "soaro.app"). The script is the last tag of the `<head>` of each page:

- `data-domains="soaro.app"`: nothing is counted on a local server or a preview address.
- `data-do-not-track="true"`: visitors who ask not to be tracked are not counted.
- The Content Security Policy in `_headers` allows this one host for scripts and requests. If the Umami address changes, change it in the two pages **and** in `_headers`.
- Umami sets no cookie. The pages say so in the "Privacy" section: keep that text true if the tool changes.

The **app** has no statistics of any kind. Do not add some: this is part of its promise.

## Images that are not screenshots

```bash
swift scripts/make-site-images.swift
```

It draws the favicons, the app icons and the two social cards from `assets/icon.svg` and the overview screenshots. The icon artwork is never changed; only a copy without rounded corners is made for `apple-touch-icon.png` and the maskable icon, because iOS and Android round them on their own. Run it again after new screenshots.

## Writing rules

Texts are written in plain, direct language, with short sentences and no marketing. Every claim must be true: the page says Soaro is notarized, so do not publish the site before the first notarized release exists.
