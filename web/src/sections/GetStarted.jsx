import { motion, useReducedMotion } from 'framer-motion'
import { Download, Github, Cpu, MonitorDown, Scale } from 'lucide-react'
import { DOWNLOAD, RELEASES, REPO, LICENSE } from '../data/content.js'

export default function GetStarted() {
  const reduce = useReducedMotion()
  return (
    <section id="get-started" className="section get-sec">
      <div className="kwrap get-inner">
        <motion.div
          className="get-glow"
          aria-hidden="true"
          initial={reduce ? { opacity: 0.5 } : { opacity: 0 }}
          whileInView={{ opacity: 0.6 }}
          viewport={{ once: true }}
          transition={{ duration: 1.6 }}
        />
        <motion.p
          className="eyebrow"
          initial={reduce ? {} : { opacity: 0, y: 16 }}
          whileInView={reduce ? {} : { opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-15% 0px' }}
          transition={{ duration: 0.8 }}
        >
          $0. Forever, thanks to GPL-3.0.
        </motion.p>
        <motion.h2
          className="get-title"
          initial={reduce ? {} : { opacity: 0, y: 30 }}
          whileInView={reduce ? {} : { opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-15% 0px' }}
          transition={{ duration: 1, ease: [0.22, 1, 0.36, 1] }}
        >
          Costs nothing. Your guilt
          <br />
          costs about <span className="grad-text">a coffee.</span>
        </motion.h2>

        <motion.div
          className="hero-ctas get-ctas"
          initial={reduce ? {} : { opacity: 0, y: 24 }}
          whileInView={reduce ? {} : { opacity: 1, y: 0 }}
          viewport={{ once: true, margin: '-12% 0px' }}
          transition={{ duration: 0.9, delay: 0.12, ease: [0.22, 1, 0.36, 1] }}
        >
          <a className="btn btn--primary btn--lg" href={DOWNLOAD} target="_blank" rel="noreferrer">
            <Download size={19} strokeWidth={2.6} />
            <span>Download Tangent</span>
          </a>
          <a className="btn btn--ghost btn--lg" href={REPO} target="_blank" rel="noreferrer">
            <Github size={18} strokeWidth={2.2} />
            <span>Explore on GitHub</span>
          </a>
        </motion.div>

        <motion.p
          className="get-note"
          initial={reduce ? {} : { opacity: 0 }}
          whileInView={reduce ? {} : { opacity: 1 }}
          viewport={{ once: true }}
          transition={{ duration: 0.9, delay: 0.3 }}
        >
          Grab the latest build from <a href={RELEASES} target="_blank" rel="noreferrer">Releases</a> — or
          compile it yourself in <a href="#terminal">three commands</a>. Requires an
          <strong> Apple Silicon Mac (M1+)</strong>, <strong>macOS 13.0+</strong>, and a desktop you
          refuse to leave sad. Source lives under{' '}
          <a href={LICENSE} target="_blank" rel="noreferrer"><Scale size={12} /> GPL-3.0</a>.
        </motion.p>
      </div>
    </section>
  )
}
