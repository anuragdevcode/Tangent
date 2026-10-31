import { WordReveal, Reveal } from '../components/Shared.jsx'

export default function Statement() {
  return (
    <section className="statement" aria-label="Why Tangent exists">
      <div className="kwrap">
        <Reveal>
          <p className="eyebrow">Why Tangent exists</p>
        </Reveal>
        <WordReveal
          className="statement-line"
          text="Static wallpapers are just screenshots with commitment issues."
        />
        <WordReveal
          className="statement-line statement-line--muted"
          text="Your GPU is right there. Tangent puts it to work — every Space, every display."
        />
      </div>
    </section>
  )
}
