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
        hintLabel.text = "Tippen = fertig  ·  ← wischen = verwerfen"

        let header = UIStackView(arrangedSubviews: [markView, statusLabel, UIView(), timeLabel])
        header.spacing = 8
        header.alignment = .center
        waveform.translatesAutoresizingMaskIntoConstraints = false

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
        recordingStack.alpha = 1
        messageStack.alpha = 0
        accessibilityLabel = "Paply hört zu. Tippen beendet, nach links wischen verwirft."
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
        recordingStack.alpha = 0
        messageStack.alpha = 1
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

/// Wellenform: Balken = die letzten Pegelwerte, älteste links.
final class WaveformView: UIView {
    static let barCount = 36
    private var bars: [CALayer] = []
    var barColor: UIColor = Brand.recordInk {
        didSet { bars.forEach { $0.backgroundColor = barColor.cgColor } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        for _ in 0..<Self.barCount {
            let bar = CALayer()
            bar.backgroundColor = barColor.cgColor
            bar.cornerRadius = 2
            layer.addSublayer(bar)
            bars.append(bar)
        }
        isUserInteractionEnabled = false
        setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        update(levels: [])
    }

    /// `levels` 0…1, älteste zuerst; fehlende Werte links werden als Stille gezeichnet.
    func update(levels: [Float]) {
        let count = bars.count
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > 0 else { return }
        let gap: CGFloat = 4
        let barWidth = max(2, (width - gap * CGFloat(count - 1)) / CGFloat(count))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, bar) in bars.enumerated() {
            let index = levels.count - count + i
            let level = index >= 0 ? CGFloat(levels[index]) : 0
            let h = max(4, height * (0.08 + 0.92 * level))
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
