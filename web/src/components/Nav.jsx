import { useEffect, useState } from 'react'
import { motion, AnimatePresence, useReducedMotion } from 'framer-motion'
import { Github, Download, Menu, X, Coffee } from 'lucide-react'
import { BRANDING, NAV_LINKS, REPO, RELEASES, KOFI, VERSION } from '../data/content.js'

export default function Nav() {
  const [scrolled, setScrolled] = useState(false)
  const [open, setOpen] = useState(false)
  const reduce = useReducedMotion()

  useEffect(() => {
    let ticking = false
    const onScroll = () => {
      if (ticking) return
      ticking = true
      requestAnimationFrame(() => {
        setScrolled(window.scrollY > 24)
        ticking = false
      })
    }
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  // Close the mobile menu when a link is followed
  const close = () => setOpen(false)

  return (
    <motion.header
      className={`nav ${scrolled ? 'is-scrolled' : ''}`}
      initial={{ y: -64, opacity: 0 }}
      animate={{ y: 0, opacity: 1 }}
      transition={reduce ? { duration: 0 } : { duration: 0.8, ease: [0.22, 1, 0.36, 1], delay: 0.2 }}
    >
      <div className="nav-inner">
        <a className="nav-brand" href="#top" onClick={close}>
          <img src={BRANDING.mark} alt="Tangent logo" width="26" height="26" />
          <span className="nav-word">Tangent</span>
          <span className="nav-version">{VERSION.split(' ')[0]}</span>
          <span className="sr-only">Back to top</span>
        </a>

        <nav className="nav-links" aria-label="Page sections">
          {NAV_LINKS.map((l) => (
            <a key={l.href} href={l.href}>
              {l.label}
            </a>
          ))}
        </nav>

        <div className="nav-actions">
          <a className="nav-coffee" href={KOFI} target="_blank" rel="noreferrer" aria-label="Support Tangent on Ko-fi">
            <Coffee size={15} strokeWidth={2} />
            <span>Ko-fi</span>
          </a>
          <a
            className="nav-gh"
            href={REPO}
            target="_blank"
            rel="noreferrer"
            aria-label="Tangent on GitHub"
          >
            <Github size={17} strokeWidth={2} />
          </a>
          <a className="btn btn--primary btn--sm" href={RELEASES} target="_blank" rel="noreferrer" aria-label="Download Tangent">
            <Download size={15} strokeWidth={2.4} />
            <span>Download</span>
          </a>
          <button
            className="nav-burger"
            aria-expanded={open}
            aria-controls="mobile-menu"
            aria-label={open ? 'Close menu' : 'Open menu'}
            onClick={() => setOpen((v) => !v)}
          >
            {open ? <X size={20} /> : <Menu size={20} />}
          </button>
        </div>
      </div>

      <AnimatePresence>
        {open && (
          <motion.div
            id="mobile-menu"
            className="nav-mobile"
            initial={{ opacity: 0, y: -12 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -12 }}
            transition={{ duration: 0.28, ease: 'easeOut' }}
            data-native-scroll
          >
            {NAV_LINKS.map((l) => (
              <a key={l.href} href={l.href} onClick={close}>
                {l.label}
              </a>
            ))}
            <div className="nav-mobile-cta">
              <a className="btn btn--primary" href={RELEASES} target="_blank" rel="noreferrer">
                <Download size={17} strokeWidth={2.4} />
                <span>Download Tangent</span>
              </a>
              <a className="btn btn--ghost" href={REPO} target="_blank" rel="noreferrer">
                <Github size={17} strokeWidth={2.2} />
                <span>Explore on GitHub</span>
              </a>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </motion.header>
  )
}
