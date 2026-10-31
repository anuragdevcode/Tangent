# Tangent — Landing Page

An art-directed, dark-mode-only product landing page for
[Tangent](https://github.com/anuragdevcode/Tangent), the native live-wallpaper
engine for Apple Silicon Macs.

Built with **React 19 + Vite 7**, animated with **Framer Motion**, smooth-scrolled
with **Lenis**, and iconographed with **Lucide**. The palette is intentionally
monochrome: the only colour on the page comes from the logo and the real wallpaper
footage.

## Run locally

```bash
npm install
npm run dev
```

## Build

```bash
npm run build
npm run preview
```

The production build is emitted to `dist/`.

## Deploy to GitHub Pages

`vite.config.js` sets `base: '/Tangent/'`, which matches a project site at
`https://anuragdevcode.github.io/Tangent/`. Publish the `dist/` folder (for example
with the `gh-pages` package or a GitHub Actions Pages workflow) after building.

If you move the site to a custom domain or a user site, update `base` accordingly.

## Content model

All copy, links and media paths live in `src/data/content.js`:

- GitHub repo / releases / issues / license
- Ko-fi page
- version string, nav links, brand assets, wallpaper media

## Open-source components

Four interaction primitives are adapted (not installed as dependencies) into
`src/components/Fx.jsx`, rewritten to use this project's plain CSS and
monochrome tokens. All three upstream projects are MIT licensed:

| Component | Upstream | Author / site | Used for |
| --- | --- | --- | --- |
| `NumberTicker` | [Magic UI](https://magicui.design) | Magic UI | count-up credibility stats |
| `Marquee` | [Magic UI](https://magicui.design) | Magic UI | capabilities ticker band |
| `SpotlightCard` | [Aceternity UI](https://ui.aceternity.com) | Aceternity | pointer spotlight on stat / support cards |
| `Magnet` | [React Bits](https://reactbits.dev) | David Haz | magnetic hero download button |

Each adaptation is reduced to the behaviour the page needs: the ticker exposes the
final value to screen readers and is static under `prefers-reduced-motion`, the
marquee renders a single static row under reduced motion, the spotlight is
hover-only and decorative, and the magnet ignores touch pointers.

## Assets

- `public/brand/logo-mark.webp` — tightly cropped Tangent app icon derived from the
  supplied logo; used at its native aspect ratio (no stretching).
- `public/media/celestial-veil-desktop.mp4` — 1080p web encode of the supplied 4K
  demo wallpaper, muted and looped; `celestial-veil-poster.webp` is its poster frame.
- The demo wallpaper belongs to its respective creator and rights holder. It is
  shown for demonstration only, is not sold or bundled with Tangent, and is not for
  commercial use. The footer states this explicitly and does not claim it as a legal
  guarantee.
