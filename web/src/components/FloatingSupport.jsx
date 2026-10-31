import { useEffect, useState } from 'react'
import { motion, AnimatePresence } from 'framer-motion'
import { Heart } from 'lucide-react'
import { KOFI } from '../data/content.js'

/* Small floating support pill — appears after the hero, stays out of the way */
export default function FloatingSupport() {
  const [show, setShow] = useState(false)

  useEffect(() => {
    let ticking = false
    const onScroll = () => {
      if (ticking) return
      ticking = true
      requestAnimationFrame(() => {
        const y = window.scrollY
        const max = document.documentElement.scrollHeight - window.innerHeight
        setShow(y > window.innerHeight * 0.9 && y < max - 24)
        ticking = false
      })
    }
    onScroll()
    window.addEventListener('scroll', onScroll, { passive: true })
    return () => window.removeEventListener('scroll', onScroll)
  }, [])

  return (
    <AnimatePresence>
      {show && (
        <motion.a
          className="float-coffee"
          href={KOFI}
          target="_blank"
          rel="noreferrer"
          aria-label="Support Tangent on Ko-fi"
          initial={{ opacity: 0, y: 24, scale: 0.8 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 24, scale: 0.8 }}
          transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
        >
          <Heart size={16} />
          <span>Tip the dev</span>
        </motion.a>
      )}
    </AnimatePresence>
  )
}
