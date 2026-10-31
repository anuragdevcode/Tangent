import { Github, ExternalLink, Heart, Scale } from 'lucide-react'
import { BRANDING, REPO, REPO_TREE, RELEASES, ISSUES, LICENSE, KOFI, VERSION } from '../data/content.js'

export default function Footer() {
  return (
    <footer className="footer">
      <div className="kwrap footer-inner">
        <div className="footer-top">
          <div className="footer-brand">
            <img src={BRANDING.mark} alt="Tangent logo" width="40" height="40" />
            <div>
              <p className="footer-name">Tangent</p>
              <p className="footer-tag">Live wallpapers, native to macOS.</p>
            </div>
          </div>

          <nav className="footer-cols" aria-label="Footer">
            <div>
              <p className="footer-col-title">Project</p>
              <a href={RELEASES} target="_blank" rel="noreferrer">
                Releases <ExternalLink size={11} />
              </a>
              <a href={ISSUES} target="_blank" rel="noreferrer">
                Issues <ExternalLink size={11} />
              </a>
              <a href={LICENSE} target="_blank" rel="noreferrer">
                License (GPL-3.0) <ExternalLink size={11} />
              </a>
            </div>
            <div>
              <p className="footer-col-title">Source</p>
              <a href={REPO} target="_blank" rel="noreferrer">
                GitHub <ExternalLink size={11} />
              </a>
              <a href={REPO_TREE} target="_blank" rel="noreferrer">
                Browse main <ExternalLink size={11} />
              </a>
              <a href="#terminal" className="footer-inner-link">
                Build from source
              </a>
            </div>
            <div>
              <p className="footer-col-title">Support</p>
              <a href={KOFI} target="_blank" rel="noreferrer">
                <Heart size={11} /> Ko-fi
              </a>
              <a href="#support" className="footer-inner-link">
                Why tips matter
              </a>
            </div>
          </nav>
        </div>

        <div className="footer-note">
          <p>
            <Scale size={13} />
            Wallpapers shown in the demos on this page belong to their respective creators and
            rights holders. Tangent does not claim ownership of these works, does not distribute
            them for payment, and they are not for commercial use — please refer to the original
            creators&rsquo; terms and licenses for applicable usage rights. This note is an
            attribution statement, not a legal guarantee.
          </p>
        </div>

        <div className="footer-bottom">
          <p>GPL-3.0 · © 2026 Tangent contributors. Built with AppKit, marketed with sarcasm.</p>
          <p className="footer-meta">v{VERSION} · arm64 · min macOS 13.0</p>
        </div>
      </div>
    </footer>
  )
}
