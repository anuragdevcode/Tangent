import { SectionHead, Reveal } from '../components/Shared.jsx'
import { Marquee, NumberTicker, SpotlightCard } from '../components/Fx.jsx'

const STATS = [
  {
    big: '167',
    value: 167,
    small: 'automated compatibility checks parse packs, hotkeys, layouts and bridges — all passing',
  },
  {
    big: '~30 fps',
    value: 30,
    prefix: '~',
    suffix: ' fps',
    small: 'VP9 rendered at the desktop layer on an M2, using about 6.6% CPU',
  },
  {
    big: '50 dylibs',
    value: 50,
    suffix: ' dylibs',
    small: 'bundled libmpv closure (~61 MB), every install name rewritten to @rpath',
  },
  {
    big: 'AppKit',
    small: 'the entire UI. No Electron, no Chromium, no embedded browser wearing a trench coat',
  },
  {
    big: '−2 147 483 622',
    small: 'the window level between the desktop picture and your icons',
  },
  {
    big: 'GPL-3.0',
    small: 'every file of it. Browse or ship it, the source stays open',
  },
]

const CAPABILITIES = [
  'VP9',
  'AV1',
  'Matroska',
  'Web wallpapers',
  'GIF',
  'Image',
  'Per-display',
  'Click-through',
  'Hardware-decoded',
  'AppKit',
  'GPL-3.0',
]

export default function Credibility() {
  return (
    <section className="section cred-sec">
      <div className="kwrap">
        <SectionHead
          align="center"
          eyebrow="For the skeptics"
          title={<>Native. Not a browser in a trench coat.</>}
          lede="Every number below is reproduced by a CLI flag you can run yourself — Tangent ships its own receipts."
        />
      </div>

      <div className="cred-band">
        <Marquee items={CAPABILITIES} />
      </div>

      <div className="kwrap">
        <div className="stat-grid">
          {STATS.map((s, i) => (
            <Reveal key={s.big} delay={i * 0.07}>
              <SpotlightCard className="stat">
                <p className="stat-big">
                  {s.value != null ? (
                    <NumberTicker
                      value={s.value}
                      prefix={s.prefix}
                      suffix={s.suffix}
                      className="stat-ticker"
                    />
                  ) : (
                    s.big
                  )}
                </p>
                <p className="stat-small">{s.small}</p>
              </SpotlightCard>
            </Reveal>
          ))}
        </div>
      </div>
    </section>
  )
}
