// Central content model for the Tangent landing page.
// Every claim on the page traces back to the repository README / ARCHITECTURE.md.
// Edit copy here — components stay dumb.

export const REPO = 'https://github.com/anuragdevcode/Tangent'
export const REPO_TREE = `${REPO}/tree/main`
export const RELEASES = `${REPO}/releases`
export const ISSUES = `${REPO}/issues`
export const LICENSE = `${REPO}/blob/main/LICENSE`
export const KOFI = 'https://ko-fi.com/anuragcodes'

export const VERSION = '0.5.0 (6)'
export const RELEASE_TAG = 'v0.5.0'
export const DOWNLOAD = `${REPO}/releases/download/${RELEASE_TAG}/Tangent-0.5.0-arm64.dmg`
export const FAVICON = import.meta.env.BASE_URL + 'brand/favicon-128.png'

export const asset = (p) => import.meta.env.BASE_URL + p

export const MEDIA = {
  wallpaperVideo: asset('media/celestial-veil-desktop.mp4'),
  wallpaperPoster: asset('media/celestial-veil-poster.webp'),
}

export const BRANDING = {
  logo: asset('brand/logo-mark.webp'),
  mark: asset('brand/logo-mark.webp'),
}

export const NAV_LINKS = [
  { label: 'Behind the icons', href: '#behind-icons' },
  { label: 'Library', href: '#library' },
  { label: 'Automation', href: '#automation' },
  { label: 'Terminal', href: '#terminal' },
  { label: 'Support', href: '#support' },
]
