import UIKit

/// Paply-Tastatur: schlanke Sprach-Ebene in der 🌐-Liste. Erscheint sie, nimmt sie sofort auf
/// (die App hält das Mikro bereit). Tipp irgendwo = fertig, nach links wischen = verwerfen.
/// Kein PaplyKit, kein Netzwerk – nur App Group, Darwin-Signale und UIKit.
final class KeyboardViewController: UIInputViewController {
    private enum State: Equatable {
        case idle
        /// `record` gesendet, warte auf Bestätigung der App
        case connecting
        case recording(startNs: UInt64)
        case polishing
        /// `unpolished`: Polieren scheiterte technisch, Rohtext eingesetzt (dezentes Zeichen)
        case inserted(unpolished: Bool)
        /// Keine Sprache erkannt: nichts eingesetzt, Tipp = neu sprechen, links wischen = zurück
        case empty
        case pending
        /// App wird per URL geöffnet; sie startet das Diktat selbst
        case opening
        case failure(Failure)
    }

    private enum Failure: Equatable {
        case noFullAccess
        case noSession
        case interrupted
        case noKey
        case notResponding
        case openFailed
        /// Endgültiger Fehler; `retryable` = die App hält das Audio noch (max. 10 Min)
        case network(String, retryable: Bool)
    }

    private let panel = PanelView()
    private var heightConstraint: NSLayoutConstraint?
    private var state: State = .idle
    private var dictationID: String?
    private var pending: PendingText?
    private var tokens: [DarwinToken] = []
    private var levels: LevelChannel?
    // Pegel-Anzeige: Kanal je Diktat, Statistik für `kb.levels`, adaptive Zeichenverzögerung
    private var levelTag: UInt32 = 0
    private var lastLevelCount: UInt64 = 0
    private var lastLevelArrival: CFTimeInterval = 0
    private var levelGapMs: Double = 100
    private var levelStats: [Float] = []
    private var levelsLogged = false
    private var lastTickTime: CFTimeInterval = 0
    private var lastOpenAttempt: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var haptic: UIImpactFeedbackGenerator?
    /// Die App hat in diesem Diktat Sprache erkannt
    private var speechSeen = false
    private var lastPongNs: UInt64 = 0
    private var recordingSinceNs: UInt64 = 0
    private var timers: [Task<Void, Never>] = []
    private var keepAlive: Task<Void, Never>?
    private var ignoreResult = false

    // Messpunkte (MonoClock)
    private let loadNs = MonoClock.now()
    private var appearNs: UInt64 = 0
    private var finishTapNs: UInt64 = 0
    private var firstFrameLogged = false
    private var layoutLog = 0
    private var lastLoggedHeight: CGFloat = -1
    private static var appearCount = 0

    private static let attachKey = "kbAttachID"
    private static let attachNsKey = "kbAttachNs"

    /// Ohne Pong so lange warten, bevor die App geöffnet wird. Ist die Tastatur vorher weg
    /// (Durchschalten mit 🌐), passiert gar nichts.
    private static let noSessionAfter: Duration = .milliseconds(1_000)

    // MARK: Lebenszyklus

    override func viewDidLoad() {
        super.viewDidLoad()
        hasDictationKey = true // System-Mikro unter Paply ausblenden

        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // Wischen beginnt immer und entscheidet erst beim Loslassen. Der Tipp greift nur,
        // wenn kein Wischen begonnen hat (echter Tipp ohne nennenswerte Bewegung).
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        panel.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.delegate = self
        tap.require(toFail: pan)
        panel.addGestureRecognizer(tap)
        panel.actionButton.addTarget(self, action: #selector(handleAction), for: .touchUpInside)
        panel.secondaryButton.addTarget(self, action: #selector(handleSecondary), for: .touchUpInside)
        panel.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)

        Diag.log("kb.load", [
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: loadNs)),
            "fullAccess": .b(hasFullAccess),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        appearNs = MonoClock.now()
        Self.appearCount += 1
        firstFrameLogged = false
        layoutLog = 0
        speechSeen = false
        ignoreResult = false
        finishTapNs = 0
        panel.card.transform = .identity
        panel.card.alpha = 1
        panel.globeButton.isHidden = !needsInputModeSwitchKey
        applyHeight(landscape: isLandscape(width: view.bounds.width))

        var fields: DiagFields = [
            "n": .i(Self.appearCount),
            "fullAccess": .b(hasFullAccess),
            "needsGlobe": .b(needsInputModeSwitchKey),
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: appearNs)),
            "sinceLoadMs": .ms(MonoClock.ms(from: loadNs, to: appearNs)),
            "height": .opt(heightConstraint.map { Double($0.constant) }),
        ]
        fields.merge(ProcessMetrics.fields) { a, _ in a }
        Diag.log("kb.appear", fields)
        HostProbe.log(from: self)

        guard hasFullAccess, AppGroup.baseURL != nil else {
            show(.failure(.noFullAccess))
            return
        }
        // Speicher-Selbsttest: eigene Markierung schreiben, die der App lesen (abseits vom Main-Thread)
        DispatchQueue.global(qos: .utility).async { _ = StorageSelfTest.run(as: .keyboard) }
        subscribe()
        startDisplayLink()

        if let text = takePendingText() {
            // Wartender Text wird genau einmal angeboten
            pending = text
            show(.pending)
            Diag.log("kb.pending.offer", ["id": .s(String(text.id.prefix(8))), "len": .i(text.text.count)])
        } else if let attachID = freshAttachID() {
            attach(to: attachID)
        } else {
            startRecording()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Diag.log("kb.didAppear", [
            "sinceAppearMs": .ms(MonoClock.msSince(appearNs)),
            "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: MonoClock.now())),
            "viewH": .d(Double(view.bounds.height)),
        ])
        // Eigene Höhe für die Höhenmessung der Testseite melden, wenn sie sich gesetzt hat
        schedule(after: .milliseconds(600)) { controller in
            guard controller.hasFullAccess else { return }
            SharedStore.write(KeyboardReport(
                viewHeight: Double(controller.view.bounds.height),
                landscape: controller.isLandscape(width: controller.view.bounds.width),
                ns: MonoClock.now()
            ), .keyboardReport)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        var fields: DiagFields = ["state": .s(stateName), "visibleMs": .ms(MonoClock.msSince(appearNs)), "speech": .b(speechSeen)]
        fields.merge(ProcessMetrics.fields) { a, _ in a }
        Diag.log("kb.disappear", fields)
        switch state {
        case .connecting, .recording:
            logLevelStats(reason: "disappear")
            guard let id = dictationID else { break }
            if speechSeen {
                // Echtes Diktat nicht verlieren: fertig machen, beim nächsten 🌐 einmal anbieten
                send(.finishLater, id: id)
                Diag.log("kb.disappear.defer", ["id": .s(String(id.prefix(8)))])
            } else {
                // Weg vor erkannter Sprache (z. B. Durchschalten): still verwerfen
                send(.cancel, id: id)
                Diag.log("kb.discard.disappear", ["id": .s(String(id.prefix(8)))])
            }
        case .polishing:
            if let id = dictationID, !ignoreResult {
                send(.finishLater, id: id)
                Diag.log("kb.disappear.defer", ["id": .s(String(id.prefix(8))), "polishing": .b(true)])
            }
        case .pending:
            Diag.log("kb.pending.dropped", ["len": .i(pending?.text.count ?? 0)])
            pending = nil
        default:
            break
        }
        teardown()
        if state != .opening { state = .idle }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        applyHeight(landscape: isLandscape(width: size.width))
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Start-Flackern der Höhe messen (0 → Vollbild → Zielhöhe)
        let height = view.bounds.height
        if height != lastLoggedHeight, layoutLog < 12, appearNs > 0, MonoClock.msSince(appearNs) < 3_000 {
            layoutLog += 1
            lastLoggedHeight = height
            Diag.log("kb.layout", ["h": .d(Double(height)), "w": .d(Double(view.bounds.width)), "sinceAppearMs": .ms(MonoClock.msSince(appearNs))])
        }
    }

    // MARK: Höhe

    /// Die Tastatur ist so breit wie der Bildschirm in der jeweiligen Lage. Breiter als die
    /// kurze Bildschirmseite = Querformat. Ohne Breite (vor dem ersten Layout): Bildschirmlage.
    private func isLandscape(width: CGFloat) -> Bool {
        let screen = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        guard width > 0 else { return screen.width > screen.height }
        return width > min(screen.width, screen.height) + 1
    }

    /// Höhe = Apples Tastaturhöhe (gemessen auf der Testseite), sonst Standardtabelle.
    private func applyHeight(landscape: Bool) {
        let screen = view.window?.windowScene?.screen.bounds.size ?? UIScreen.main.bounds.size
        let measured = SharedSettings.keyboardHeights.targetViewHeight(landscape: landscape)
        let fallback = KeyboardHeightTable.defaultViewHeight(screenWidth: Double(screen.width), screenHeight: Double(screen.height), landscape: landscape)
        guard let target = measured ?? fallback else {
            heightConstraint?.isActive = false
            return
        }
        if heightConstraint == nil {
            let constraint = view.heightAnchor.constraint(equalToConstant: CGFloat(target))
            constraint.priority = UILayoutPriority(999)
            heightConstraint = constraint
        }
        heightConstraint?.constant = CGFloat(target)
        heightConstraint?.isActive = true
        Diag.log("kb.height", ["target": .d(target), "measured": .b(measured != nil), "landscape": .b(landscape)])
    }

    // MARK: Ablauf

    private func startRecording() {
        let id = UUID().uuidString
        dictationID = id
        resetLevels(for: id)
        speechSeen = false
        finishTapNs = 0
        lastPongNs = 0
        show(.connecting)
        send(.record, id: id)
        DarwinBus.shared.post(.ping)
        haptic = UIImpactFeedbackGenerator(style: .light)
        haptic?.prepare()
        schedule(after: .milliseconds(450)) { $0.checkAck(stage: .first) }
    }

    /// Nach Start per URL: das Diktat läuft schon in der App – nur anschließen.
    private func attach(to id: String) {
        clearAttachID()
        dictationID = id
        resetLevels(for: id)
        lastPongNs = 0
        show(.connecting)
        send(.record, id: id) // idempotent: die App bestätigt nur
        DarwinBus.shared.post(.ping)
        haptic = UIImpactFeedbackGenerator(style: .light)
        haptic?.prepare()
        Diag.log("kb.attach", ["id": .s(String(id.prefix(8)))])
        schedule(after: .milliseconds(450)) { $0.checkAck(stage: .first) }
    }

    private enum AckStage: String {
        /// 450 ms: noch keine Bestätigung → nochmal pingen
        case first
        /// ≥ 1000 ms: ohne Pong gilt die Sitzung als weg
        case noPong
        /// App lebt (Pong), bestätigt aber nicht
        case slow
    }

    private func checkAck(stage: AckStage) {
        guard state == .connecting else { return }
        readState()
        guard state == .connecting else { return }
        let session = SharedStore.read(SessionState.self, .session)
        let alive = lastPongNs > appearNs
        Diag.log("kb.ack.missing", ["stage": .s(stage.rawValue), "pong": .b(alive), "status": .opt(session?.status.rawValue)])
        switch stage {
        case .first:
            if alive {
                schedule(after: .milliseconds(1_000)) { $0.checkAck(stage: .slow) }
            } else {
                DarwinBus.shared.post(.ping)
                schedule(after: Self.noSessionAfter - .milliseconds(450)) { $0.checkAck(stage: .noPong) }
            }
        case .noPong:
            if alive {
                schedule(after: .milliseconds(1_000)) { $0.checkAck(stage: .slow) }
            } else {
                noSession(interrupted: session?.status == .interrupted)
            }
        case .slow:
            show(.failure(.notResponding))
        }
    }

    private func noSession(interrupted: Bool) {
        if SharedSettings.autoOpenApp {
            openApp(reason: interrupted ? "interrupted" : "no-session")
        } else {
            show(.failure(interrupted ? .interrupted : .noSession))
        }
    }

    private func finish() {
        guard case .recording = state, let id = dictationID else { return }
        finishTapNs = MonoClock.now()
        logLevelStats(reason: "finish")
        send(.finish, id: id)
        show(.polishing)
        Diag.log("kb.finish", ["id": .s(String(id.prefix(8)))])
        readResult() // falls schon da
    }

    private func discard() {
        let previous = state
        if previous == .connecting || isRecording { logLevelStats(reason: "discard") }
        if let id = dictationID, previous == .connecting || isRecording || isRetryableFailure {
            send(.cancel, id: id) // bei Fehler: behaltenes Audio in der App freigeben
        }
        if previous == .pending { pending = nil }
        if previous == .polishing { ignoreResult = true } // Ergebnis bleibt im Verlauf
        Diag.log("kb.discard.swipe", ["state": .s(name(of: previous)), "speech": .b(speechSeen), "id": .opt(dictationID.map { String($0.prefix(8)) })])
        state = .idle
        animateOut { [weak self] in self?.advance(reason: "discard") }
    }

    private func insert(_ text: String, source: String, result: DictationResult?) {
        let unpolished = result?.unpolished ?? false
        let output = Spacing.prefixed(text, after: textDocumentProxy.documentContextBeforeInput)
        textDocumentProxy.insertText(output)
        let timings = result?.timings
        Diag.log("kb.inserted", [
            "id": .opt((result?.dictationID ?? pending?.id).map { String($0.prefix(8)) }),
            "source": .s(source),
            "len": .i(output.count),
            "spaced": .b(output.count != text.count),
            "tapToInsertMs": finishTapNs > 0 ? .ms(MonoClock.msSince(finishTapNs)) : .null,
            "model": .opt(timings?.model),
            "chunked": timings?.chunked.map { .b($0) } ?? .null,
            "net": .opt(timings?.net),
            "opts": .opt(timings?.options),
            "unpolished": .b(unpolished),
        ])
        show(.inserted(unpolished: unpolished))
        schedule(after: .milliseconds(220)) { $0.advance(reason: "inserted") }
    }

    private func advance(reason: String) {
        Diag.log("kb.advance", ["reason": .s(reason)])
        advanceToNextInputMode()
    }

    private func openApp(reason: String) {
        guard let id = dictationID, let url = PaplyURL.sessionStart(dictationID: id, sentNs: MonoClock.now()) else { return }
        show(.opening)
        storeAttachID(id)
        Diag.log("kb.open", ["reason": .s(reason), "id": .s(String(id.prefix(8)))])
        AppOpener.open(url, from: self) { [weak self] variant, success in
            Diag.log("kb.open.result", ["variant": .s(variant), "ok": .b(success)])
            guard let self, !success, self.state == .opening else { return }
            self.clearAttachID()
            self.show(.failure(.openFailed))
        }
    }

    // MARK: App-Signale

    private func subscribe() {
        guard tokens.isEmpty else { return }
        let bus = DarwinBus.shared
        tokens = [
            bus.observe(.state) { [weak self] in self?.readState() },
            bus.observe(.speech) { [weak self] in self?.readState() },
            bus.observe(.result) { [weak self] in self?.readResult() },
            bus.observe(.pong) { [weak self] in self?.lastPongNs = MonoClock.now() },
        ]
    }

    private func readState() {
        guard let session = SharedStore.read(SessionState.self, .session) else { return }
        let waiting = state == .connecting || state == .opening
        guard let id = dictationID, let dictation = session.dictation, dictation.id == id else {
            if session.status == .interrupted, state == .connecting || isRecording {
                noSession(interrupted: true) // Variante A öffnet die App, B zeigt „Mikro aus“
            }
            return
        }
        if let code = dictation.errorCode, waiting {
            // Beim Öffnen der App ist „nicht bereit“ erwartet – die App startet gleich selbst.
            guard state == .connecting || code == .noAPIKey else { return }
            Diag.log("kb.refused", ["code": .s(code.rawValue)])
            switch code {
            case .noAPIKey: show(.failure(.noKey))
            case .interrupted: noSession(interrupted: true)
            case .sessionNotReady: noSession(interrupted: false)
            }
            return
        }
        switch dictation.phase {
        case .recording:
            if waiting {
                let from = name(of: state)
                clearAttachID()
                show(.recording(startNs: dictation.startedNs))
                recordingSinceNs = MonoClock.now()
                Diag.log("kb.recording", [
                    "id": .s(String(id.prefix(8))),
                    "from": .s(from),
                    "appearToRecordingMs": .ms(MonoClock.msSince(appearNs)),
                    "appRecordingSinceMs": .ms(MonoClock.msSince(dictation.startedNs)),
                ])
                startKeepAlive()
            }
        case .cancelled:
            // z. B. Wiederanlauf aus dem Leerlauf gescheitert → „Mikro aus“ wie bei Unterbrechung
            if isRecording {
                if session.status == .interrupted {
                    noSession(interrupted: true)
                } else {
                    show(.failure(.notResponding))
                }
            }
        default:
            break
        }
        if dictation.speechDetected, !speechSeen, isRecording {
            speechSeen = true
            haptic?.impactOccurred()
            Diag.log("kb.speech", ["sinceAppearMs": .ms(MonoClock.msSince(appearNs)), "fullAccess": .b(hasFullAccess)])
        }
    }

    private func readResult() {
        guard state == .polishing, !ignoreResult, let id = dictationID, let result = SharedStore.readResult(id: id) else { return }
        SharedStore.removeResult(id: id)
        let now = MonoClock.now()
        let t = result.timings
        Diag.log("kb.result", [
            "id": .s(String(id.prefix(8))),
            "tapToResultMs": .ms(MonoClock.ms(from: finishTapNs, to: now)),
            "tapToAppMs": .ms(MonoClock.ms(from: finishTapNs, to: result.finishReceivedNs)),
            "appProcessingMs": .ms(MonoClock.ms(from: result.finishReceivedNs, to: result.writtenNs)),
            "writtenToKbMs": .ms(MonoClock.ms(from: result.writtenNs, to: now)),
            "flushMs": .opt(t.flushMs),
            "transcribeMs": .opt(t.transcriptionDoneMs),
            "polishMs": .opt(t.polishDoneMs),
            "totalMs": .opt(t.totalMs),
            "audioS": .d(t.audioSeconds),
            "chunks": .i(t.chunkCount),
            "model": .opt(t.model),
            "chunked": t.chunked.map { .b($0) } ?? .null,
            "net": .opt(t.net),
            "opts": .opt(t.options),
            "unpolished": .b(result.unpolished ?? false),
            "retryable": .b(result.retryable ?? false),
            "noSpeech": .b(result.noSpeech ?? false),
            "len": .i(result.text.count),
            "error": .opt(result.errorMessage),
        ])
        if !result.text.isEmpty {
            insert(result.text, source: "dictation", result: result)
        } else if let error = result.errorMessage {
            show(.failure(.network(error, retryable: result.retryable ?? false)))
        } else {
            Diag.log("kb.noSpeech", ["id": .s(String(id.prefix(8))), "flag": .b(result.noSpeech ?? false)])
            show(.empty)
        }
    }

    // MARK: Gesten und Knöpfe

    @objc private func handleTap() {
        switch state {
        case .recording: finish()
        case .pending: insertPending()
        case .failure(.network(_, let retryable)): retryable ? retry() : startRecording()
        case .empty: startRecording()
        case .failure(.interrupted), .failure(.noSession), .failure(.notResponding), .failure(.openFailed):
            openApp(reason: "tap")
        default: break
        }
    }

    @objc private func handleAction() {
        switch state {
        case .pending: insertPending()
        case .failure(.noFullAccess): advance(reason: "noFullAccess")
        case .failure(.noKey), .failure(.noSession), .failure(.interrupted), .failure(.notResponding), .failure(.openFailed):
            openApp(reason: "button")
        case .failure(.network(_, let retryable)): retryable ? retry() : startRecording()
        case .empty: startRecording()
        default: break
        }
    }

    @objc private func handleSecondary() {
        if state == .pending {
            Diag.log("kb.pending.skipped", ["len": .i(pending?.text.count ?? 0)])
            pending = nil
            startRecording()
        } else {
            advance(reason: "secondary")
        }
    }

    /// Nach endgültigem Fehler: dieselbe Aufnahme erneut senden lassen.
    private func retry() {
        guard let id = dictationID else { return }
        finishTapNs = MonoClock.now()
        send(.retry, id: id)
        show(.polishing)
        startKeepAlive()
        Diag.log("kb.retry", ["id": .s(String(id.prefix(8)))])
    }

    private func insertPending() {
        guard let pending else { return }
        finishTapNs = 0
        insert(pending.text, source: "pending", result: nil)
        self.pending = nil
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard canDiscard else { return }
        let translation = pan.translation(in: panel)
        let dx = min(0, translation.x)
        switch pan.state {
        case .changed:
            panel.card.transform = CGAffineTransform(translationX: dx, y: 0)
            panel.card.alpha = 1 - min(0.5, abs(dx) / 400)
        case .ended:
            // Nur deutlich nach links verwirft; rechts, senkrecht oder zu kurz federt zurück.
            let velocity = pan.velocity(in: panel)
            let mostlyHorizontal = abs(translation.x) > abs(translation.y)
            if mostlyHorizontal, dx < -90 || (dx < -30 && velocity.x < -650) {
                discard()
            } else {
                springBack()
            }
        case .cancelled, .failed:
            springBack()
        default:
            break
        }
    }

    private var canDiscard: Bool {
        switch state {
        case .connecting, .recording, .pending, .polishing, .empty: true
        case .failure(.network(_, let retryable)): retryable
        default: false
        }
    }

    // MARK: Anzeige

    private func show(_ newState: State) {
        state = newState
        // Bildrate nur für Wellenform und Zeit (Verbinden + Aufnahme); das erste Bild wird immer gemessen
        displayLink?.isPaused = firstFrameLogged && !isLive
        switch newState {
        case .idle:
            break
        case .connecting:
            panel.showRecording(status: "Mikro …")
            panel.setTime("0:00")
        case .recording:
            panel.showRecording(status: "Paply hört zu")
            ensureLevels()
        case .polishing:
            panel.showMessage(.init(title: "Poliere …", subtitle: nil, spinner: true), look: .forest)
        case .inserted(let unpolished):
            panel.showMessage(.init(title: "Eingesetzt", subtitle: unpolished ? "ohne Polieren" : nil, check: true), look: .green)
        case .empty:
            panel.showMessage(.init(title: "Nichts verstanden", subtitle: "Tippen = neu sprechen · ← wischen = zurück", action: "Neu sprechen"), look: .forest)
        case .pending:
            let text = pending?.text ?? ""
            let preview = String(text.prefix(90)) + (text.count > 90 ? " …" : "")
            panel.showMessage(.init(title: "Wartender Text", subtitle: "„\(preview)“", action: "Einsetzen", secondary: "Neu sprechen"), look: .forest)
        case .opening:
            panel.showMessage(.init(title: "Paply schaltet das Mikro ein …", subtitle: "Danach oben links auf „◀︎“ tippen – du kannst gleich losreden.", spinner: true), look: .forest)
        case .failure(let failure):
            panel.showMessage(message(for: failure), look: .forest)
            Diag.log("kb.failure", ["kind": .s(name(of: newState))])
        }
        animatePop()
    }

    private func message(for failure: Failure) -> PanelView.Message {
        switch failure {
        case .noFullAccess:
            .init(title: "Vollzugriff fehlt",
                  subtitle: "Einstellungen → Allgemein → Tastatur → Tastaturen → Paply → „Vollen Zugriff erlauben“.",
                  action: "Weiter zur nächsten Tastatur")
        case .noSession:
            .init(title: "Paply ist nicht bereit", subtitle: "Einmal kurz Paply öffnen, dann hört Paply hier sofort zu.", action: "Paply starten", secondary: "Andere Tastatur")
        case .interrupted:
            .init(title: "Mikro aus", subtitle: "Zum Beispiel nach einem Anruf. Ein Tipp startet Paply neu.", action: "Paply starten", secondary: "Andere Tastatur")
        case .noKey:
            .init(title: "Kein Groq-Schlüssel", subtitle: "In der Paply-App unter Einstellungen eintragen.", action: "Paply öffnen", secondary: "Andere Tastatur")
        case .notResponding:
            .init(title: "Paply antwortet nicht", subtitle: "Ein Tipp öffnet Paply und startet das Mikro neu.", action: "Paply öffnen", secondary: "Andere Tastatur")
        case .openFailed:
            .init(title: "Paply ließ sich nicht öffnen", subtitle: "Öffne Paply einmal selbst und komm dann zurück.", action: "Nochmal versuchen", secondary: "Andere Tastatur")
        case .network(let text, let retryable):
            retryable
                ? .init(title: "Das hat nicht geklappt", subtitle: "\(text)\nTippen = erneut senden · ← wischen = verwerfen", action: "Erneut versuchen")
                : .init(title: "Das hat nicht geklappt", subtitle: text, action: "Neu aufnehmen", secondary: "Andere Tastatur")
        }
    }

    private func animatePop() {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        panel.card.transform = CGAffineTransform(scaleX: 0.97, y: 0.97)
        let params = UISpringTimingParameters(mass: 1, stiffness: Brand.Spring.bouncy.stiffness, damping: Brand.Spring.bouncy.damping, initialVelocity: .zero)
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: params)
        animator.addAnimations { [panel] in panel.card.transform = .identity }
        animator.startAnimation()
    }

    private func springBack() {
        let params = UISpringTimingParameters(mass: 1, stiffness: Brand.Spring.smooth.stiffness, damping: Brand.Spring.smooth.damping, initialVelocity: .zero)
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: params)
        animator.addAnimations { [panel] in
            panel.card.transform = .identity
            panel.card.alpha = 1
        }
        animator.startAnimation()
    }

    private func animateOut(then done: @escaping @MainActor () -> Void) {
        panel.showMessage(.init(title: "Verworfen"), look: .forest)
        let animator = UIViewPropertyAnimator(duration: 0.28, curve: .easeIn)
        animator.addAnimations { [panel] in
            panel.card.transform = CGAffineTransform(translationX: -panel.bounds.width * 0.6, y: 0)
            panel.card.alpha = 0
        }
        animator.addCompletion { _ in done() }
        animator.startAnimation()
    }

    // MARK: Pegel und Zeit (Bildrate)

    private func ensureLevels() {
        guard levels == nil else { return }
        lastOpenAttempt = CACurrentMediaTime()
        levels = LevelChannel.openReader()
    }

    private func resetLevels(for id: String) {
        levels = nil // je Diktat frisch öffnen
        levelTag = LevelChannel.tag(for: id)
        lastLevelCount = 0
        lastLevelArrival = 0
        levelGapMs = 100
        levelStats = []
        levelsLogged = false
        panel.waveform.reset()
    }

    /// Einmal pro Diktat: kamen Pegel an, und wie laut? (ohne Text)
    private func logLevelStats(reason: String) {
        guard !levelsLogged, let id = dictationID else { return }
        levelsLogged = true
        let sorted = levelStats.sorted()
        func round2(_ v: Float) -> Double { (Double(v) * 100).rounded() / 100 }
        Diag.log("kb.levels", [
            "id": .s(String(id.prefix(8))),
            "reason": .s(reason),
            "channel": .b(levels != nil),
            "received": .i(levelStats.count),
            "max": .d(round2(sorted.last ?? 0)),
            "median": .d(round2(sorted.isEmpty ? 0 : sorted[sorted.count / 2])),
            "gapMs": .ms(levelGapMs),
        ])
    }

    private func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick() {
        if !firstFrameLogged {
            firstFrameLogged = true
            Diag.log("kb.firstFrame", [
                "sinceAppearMs": .ms(MonoClock.msSince(appearNs)),
                "sinceProcessStartMs": .ms(MonoClock.ms(from: MonoClock.processStart, to: MonoClock.now())),
                "viewH": .d(Double(view.bounds.height)),
            ])
            displayLink?.isPaused = !isLive
        }
        let frameTime = displayLink?.timestamp ?? CACurrentMediaTime()
        let dt = lastTickTime > 0 ? frameTime - lastTickTime : 1.0 / 60
        lastTickTime = frameTime
        guard isLive else { return }
        if case .recording(let startNs) = state {
            let now = MonoClock.now()
            let seconds = Int(MonoClock.ms(from: startNs, to: now) / 1000)
            panel.setTime("\(seconds / 60):\(String(format: "%02d", seconds % 60))")
            updateLevelTargets(now: now, frameTime: frameTime)
        }
        panel.waveform.step(dt: dt, time: frameTime)
    }

    /// Pegel aus der geteilten Datei holen. Sie kommen blockweise (Tap-Puffer ~100 ms);
    /// gezeichnet wird um einen Block verzögert, damit die Welle gleichmäßig weiterläuft.
    private func updateLevelTargets(now: UInt64, frameTime: CFTimeInterval) {
        if levels == nil, frameTime - lastOpenAttempt > 0.5 { ensureLevels() }
        guard let levels, levels.tag == levelTag else { return }
        let count = levels.count
        if count > lastLevelCount {
            let fresh = Int(min(count - lastLevelCount, 60))
            levelStats.append(contentsOf: levels.recent(max: fresh, notAfter: .max))
            if levelStats.count > 4_000 { levelStats.removeFirst(levelStats.count - 4_000) }
            if lastLevelArrival > 0 {
                let gap = (frameTime - lastLevelArrival) * 1000
                levelGapMs = levelGapMs * 0.8 + min(gap, 500) * 0.2
            }
            lastLevelArrival = frameTime
            lastLevelCount = count
        }
        let delayMs = min(max(levelGapMs + 30, 60), 300)
        let limit = now > UInt64(delayMs * 1_000_000) ? now - UInt64(delayMs * 1_000_000) : now
        panel.waveform.setTargets(levels.recent(max: WaveformView.barCount, notAfter: limit))
    }

    // MARK: Hilfen

    private var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    /// Wellenform lebt: beim Verbinden (Atmen) und während der Aufnahme
    private var isLive: Bool { state == .connecting || isRecording }

    private var isRetryableFailure: Bool {
        if case .failure(.network(_, true)) = state { return true }
        return false
    }

    private func send(_ action: KeyboardCommand.Action, id: String) {
        SharedStore.write(KeyboardCommand(dictationID: id, action: action, sentNs: MonoClock.now()), .keyboardCommand)
        DarwinBus.shared.post(.command)
    }

    /// Lebenszeichen alle 2 s, solange aufgenommen oder poliert wird.
    /// - Aufnahme: 6 s ohne Pong → „Paply antwortet nicht“ (App tot oder ausgesetzt).
    /// - Polieren: Ergebnis zusätzlich selbst nachsehen (falls das Signal verloren ging);
    ///   10 s ohne Pong → „Paply antwortet nicht“. Kein Zeitlimit fürs Polieren selbst.
    private func startKeepAlive() {
        keepAlive?.cancel()
        keepAlive = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled else { return }
                let reference = max(self.lastPongNs, self.recordingSinceNs)
                if self.isRecording {
                    DarwinBus.shared.post(.ping)
                    if MonoClock.msSince(reference) > 6_000 {
                        Diag.log("kb.recording.noPong", ["sincePongMs": .ms(MonoClock.msSince(reference))])
                        self.show(.failure(.notResponding))
                    }
                } else if self.state == .polishing {
                    DarwinBus.shared.post(.ping)
                    self.readResult()
                    if self.state == .polishing, MonoClock.msSince(max(reference, self.finishTapNs)) > 10_000 {
                        Diag.log("kb.polishing.noPong")
                        self.show(.failure(.notResponding))
                    }
                }
            }
        }
    }

    private func schedule(after delay: Duration, _ action: @escaping @MainActor (KeyboardViewController) -> Void) {
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            action(self)
        }
        timers.append(task)
    }

    private func teardown() {
        tokens.forEach(DarwinBus.shared.remove)
        tokens = []
        timers.forEach { $0.cancel() }
        timers = []
        keepAlive?.cancel()
        keepAlive = nil
        displayLink?.invalidate()
        displayLink = nil
        haptic = nil
    }

    /// Wartenden Text lesen und sofort löschen: Er wird genau einmal angeboten.
    private func takePendingText() -> PendingText? {
        guard let text = SharedStore.read(PendingText.self, .pendingText) else { return nil }
        SharedStore.remove(.pendingText)
        return text.isFresh && !text.text.isEmpty ? text : nil
    }

    private func storeAttachID(_ id: String) {
        AppGroup.defaults?.set(id, forKey: Self.attachKey)
        AppGroup.defaults?.set(Double(MonoClock.now()), forKey: Self.attachNsKey)
    }

    private func clearAttachID() {
        AppGroup.defaults?.removeObject(forKey: Self.attachKey)
        AppGroup.defaults?.removeObject(forKey: Self.attachNsKey)
    }

    /// Nach dem Öffnen der App: höchstens 60 s alt, und die App nimmt dafür gerade auf.
    private func freshAttachID() -> String? {
        guard let id = AppGroup.defaults?.string(forKey: Self.attachKey),
              let ns = AppGroup.defaults?.object(forKey: Self.attachNsKey) as? Double
        else { return nil }
        guard MonoClock.ms(from: UInt64(ns), to: MonoClock.now()) < 60_000,
              let session = SharedStore.read(SessionState.self, .session),
              session.dictation?.id == id, session.dictation?.phase == .recording
        else {
            clearAttachID()
            return nil
        }
        return id
    }

    private var stateName: String { name(of: state) }

    private func name(of state: State) -> String {
        switch state {
        case .idle: "idle"
        case .connecting: "connecting"
        case .recording: "recording"
        case .polishing: "polishing"
        case .inserted: "inserted"
        case .empty: "empty"
        case .pending: "pending"
        case .opening: "opening"
        case .failure(let f):
            switch f {
            case .noFullAccess: "noFullAccess"
            case .noSession: "noSession"
            case .interrupted: "interrupted"
            case .noKey: "noKey"
            case .notResponding: "notResponding"
            case .openFailed: "openFailed"
            case .network: "network"
            }
        }
    }
}

extension KeyboardViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }
}

/// Leerzeichen vor dem eingesetzten Text, wenn es zum Text davor passt.
enum Spacing {
    /// Nach diesen Zeichen kein Leerzeichen
    private static let noSpaceAfter: Set<Character> = ["„", "(", "[", "{", "/", "‚", "«"]
    /// Vor diesen Zeichen (Textanfang) kein Leerzeichen
    private static let noSpaceBefore: Set<Character> = [",", ".", "!", "?", ":", ";", ")", "]", "}", "“", "‘", "»", "…"]

    static func prefixed(_ text: String, after context: String?) -> String {
        guard let last = context?.last, let first = text.first else { return text }
        if last.isWhitespace || first.isWhitespace { return text }
        if noSpaceAfter.contains(last) || noSpaceBefore.contains(first) { return text }
        return " " + text
    }
}
