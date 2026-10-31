import { useEffect } from 'react'
import Nav from './components/Nav.jsx'
import Hero from './sections/Hero.jsx'
import Statement from './sections/Statement.jsx'
import BehindIcons from './sections/BehindIcons.jsx'
import Library from './sections/Library.jsx'
import Automation from './sections/Automation.jsx'
import Displays from './sections/Displays.jsx'
import Shortcuts from './sections/Shortcuts.jsx'
import Terminal from './sections/Terminal.jsx'
import Credibility from './sections/Credibility.jsx'
import GetStarted from './sections/GetStarted.jsx'
import Support from './sections/Support.jsx'
import Footer from './components/Footer.jsx'
import FloatingSupport from './components/FloatingSupport.jsx'

export default function App() {
  // Smooth scrolling with Lenis — skipped entirely for reduced-motion users,
  // who keep native, instant scrolling.
  useEffect(() => {
    if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
      document.documentElement.dataset.motion = 'reduced'
      // Ambient video counts as motion — keep every clip frozen for these users.
      document.querySelectorAll('video').forEach((v) => v.pause())
      return
    }
    let lenis
    let rafId
    let cancelled = false
    import('lenis').then(({ default: Lenis }) => {
      if (cancelled) return
      lenis = new Lenis({
        lerp: 0.11,
        anchors: true,
        prevent: (node) => node.closest?.('[data-native-scroll]') != null,
      })
      const raf = (time) => {
        lenis.raf(time)
        rafId = requestAnimationFrame(raf)
      }
      rafId = requestAnimationFrame(raf)
    })
    return () => {
      cancelled = true
      if (rafId) cancelAnimationFrame(rafId)
      lenis?.destroy()
    }
  }, [])

  return (
    <>
      <a className="skip-link" href="#main">
        Skip to content
      </a>
      <Nav />
      <main id="main">
        <Hero />
        <BehindIcons />
        <Statement />
        <Library />
        <Automation />
        <Displays />
        <Shortcuts />
        <Terminal />
        <Credibility />
        <GetStarted />
        <Support />
      </main>
      <Footer />
      <FloatingSupport />
    </>
  )
}
