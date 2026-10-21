function meetingAccelerator(key = 'CommandOrControl+Shift+X', platform = process.platform) {
  return key
    .split('+')
    .map((part) => {
      if (/^(CommandOrControl|CmdOrCtrl)$/i.test(part))
        return platform === 'darwin' ? 'Command' : 'Control';
      if (platform !== 'darwin' && /^(Command|Cmd)$/i.test(part)) return 'Control';
      return part;
    })
    .join('+');
}

// Eigene Registrierung: Umschalten berührt weder Diktat noch andere Hotkeys.
function createMeetingBetaMode({ globalShortcut, getController, platform, onError = () => {} }) {
  let registered = null;
  function apply(enabled, hotkey) {
    const controller = getController();
    // getStatus.active bleibt auch während des asynchronen Stop/Flush wahr.
    if (!enabled && controller?.getStatus().active) {
      throw new Error('Beende zuerst das laufende Meeting.');
    }
    const next = enabled ? meetingAccelerator(hotkey, platform) : null;
    if (next === registered) return;
    if (next) {
      let ok = false;
      try {
        ok = globalShortcut.register(next, () => {
          const meeting = getController();
          Promise.resolve()
            .then(() => (meeting?.isActive() ? meeting.stop() : meeting?.start()))
            .catch(() => onError('Das Meeting konnte nicht gestartet oder beendet werden.'));
        });
      } catch {
        /* Ungültiger Accelerator: gleiche verständliche Fehlermeldung. */
      }
      if (!ok)
        throw new Error(
          'Das Meeting-Tastenkürzel ist ungültig oder bereits belegt. Wähle ein anderes.'
        );
    }
    if (registered) globalShortcut.unregister(registered);
    registered = next;
  }
  return { apply };
}

module.exports = { meetingAccelerator, createMeetingBetaMode };
