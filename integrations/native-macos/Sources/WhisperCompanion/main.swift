import AppKit
import CompanionCore

@MainActor
final class CompanionApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private let menu = NSMenu()
    private var cli: WhisperCLI?
    private var status: CompanionStatus?
    private var readError: String?
    private var actionError: String?
    private var busy = false
    private var refreshing = false
    private var renderedMenu = ""
    private var showMenuAfterRead = CommandLine.arguments.contains("--show-menu")
    private var lastRead: Date?
    private var timer: Timer?
    private var pollTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        render()
        refresh()
        timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func menuWillOpen(_ menu: NSMenu) {
        render()
        refresh()
    }


    private var fresh: Bool {
        guard let lastRead else { return false }
        return Date().timeIntervalSince(lastRead) < 15 && readError == nil
    }

    private func refresh() {
        guard !refreshing, !busy else { return }
        refreshing = true
        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                if cli == nil { cli = WhisperCLI() }
                status = try await cli!.status()
                lastRead = Date()
                readError = nil
            } catch {
                status = nil
                readError = error.localizedDescription
            }
            refreshing = false
            render()
            if showMenuAfterRead {
                showMenuAfterRead = false
                item.button?.performClick(nil)
            }
        }
    }

    private func text(_ value: String) {
        // Native menu rows do not wrap. Bound individual lines for small screens.
        let bounded = value.count > 400 ? String(value.prefix(400)) + "…" : value
        let words = bounded.split(whereSeparator: { $0.isWhitespace })
        var line = ""
        for word in words {
            if line.count + word.count > 66 && !line.isEmpty {
                add(line, enabled: false)
                line = ""
            }
            line += (line.isEmpty ? "" : " ") + word.prefix(100)
        }
        if !line.isEmpty { add(line, enabled: false) }
    }

    @discardableResult
    private func add(_ title: String, action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
        let row = NSMenuItem(title: title, action: action, keyEquivalent: "")
        row.target = self
        row.isEnabled = enabled
        menu.addItem(row)
        return row
    }

    private func render() {
        let state = status?.summary.state.rawValue ?? "unavailable"
        let hasError = readError != nil || actionError != nil
        let symbol: String
        if hasError { symbol = "exclamationmark.circle" }
        else {
            switch state {
            case "ready": symbol = "waveform.circle"
            case "recording": symbol = "record.circle"
            case "processing": symbol = "hourglass.circle"
            default: symbol = "exclamationmark.circle"
            }
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Tmux Whisper: \(state)")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Tmux Whisper Companion — \(status?.summary.headline ?? "Checking CLI…")"
        let policy = status?.policy
        let enabled = fresh && !busy && !refreshing
        let signature = [state, status?.summary.headline ?? "", status?.summary.nextAction ?? "",
                         readError ?? "", actionError ?? "", String(busy), String(enabled),
                         String(policy?.canStartInline ?? false), String(policy?.canStopInline ?? false),
                         String(policy?.canCancelInline ?? false)].joined(separator: "\n")
        guard signature != renderedMenu else { return }
        renderedMenu = signature
        // Avoid rebuilding unchanged menus so keyboard selection survives polling.
        menu.removeAllItems()
        add("Tmux Whisper · Prototype", enabled: false)
        text(busy ? "Working…" : (status?.summary.headline ?? (readError == nil ? "Checking CLI…" : "CLI unavailable")))
        if let status { text(status.summary.nextAction) }
        if let error = readError { text(error) }
        if let error = actionError {
            menu.addItem(.separator())
            text("Command failed: \(error)")
            add("Dismiss command error", action: #selector(dismissError))
        }
        menu.addItem(.separator())
        add("Start inline recording", action: #selector(start), enabled: enabled && policy?.canStartInline == true)
        add("Stop and transcribe", action: #selector(stop), enabled: enabled && policy?.canStopInline == true)
        add("Cancel recording (discard audio)", action: #selector(cancel), enabled: enabled && policy?.canCancelInline == true)
        menu.addItem(.separator())
        add("Refresh status", action: #selector(refreshStatus), enabled: !busy && !refreshing)
        add("Quit companion", action: #selector(quit))
    }

    private func perform(_ command: WhisperCommand) {
        guard !busy, !refreshing, let cli else { return }
        busy = true
        actionError = nil
        render()
        // Menu tracking must finish before CLI captures the current destination.
        menu.cancelTracking()
        Task { [weak self] in
            guard let self else { return }
            do {
                let current = try await cli.status()
                status = current
                lastRead = Date()
                readError = nil
                let allowed: Bool
                switch command {
                case .startInline: allowed = current.policy.canStartInline
                case .stopInline: allowed = current.policy.canStopInline
                case .cancelInline: allowed = current.policy.canCancelInline
                }
                guard allowed else {
                    actionError = "State changed. Review the current status before trying again."
                    busy = false
                    render()
                    return
                }
                try await cli.execute(command)
            } catch { actionError = error.localizedDescription }
            busy = false
            render()
            refresh()
        }
    }

    @objc private func start() { perform(.startInline) }
    @objc private func stop() { perform(.stopInline) }
    @objc private func cancel() { perform(.cancelInline) }
    @objc private func refreshStatus() { refresh() }
    @objc private func dismissError() { actionError = nil; render() }
    @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
let delegate = CompanionApp()
app.delegate = delegate
app.run()
