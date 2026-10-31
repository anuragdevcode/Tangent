import { useRef } from 'react'
import { motion, useScroll, useTransform, useReducedMotion } from 'framer-motion'
import { Download, Github, ChevronDown, Coffee, Cpu } from 'lucide-react'
import { DOWNLOAD, REPO, KOFI, BRANDING, VERSION, MEDIA } from '../data/content.js'
import { AmbientVideo } from '../components/Shared.jsx'
import { Magnet } from '../components/Fx.jsx'

export default function Hero() {
  const ref = useRef(null)
  const reduce = useReducedMotion()
  const { scrollYProgress } = useScroll({ target: ref, offset: ['start start', 'end start'] })

  // The opening "shot": the film scales down as you scroll out
  const bgScale = useTransform(scrollYProgress, [0, 1], [1.08, 1.22])
  const bgDim = useTransform(scrollYProgress, [0, 1], [0.62, 0.86])
  const contentY = useTransform(scrollYProgress, [0, 1], [0, -120])
  const contentOpacity = useTransform(scrollYProgress, [0, 0.75], [1, 0])
  const logoY = useTransform(scrollYProgress, [0, 1], [0, -60])

  const bgStyle = reduce ? { scale: 1.08 } : { scale: bgScale }

  return (
    <section id="top" className="hero" ref={ref}>
      <motion.div className="hero-bg" style={bgStyle} aria-hidden="true">
        <AmbientVideo
          className="hero-video"
          src={MEDIA.wallpaperVideo}
          poster={MEDIA.wallpaperPoster}
          preload="auto"
        />
        <motion.div className="hero-dim" style={reduce ? { opacity: 0.7 } : { opacity: bgDim }} />
      </motion.div>

      <motion.div className="hero-content" style={reduce ? {} : { y: contentY, opacity: contentOpacity }}>
        <motion.div
          className="hero-logo-wrap"
          style={reduce ? {} : { y: logoY }}
          initial={reduce ? {} : { opacity: 0, scale: 0.86, filter: 'blur(14px)' }}
          animate={reduce ? {} : { opacity: 1, scale: 1, filter: 'blur(0px)' }}
          transition={{ duration: 1.4, ease: [0.22, 1, 0.36, 1], delay: 0.15 }}
        >
          <img
            className="hero-logo"
            src={BRANDING.logo}
            alt="Tangent logo — a silver tangent line meeting a neon sine wave"
            width="768"
            height="768"
            fetchPriority="high"
            data-video
          />
        </motion.div>

        <motion.p
          className="eyebrow"
          initial={reduce ? {} : { opacity: 0, y: 16 }}
          animate={reduce ? {} : { opacity: 1, y: 0 }}
          transition={{ duration: 0.8, delay: 0.5 }}
        >
          Live wallpaper engine · native to macOS · Apple Silicon
        </motion.p>

        <motion.h1
          className="hero-title"
          initial={reduce ? {} : { opacity: 0, y: 28 }}
          animate={reduce ? {} : { opacity: 1, y: 0 }}
          transition={{ duration: 1, delay: 0.62, ease: [0.22, 1, 0.36, 1] }}
        >
          Your desktop called.{' '}
          <br />
          <span className="grad-text">It&rsquo;s bored.</span>
        </motion.h1>

        <motion.p
          className="hero-sub"
          initial={reduce ? {} : { opacity: 0, y: 24 }}
          animate={reduce ? {} : { opacity: 1, y: 0 }}
          transition={{ duration: 1, delay: 0.76, ease: [0.22, 1, 0.36, 1] }}
        >
          Tangent renders video, web, GIF and image wallpapers in a click-through window
          <em> behind your desktop icons</em> — hardware-decoded, per-display, and smart enough
          to shut up when you&rsquo;re working.
        </motion.p>

        <motion.div
          className="hero-ctas"
          initial={reduce ? {} : { opacity: 0, y: 24 }}
          animate={reduce ? {} : { opacity: 1, y: 0 }}
          transition={{ duration: 1, delay: 0.9, ease: [0.22, 1, 0.36, 1] }}
        >
          <Magnet>
            <a className="btn btn--primary btn--lg" href={DOWNLOAD} target="_blank" rel="noreferrer">
              <Download size={19} strokeWidth={2.6} />
              <span>Download Tangent</span>
            </a>
          </Magnet>
          <a className="btn btn--ghost btn--lg" href={REPO} target="_blank" rel="noreferrer">
            <Github size={18} strokeWidth={2.2} />
            <span>Explore on GitHub</span>
          </a>
        </motion.div>

        <motion.p
          className="hero-kofi"
          initial={reduce ? {} : { opacity: 0 }}
          animate={reduce ? {} : { opacity: 1 }}
          transition={{ duration: 1, delay: 1.15 }}
        >
          Optional, but appreciated: <a href={KOFI} target="_blank" rel="noreferrer"><Coffee size={13} /> buy me a coffee</a> — about the same price as a wallpaper that actually moves.
        </motion.p>

        <motion.div
          className="hero-meta"
          initial={reduce ? {} : { opacity: 0 }}
          animate={reduce ? {} : { opacity: 1 }}
          transition={{ duration: 1, delay: 1.3 }}
        >
          <span><Cpu size={13} /> Apple Silicon M1+</span>
          <span>macOS 13.0+</span>
          <span>GPL-3.0</span>
          <span>v{VERSION}</span>
        </motion.div>
      </motion.div>

      <motion.div
        className="hero-cue"
        initial={reduce ? {} : { opacity: 0 }}
        animate={reduce ? {} : { opacity: 1 }}
        transition={{ duration: 1, delay: 1.6 }}
        aria-hidden="true"
      >
        <ChevronDown size={18} />
        <span>scroll — it gets worse</span>
      </motion.div>
    </section>
  )
}
