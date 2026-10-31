import { SectionHead, Reveal } from '../components/Shared.jsx'

const LINES = [
  { p: '# three commands and a Mac', c: 'comment' },
  { p: '$ git clone https://github.com/anuragdevcode/Tangent.git', c: 'cmd' },
  { p: '$ cd Tangent && brew install mpv        # build-time headers', c: 'cmd' },
  { p: '$ ./build.sh --universal                 # arm64 (+ x86_64)', c: 'cmd' },
  { p: '$ open build/Tangent.app                 # menu bar appears', c: 'cmd' },
]

const FLAGS = [
  ['--set ~/Wallpapers/aurora --display 2 --ephemeral', 'apply to one display, don\'t touch the layout'],
  ['--library', 'open the library window at launch'],
  ['--probe-mpv loop.webm', 'decode a codec stack and print frames'],
  ['--snapshot-library /tmp/lib.png', 'render the UI to PNG, no screen-recording perms'],
  ['--test', 'the 301-check compatibility suite'],
]

export default function Terminal() {
  return (
    <section id="terminal" className="section term-sec">
      <div className="kwrap">
        <SectionHead
          align="left"
          eyebrow="Build from source"
          title={<>For people who read the makefile.</>}
          lede="No Xcode required — Command Line Tools and swiftc are enough. Homebrew mpv is a build-time dependency; the app bundles libmpv and its dependency closure so VP9, AV1 and Matroska play without Homebrew at runtime."
        />
      </div>

      <div className="kwrap">
        <Reveal>
          <div className="terminal mac-window" data-native-scroll>
            <div className="mw-bar">
              <span className="mw-dots" aria-hidden="true"><i /><i /><i /></span>
              <span className="mw-title">Terminal — Tangent</span>
            </div>
            <pre className="term-body" tabIndex={0} role="region" aria-label="Build commands">
              {LINES.map((l, i) => (
                <code key={i} className={`term-${l.c}`}>
                  {l.p}
                </code>
              ))}
              <code className="term-cursor" aria-hidden="true">▮</code>
            </pre>
          </div>
        </Reveal>

        <Reveal delay={0.1}>
          <div className="flag-grid">
            <p className="flag-title">And if your wallpaper pipeline is scripted, it&rsquo;s a first-class citizen:</p>
            {FLAGS.map(([flag, desc]) => (
              <div key={flag} className="flag-row">
                <code className="flag-cmd">{flag}</code>
                <span>{desc}</span>
              </div>
            ))}
          </div>
        </Reveal>
      </div>
    </section>
  )
}
