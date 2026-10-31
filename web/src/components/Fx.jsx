import { useEffect, useRef, useState } from 'react'
import {
  animate,
  motion,
  useInView,
  useMotionValue,
  useReducedMotion,
  useSpring,
} from 'framer-motion'

/* ------------------------------------------------------------------ */
/* Open-source component adaptations, reimplemented for this project's  */
/* CSS system and monochrome palette (all MIT licensed):                */
/*   NumberTicker, Marquee  — Magic UI        (magicui.design)          */
/*   SpotlightCard          — Aceternity UI   (ui.aceternity.com)       */
/*   Magnet                 — React Bits      (reactbits.dev)           */
/* ------------------------------------------------------------------ */

const formatValue = (value, decimals) =>
  decimals > 0
    ? value.toFixed(decimals)
    : Math.round(value).toLocaleString('en-US').replace(/,/g, ' ')

/* Magic UI NumberTicker — counts a stat up once it scrolls into view. */
export function NumberTicker({
  value,
  prefix = '',
  suffix = '',
  decimals = 0,
  duration = 1.7,
  className = '',
}) {
  const ref = useRef(null)
  const inView = useInView(ref, { once: true, margin: '-8% 0px' })
  const reduce = useReducedMotion()
  const [display, setDisplay] = useState(0)

  useEffect(() => {
    if (reduce || !inView) return
    const controls = animate(0, value, {
      duration,
      ease: [0.16, 1, 0.3, 1],
      onUpdate: (v) => setDisplay(v),
    })
    return () => controls.stop()
  }, [inView, reduce, value, duration])

  const shown = reduce ? value : display
  const finalText = `${prefix}${formatValue(value, decimals)}${suffix}`

  return (
    <span ref={ref} className={className}>
      <span aria-hidden="true">
        {prefix}
        {formatValue(shown, decimals)}
        {suffix}
      </span>
      <span className="sr-only">{finalText}</span>
    </span>
  )
}

/* Magic UI Marquee — a seamless capability ticker. Decorative: the same
   facts live in the surrounding copy, so it is hidden from assistive tech. */
export function Marquee({ items, speed = 38, className = '' }) {
  const reduce = useReducedMotion()
  const list = reduce ? items : [...items, ...items]

  return (
    <div className={`marquee ${className}`.trim()} aria-hidden="true">
      <div
        className="marquee-track"
        style={reduce ? undefined : { animationDuration: `${speed}s` }}
      >
        {list.map((item, i) => (
          <span className="marquee-item" key={`${item}-${i}`}>
            {item}
          </span>
        ))}
      </div>
    </div>
  )
}

/* Aceternity SpotlightCard — a soft white spotlight follows the pointer
   across a card. Hover-only; purely decorative. */
export function SpotlightCard({ className = '', children, ...props }) {
  const ref = useRef(null)

  const onPointerMove = (e) => {
    const el = ref.current
    if (!el) return
    const rect = el.getBoundingClientRect()
    el.style.setProperty('--spot-x', `${e.clientX - rect.left}px`)
    el.style.setProperty('--spot-y', `${e.clientY - rect.top}px`)
  }

  return (
    <div
      ref={ref}
      className={`spotlight-card ${className}`.trim()}
      onPointerMove={onPointerMove}
      {...props}
    >
      {children}
    </div>
  )
}

/* React Bits Magnet — the primary CTA leans a few pixels toward the
   cursor. Mouse-only and disabled for reduced-motion users. */
export function Magnet({ children, strength = 0.16, className = '' }) {
  const ref = useRef(null)
  const reduce = useReducedMotion()
  const x = useMotionValue(0)
  const y = useMotionValue(0)
  const springX = useSpring(x, { stiffness: 180, damping: 18, mass: 0.2 })
  const springY = useSpring(y, { stiffness: 180, damping: 18, mass: 0.2 })

  const onPointerMove = (e) => {
    if (reduce || e.pointerType !== 'mouse' || !ref.current) return
    const rect = ref.current.getBoundingClientRect()
    x.set((e.clientX - (rect.left + rect.width / 2)) * strength)
    y.set((e.clientY - (rect.top + rect.height / 2)) * strength)
  }

  const reset = () => {
    x.set(0)
    y.set(0)
  }

  return (
    <motion.div
      ref={ref}
      className={`magnet ${className}`.trim()}
      style={reduce ? undefined : { x: springX, y: springY }}
      onPointerMove={onPointerMove}
      onPointerLeave={reset}
    >
      {children}
    </motion.div>
  )
}
