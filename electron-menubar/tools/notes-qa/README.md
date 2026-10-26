# Independent Notes QA tools

These scripts are developer-only, excluded from the packaged app. They create fresh temporary profiles with the exact dummy key `paply-notes-test-key`, isolated F18/F19/F20 shortcuts, local synthetic audio, and a loopback model server. They do not read the normal Paply profile. Tell Allan before launching that the isolated app initially looks empty.

Run `node tools/notes-qa/harness.cjs` in an interactive terminal after the renderer build. The harness accepts one short JavaScript test command per input line; use helper modules for longer sequences (macOS canonical terminal input is bounded). It prints its artifact directory. It uses locally cached Playwright by default; set `PAPLY_QA_PLAYWRIGHT` to a compatible local package path if necessary. No browser download is needed for Electron.

- `await launch(); return await openBoard();` starts with the normal sandbox. Use this for IPC/CSP checks.
- On this Mac the fake-audio service cannot read the WAV inside its sandbox. The separately documented audio QA workaround is `await launch({audioWorkaround:true,nativeBackground:true})`. It is **not** production configuration. The bootstrap removes Playwright's background scheduling flags before requiring the real app.
- `await require(path.join(appDir,'tools/notes-qa/canvas.cjs')).run({board,state,shot,app,results})` checks real drag/resize/edit actions after the mixed capture fixture has been generated through the pipeline.
- `await require(path.join(appDir,'tools/notes-qa/performance.cjs')).run({board,state,app,dashboard,shot})` requires an otherwise empty dedicated QA profile and creates its 300-node volume fixture.
- `await require(path.join(appDir,'tools/notes-qa/arbitration.cjs')).run({board,dashboard,app,pill,waitUntil,profile})` checks dictation priority with a separate, strict fake dictation transport.

`mode` controls the loopback server: `normal`, `delay`, `invalid`, `auth`, `rate`. Delayed replies are in `pending`. The exact model-plan fixture is intentionally fixed; this is not an evaluation of live model quality. Do not change the server to forward a request or copy a real API key into a QA profile.

Use `await app.close()` for ordinary cleanup, and end input to stop the loopback server. The harness writes `results.json` on EOF. Kill/restart cases should target only `app.process()` from this harness. See `docs/notes/QA.md` for actual outcomes, fixes and limitations of the independent round.

## Packaged smoke

`node tools/notes-qa/packaged-harness.cjs` uses the real macOS arm64 executable in `dist/notes-test`, always with the normal sandbox. `await launch('notes-test-next')` can select a separately built candidate directory. This harness generates no audio and never starts a real microphone.

Start with `await launch(); return await openBoard();`. Put `transcript` into the native clipboard with `app.evaluate(({clipboard},t)=>clipboard.writeText(t),transcript)`, then use `board.keyboard.press('Meta+v')` and wait for the source entry to complete. The loopback server returns the same documented mixed fixture.

`packaged-cases.cjs` exports `mindmap`, `original`, `camera`, `settings`, `crash`, `performance` and `updateQuit`. Pass the harness objects named in each function's signature. After `crash`, assign its returned page back to `board`. `camera` replaces `getSources` before clicking the camera and restores it afterwards, so it never samples the user's screen. Run `performance` only after other scene checks: it intentionally replaces this temporary board with 60 short measurement objects. Run `updateQuit` last because it enters the real shutdown lifecycle. It emits only the native event and never calls update download/install APIs. End input after regular app cleanup to close the mock server and write `results.json`.

See `docs/notes/PACKAGED-QA.md` for the exact tested bundle hash, initial findings, final evidence and limits.

## Open-editor regressions (N1/N2)

After the main agent confirms the new bundle is ready, `freshProfile('n1-a','notes-test-final')` starts an independent empty profile. `raceContext()` supplies the test handles to `editor-races.cjs`:

- `planDuringEditor(raceContext())`: delayed plan arrives while a modified textarea stays open; save must retain the draft with one model request.
- `planDuringEditor(raceContext(),{unchanged:true})`: close the untouched editor; apply the cached plan without another request.
- `transcriptDuringEditor(raceContext())`: start Chromium's internal fake microphone, edit its pending card, stop through the existing capture preload without changing focus, then deliver delayed STT. Draft and transcript must survive together. This case asserts fake-device flags and normal sandbox before starting; it injects no PCM and uses no real hardware or WAV file.
- `transcriptDuringEditor(raceContext(),{reopen:true})`: B2 variant. Save a first draft while pending, reopen the same user-owned placeholder, change it again, then deliver STT. The second save must close the editor and contain exactly the new draft plus one full transcript, without the old prefix.
- `longTable(raceContext())`: a nonliteral table quote expands to a source sentence over 2,000 characters; two complete ordinary notes must result from one request.

Use a new `freshProfile` label for each case. `mode='delay-stt'`, `pendingStt`, `sttTranscript` and `planOverride` provide deterministic transport timing/fixtures; no request is forwarded externally. Do not start an unannounced or unfinished bundle.

`switchAndBlur(raceContext(),{nativeBlur:false})` checks direct editor switching and ordinary save. The default `nativeBlur:true` additionally requires a verified native Dashboard/Board focus transition; if the automation environment cannot acquire native focus, report that step as unverified instead of injecting a DOM blur event. Actual final-bundle results and the current normal-sandbox audio evidence are in `docs/notes/EDITOR-QA.md`.
