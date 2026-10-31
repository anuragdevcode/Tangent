import { useEffect, useMemo, useRef } from 'react'
import { motion, useScroll, useTransform, useReducedMotion } from 'framer-motion'

/* ------------------------------------------------------------------ */
/* AmbientVideo — muted, looping wallpaper footage that only decodes   */
/* while it is on screen (and stays frozen for reduced-motion users)   */
/* ------------------------------------------------------------------ */
export function AmbientVideo({ className, src, poster, preload = 'metadata' }) {
  const ref = useRef(null)

  useEffect(() => {
    const video = ref.current
    if (!video) return
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches
    if (reduce) {
      video.pause()
      return
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          video.play().catch(() => {})
        } else {
          video.pause()
        }
      },
      { threshold: 0.12 },
    )
    io.observe(video)
    return () => io.disconnect()
  }, [])

  return (
    <video
      ref={ref}
      className={className}
      src={src}
      poster={poster}
      muted
      loop
      playsInline
      preload={preload}
      aria-hidden="true"
    />
  )
}

/* ------------------------------------------------------------------ */
/* Reveal — a soft fade/rise for sections entering the viewport        */
/* ------------------------------------------------------------------ */
export function Reveal({ children, delay = 0, y = 28, className, style }) {
  const reduce = useReducedMotion()
  if (reduce) {
    return (
      <div className={className} style={style}>
        {children}
      </div>
    )
  }
  return (
    <motion.div
      className={className}
      style={style}
      initial={{ opacity: 0, y }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '0px 0px -12% 0px' }}
      transition={{ duration: 0.9, delay, ease: [0.22, 1, 0.36, 1] }}
    >
      {children}
    </motion.div>
  )
}

/* ------------------------------------------------------------------ */
/* SectionHead — eyebrow + editorial heading + supporting lede         */
/* ------------------------------------------------------------------ */
export function SectionHead({ eyebrow, title, lede, align = 'center', size = 'lg' }) {
  return (
    <div className={`section-head align-${align} section-head--${size}`}>
      {eyebrow && (
        <Reveal>
          <p className="eyebrow">{eyebrow}</p>
        </Reveal>
      )}
      <Reveal delay={0.08}>
        <h2 className="section-title">{title}</h2>
      </Reveal>
      {lede && (
        <Reveal delay={0.16}>
          <p className="lede">{lede}</p>
        </Reveal>
      )}
    </div>
  )
}

/* ------------------------------------------------------------------ */
/* WordReveal — scroll-linked word-by-word illumination (kinetic VFX)  */
/* ------------------------------------------------------------------ */
function Word({ progress, range, children }) {
  const opacity = useTransform(progress, range, [0.5, 1])
  const y = useTransform(progress, range, [10, 0])
  return (
    <motion.span style={{ opacity, y }} className="wr-word">
      {children}
    </motion.span>
  )
}

export function WordReveal({ text, className, offset = ['start 0.9', 'start 0.3'] }) {
  const ref = useRef(null)
  const reduce = useReducedMotion()
  
  // Clean split that ignores extra spaces or line breaks
  const words = useMemo(() => text.trim().split(/\s+/), [text])
  const { scrollYProgress } = useScroll({ target: ref, offset })

  if (reduce) {
    return (
      <p ref={ref} className={className}>
        {text}
      </p>
    )
  }

  const n = words.length
  return (
    <p ref={ref} className={className}>
      {words.map((w, i) => {
        const from = (i / n) * 0.85
        const to = Math.min(1, from + 0.3)
        return (
          <span key={`${w}-${i}`} className="inline-block whitespace-nowrap">
            <Word progress={scrollYProgress} range={[from, to]}>
              {w}
            </Word>
            {i < n - 1 && '\u00A0'} {/* Non-breaking space, or regular ' ' outside <Word> */}
          </span>
        )
      })}
    </p>
  )
}
/* ------------------------------------------------------------------ */
/* Toggle — a decorative macOS-style switch (non-interactive on purpose) */
/* ------------------------------------------------------------------ */
export function Toggle({ on = false, delay = 0, animate = false }) {
  const reduce = useReducedMotion()
  return (
    <span className={`toggle ${on ? 'is-on' : 'is-off'}`} aria-hidden="true">
      <motion.span
        className="toggle-knob"
        initial={false}
        animate={{ x: on ? 100 : 0 }}
        {...(animate
          ? {
              variants: {
                on: { x: 100 },
                off: { x: 0 },
              },
              whileInView: 'on',
              viewport: { once: true },
              transition: { delay, duration: 0.45, ease: [0.34, 1.56, 0.64, 1] },
            }
          : {})}
      />
    </span>
  )
}

/* ------------------------------------------------------------------ */
/* Kbd — keycap row for the shortcuts scene                            */
/* ------------------------------------------------------------------ */
export function ShortcutRow({ keys, label, desc, index = 0 }) {
  return (
    <motion.li
      className="shortcut-row"
      initial={{ opacity: 0, y: 18 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-8% 0px' }}
      transition={{ duration: 0.7, delay: index * 0.12, ease: [0.22, 1, 0.36, 1] }}
    >
      <span className="shortcut-keys" aria-label={label}>
        {keys.map((k, i) => (
          <kbd key={i}>{k}</kbd>
        ))}
      </span>
      <span className="shortcut-meta">
        <strong>{label}</strong>
        {desc && <em>{desc}</em>}
      </span>
    </motion.li>
  )
}
