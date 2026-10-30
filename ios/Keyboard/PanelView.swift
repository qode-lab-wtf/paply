import UIKit

/// Die Paply-Ebene: eine große Fläche mit Wellenform und Zeit (Aufnahme) bzw. einer
/// klaren Meldung mit nächstem Schritt. Nur UIKit + CALayer – die Tastatur bleibt klein.
final class PanelView: UIView {
    enum Look {
        case green
        case forest
    }

    struct Message {
        var title: String
        var subtitle: String?
        var action: String?
        var secondary: String?
        var spinner = false
        var check = false
    }

    let card = UIView()
    let waveform = WaveformView()
    let globeButton = UIButton(type: .system)
    let actionButton = UIButton(type: .system)
    let secondaryButton = UIButton(type: .system)

    private let gradient = CAGradientLayer()
    private let markView = MarkView()
    private let statusLabel = UILabel()
    private let timeLabel = UILabel()
    private let hintLabel = UILabel()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let checkView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
    private let recordingStack = UIStackView()
    private let messageStack = UIStackView()
    private var look: Look = .green

    override init(frame: CGRect) {
        super.init(frame: frame)
        build()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        backgroundColor = .clear

        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        card.clipsToBounds = true
        addSubview(card)
        gradient.colors = [Brand.recordTop.cgColor, Brand.recordBottom.cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        card.layer.insertSublayer(gradient, at: 0)

        // Kopfzeile: Marke + Status links, Zeit rechts
        markView.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        timeLabel.textAlignment = .right
        hintLabel.font = .systemFont(ofSize: 13, weight: .medium)
        hintLabel.textAlignment = .center
        hintLabel.adjustsFontSizeToFitWidth = true
        hintLabel.minimumScaleFactor = 0.8
        hintLabel.text = Self.recordingHint

        let header = UIStackView(arrangedSubviews: [markView, statusLabel, UIView(), timeLabel])
        header.spacing = 8
        header.alignment = .center
        // Kopf und Hinweis behalten ihre Höhe, die Wellenform nimmt den Rest. Ohne diese
        // Prioritäten konnte Auto Layout ihr 0 pt geben – dann blieb sie unsichtbar/still.
        header.setContentHuggingPriority(.required, for: .vertical)
        hintLabel.setContentHuggingPriority(.required, for: .vertical)
        header.setContentCompressionResistancePriority(.required, for: .vertical)
        hintLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        waveform.translatesAutoresizingMaskIntoConstraints = false
        waveform.setContentHuggingPriority(UILayoutPriority(1), for: .vertical)
        waveform.setContentCompressionResistancePriority(UILayoutPriority(1), for: .vertical)

        recordingStack.axis = .vertical
        recordingStack.spacing = 8
        recordingStack.addArrangedSubview(header)
        recordingStack.addArrangedSubview(waveform)
        recordingStack.addArrangedSubview(hintLabel)
        recordingStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(recordingStack)

        // Meldung: Titel, Text, Knöpfe
        titleLabel.font = .systemFont(ofSize: 19, weight: .bold)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        subtitleLabel.font = .systemFont(ofSize: 14.5)
        subtitleLabel.textAlignment = .center
        subtitleLabel.numberOfLines = 4
        spinner.color = Brand.greenBright
        checkView.tintColor = Brand.recordInk
        checkView.contentMode = .scaleAspectFit
        checkView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 40, weight: .semibold)
        styleButton(actionButton, filled: true)
        styleButton(secondaryButton, filled: false)
        let buttons = UIStackView(arrangedSubviews: [secondaryButton, actionButton])
        buttons.spacing = 10
        buttons.alignment = .center
        messageStack.axis = .vertical
        messageStack.alignment = .center
        messageStack.spacing = 8
        [spinner, checkView, titleLabel, subtitleLabel, buttons].forEach(messageStack.addArrangedSubview)
        messageStack.setCustomSpacing(14, after: subtitleLabel)
        messageStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(messageStack)

        // 🌐 nur, wenn iOS keine eigene Umschalttaste zeigt (Geräte ohne Face ID)
        globeButton.setImage(UIImage(systemName: "globe"), for: .normal)
        globeButton.translatesAutoresizingMaskIntoConstraints = false
        globeButton.isHidden = true
        globeButton.accessibilityLabel = "Nächste Tastatur"
        card.addSubview(globeButton)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            card.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),

            waveform.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            markView.widthAnchor.constraint(equalToConstant: 17),
            markView.heightAnchor.constraint(equalToConstant: 18),

            recordingStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            recordingStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            recordingStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            recordingStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -12),

            messageStack.leadingAnchor.constraint(greaterThanOrEqualTo: card.leadingAnchor, constant: 20),
            messageStack.trailingAnchor.constraint(lessThanOrEqualTo: card.trailingAnchor, constant: -20),
            messageStack.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            messageStack.centerYAnchor.constraint(equalTo: card.centerYAnchor),

            globeButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            globeButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
            globeButton.widthAnchor.constraint(equalToConstant: 40),
            globeButton.heightAnchor.constraint(equalToConstant: 40),
        ])
        apply(look: .green)
        showRecording(status: "Paply hört zu")
    }

    private func styleButton(_ button: UIButton, filled: Bool) {
        var config = filled ? UIButton.Configuration.filled() : UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 18, bottom: 9, trailing: 18)
        button.configuration = config
        button.isHidden = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = card.bounds
        CATransaction.commit()
    }

    // MARK: Zustände

    func showRecording(status: String) {
        apply(look: .green)
        statusLabel.text = status
        hintLabel.text = Self.recordingHint
        waveform.mode = .live
        crossfade {
            self.recordingStack.alpha = 1
            self.messageStack.alpha = 0
            self.statusLabel.alpha = 1
            self.timeLabel.alpha = 1
            self.hintLabel.alpha = 1
        }
        accessibilityLabel = "Paply hört zu. Tippen beendet, nach links wischen verwirft."
    }

    /// Warten aufs Polieren (auch „Erneut senden“): kein Text, die Welle zieht sich zu einem
    /// ruhigen, wandernden Schimmer zusammen (wie der Polier-Ring der Desktop-Pille).
    func showWorking() {
        apply(look: .green)
        waveform.mode = .working
        hintLabel.text = "dauert etwas länger"
        crossfade {
            self.recordingStack.alpha = 1
            self.messageStack.alpha = 0
            self.statusLabel.alpha = 0
            self.timeLabel.alpha = 0
            self.hintLabel.alpha = 0
        }
        accessibilityLabel = "Wird poliert"
        UIAccessibility.post(notification: .layoutChanged, argument: self)
    }

    /// Nach ≥ 6 s: dezenter Hinweis, damit man bei schlechtem Netz nicht zweifelt.
    func showSlowHint() {
        UIView.animate(withDuration: 0.6) { self.hintLabel.alpha = 1 }
        accessibilityLabel = "Wird poliert, dauert etwas länger"
    }

    private static let recordingHint = "Tippen = fertig  ·  ← wischen = verwerfen"

    /// Weicher Übergang zwischen Aufnahme, Warten und Meldung.
    private func crossfade(_ changes: @escaping () -> Void) {
        if UIAccessibility.isReduceMotionEnabled || window == nil {
            changes()
        } else {
            UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
        }
    }

    func setTime(_ text: String) {
        if timeLabel.text != text { timeLabel.text = text }
    }

    func showMessage(_ message: Message, look: Look) {
        apply(look: look)
        titleLabel.text = message.title
        subtitleLabel.text = message.subtitle
        subtitleLabel.isHidden = message.subtitle == nil
        spinner.isHidden = !message.spinner
        if message.spinner { spinner.startAnimating() } else { spinner.stopAnimating() }
        checkView.isHidden = !message.check
        configure(actionButton, title: message.action, filled: true)
        configure(secondaryButton, title: message.secondary, filled: false)
        waveform.mode = .live
        crossfade {
            self.recordingStack.alpha = 0
            self.messageStack.alpha = 1
        }
        accessibilityLabel = [message.title, message.subtitle].compactMap { $0 }.joined(separator: ". ")
    }

    private func configure(_ button: UIButton, title: String?, filled: Bool) {
        button.isHidden = title == nil
        guard let title, var config = button.configuration else { return }
        var attributes = AttributeContainer()
        attributes.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        config.attributedTitle = AttributedString(title, attributes: attributes)
        switch (look, filled) {
        case (.green, true):
            config.baseBackgroundColor = Brand.forest
            config.baseForegroundColor = Brand.text
        case (.forest, true):
            config.baseBackgroundColor = Brand.greenBright
            config.baseForegroundColor = Brand.forest
        case (.green, false):
            config.baseForegroundColor = Brand.recordInk
        case (.forest, false):
            config.baseForegroundColor = Brand.text.withAlphaComponent(0.75)
        }
        button.configuration = config
    }

    private func apply(look: Look) {
        self.look = look
        let ink = look == .green ? Brand.recordInk : Brand.text
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.25)
        gradient.colors = look == .green
            ? [Brand.recordTop.cgColor, Brand.recordBottom.cgColor]
            : [Brand.forest.cgColor, Brand.forestDeep.cgColor]
        CATransaction.commit()
        statusLabel.textColor = ink
        timeLabel.textColor = ink
        hintLabel.textColor = ink.withAlphaComponent(0.6)
        titleLabel.textColor = ink
        subtitleLabel.textColor = ink.withAlphaComponent(0.72)
        globeButton.tintColor = ink.withAlphaComponent(0.7)
        markView.monochrome = look == .green ? Brand.recordInk : nil
        waveform.barColor = look == .green ? Brand.recordInk.withAlphaComponent(0.85) : Brand.greenBright
    }
}

/// Wellenform: Balken = die letzten Pegelwerte (älteste links). Jeder Balken folgt seinem
/// Zielwert mit einer Feder (SMOOTH der Desktop-Pille, k=420 c=30), so fließt die Welle
/// statt zu springen. In Ruhe atmen die Balken dezent.
/// Arbeitsmodus (Polieren): Die Balken ziehen sich zur Mitte zu einer schmalen Pille zusammen,
/// durch die ein weicher Schimmer wandert (1,6 s wie der Polier-Ring am Desktop). Bei
/// reduzierter Bewegung nur ein langsames, gleichmäßiges Pulsieren.
final class WaveformView: UIView {
    enum Mode { case live, working }

    static let barCount = 36
    var mode: Mode = .live {
        didSet {
            guard mode != oldValue, mode == .live else { return }
            bars.forEach { $0.opacity = 1 }
        }
    }
    private var bars: [CALayer] = []
    private var targets = [Double](repeating: 0, count: barCount)
    private var values = [Double](repeating: 0, count: barCount)
    private var velocities = [Double](repeating: 0, count: barCount)
    var barColor: UIColor = Brand.recordInk {
        didSet { bars.forEach { $0.backgroundColor = barColor.cgColor } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.backgroundColor = barColor.cgColor
            layer.addSublayer(bar)
            bars.append(bar)
        }
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        render(time: CACurrentMediaTime())
    }

    /// Zurück auf Ruhe (neues Diktat)
    func reset() {
        targets = [Double](repeating: 0, count: Self.barCount)
        values = targets
        velocities = targets
        render(time: CACurrentMediaTime())
    }

    /// Neue Zielwerte 0…1, älteste zuerst; fehlende Werte links = Stille.
    func setTargets(_ levels: [Float]) {
        let count = Self.barCount
        for i in 0..<count {
            let index = levels.count - count + i
            targets[i] = index >= 0 ? Double(levels[index]) : 0
        }
    }

    /// Ein Bild weiter: Federn integrieren (halbimplizites Euler) und zeichnen.
    func step(dt: Double, time: Double) {
        if mode == .working { setWorkingTargets(time: time) }
        let dt = min(max(dt, 0), 1.0 / 30)
        let k = Brand.Spring.smooth.stiffness
        let c = Brand.Spring.smooth.damping
        for i in 0..<Self.barCount {
            velocities[i] += (k * (targets[i] - values[i]) - c * velocities[i]) * dt
            values[i] += velocities[i] * dt
        }
        render(time: time)
    }

    /// Ziel- und Deckkraft je Balken im Arbeitsmodus; die Federn machen den Übergang weich.
    private func setWorkingTargets(time: Double) {
        let n = Double(Self.barCount)
        let center = (n - 1) / 2
        let reduced = UIAccessibility.isReduceMotionEnabled
        let pulse = 0.5 + 0.5 * sin(time * 2 * .pi / 2.4)
        let phase = time.truncatingRemainder(dividingBy: 1.6) / 1.6
        let position = -6 + phase * (n + 12)
        for i in 0..<Self.barCount {
            let x = Double(i)
            // Zur Mitte zusammengezogen: außen fast nichts, innen eine Pille
            let envelope = exp(-pow(x - center, 2) / (2 * pow(n / 5.5, 2)))
            let height: Double
            let opacity: Double
            if reduced {
                height = 0.12 * envelope
                opacity = (0.45 + 0.4 * pulse) * (0.25 + 0.75 * envelope)
            } else {
                let shimmer = exp(-pow(x - position, 2) / (2 * 3.2 * 3.2))
                height = (0.09 + 0.24 * shimmer) * envelope
                opacity = (0.3 + 0.65 * shimmer) * (0.2 + 0.8 * envelope)
            }
            targets[i] = height
            bars[i].opacity = Float(opacity)
        }
    }

    private func render(time: Double) {
        let count = bars.count
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        let gap: CGFloat = 4
        let barWidth = max(2, (width - gap * CGFloat(count - 1)) / CGFloat(count))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            // dezentes Atmen in Ruhe (langsame Welle über die Balken); im Arbeitsmodus nicht
            let breath = mode == .working ? 0 : 0.07 + 0.05 * (0.5 + 0.5 * sin(time * 2 * .pi * 0.45 + Double(i) * 0.42))
            let level = max(breath, min(1, max(0, values[i])))
            let h = max(4, height * CGFloat(level))
            bar.frame = CGRect(x: CGFloat(i) * (barWidth + gap), y: (height - h) / 2, width: barWidth, height: h)
            bar.cornerRadius = min(barWidth / 2, 2.5)
        }
        CATransaction.commit()
    }
}

/// Die Marke „p-Kopf“ als zwei Formebenen (klein, ohne Bilder).
final class MarkView: UIView {
    private let head = CAShapeLayer()
    private let beak = CAShapeLayer()
    var monochrome: UIColor? {
        didSet { applyColors() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.addSublayer(beak)
        layer.addSublayer(head)
        isUserInteractionEnabled = false
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        var transform = PaplyMarkGeometry.transform(fitting: bounds)
        head.path = PaplyMarkGeometry.head.copy(using: &transform)
        beak.path = PaplyMarkGeometry.beak.copy(using: &transform)
    }

    private func applyColors() {
        head.fillColor = (monochrome ?? PaplyMarkGeometry.headColors.top).cgColor
        beak.fillColor = (monochrome ?? PaplyMarkGeometry.beakColors.bottom).cgColor
    }
}
