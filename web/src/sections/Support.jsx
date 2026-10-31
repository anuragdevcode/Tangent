import { motion, useReducedMotion } from 'framer-motion'
import { Coffee, Heart } from 'lucide-react'
import { SectionHead, Reveal } from '../components/Shared.jsx'
import { SpotlightCard } from '../components/Fx.jsx'
import { KOFI } from '../data/content.js'

export default function Support() {
  const reduce = useReducedMotion()
  return (
    <section id="support" className="section support-sec">
      <div className="kwrap">
        <SectionHead
          align="center"
          size="md"
          eyebrow="Support the humans"
          title={<>One dev, one desktop engine, zero venture funding.</>}
        />

        <Reveal>
          <SpotlightCard className="support-card">
            <div className="support-icon" aria-hidden="true">
              <Heart size={26} fill="currentColor" strokeWidth={0} />
            </div>
            <div className="support-copy">
              <p>
                <strong>Tangent is free and open source.</strong> No paywall, no pro tier, no
                &ldquo;unlock your GPU&rdquo; nonsense. It stays free because it&rsquo;s GPL-3.0, and
                it keeps getting better because someone stubbornly invests evenings and weekends
                into it.
              </p>
              <p>
                If it made your desktop <em>actually</em> better, a tip on Ko-fi directly funds new
                backends and polish. Entirely optional — the wallpaper still works if you say no.
              </p>
            </div>
            <motion.div
              className="support-cta"
              initial={reduce ? {} : { opacity: 0, y: 16 }}
              whileInView={reduce ? {} : { opacity: 1, y: 0 }}
              viewport={{ once: true }}
              transition={{ duration: 0.8, delay: 0.2 }}
            >
              <a className="btn btn--kofi" href={KOFI} target="_blank" rel="noreferrer">
                <Coffee size={18} />
                <span>Support me on Ko-fi</span>
              </a>
              <span className="support-fine">Tipping is optional. Guilt is outdated firmware.</span>
            </motion.div>
          </SpotlightCard>
        </Reveal>
      </div>
    </section>
  )
}
