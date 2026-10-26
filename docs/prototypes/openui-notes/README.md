# Paply Notes · OpenUI-Prototyp

Isolierter, interaktiver Darstellungsversuch nach Allans Rückmeldung. Kein App-Code, keine API-Nutzung. Die Beispielnotizen (insbesondere die Lampenalternativen) sind vorbereitet und keine recherchierten Produktdaten.

```sh
npm ci --prefix docs/prototypes/openui-notes --ignore-scripts
npm run build --prefix docs/prototypes/openui-notes
```

Erzeugt `../paply-notes-generative.html`, vollständig eingebettet. React, OpenUI, Zod und Lucide sind lokal gebündelt. Für die Inline-Größenbegrenzung wird das JS gzip-komprimiert eingebettet und durch die native DecompressionStream-API entpackt. Keine CDN- oder Modellrequests.

Der echte OpenUI-Renderer interpretiert vorbereitete Programme (`root = MindMap("trip")`, `Comparison("home")`, `Flow("paply")`, `FreeNotes(...)`). Die Auswahl ist im Demo fest; **kein automatischer semantischer Router ist hier implementiert**. Die Komponenten lesen Notizen aus einem getrennten React-Store. Änderungen, Entfernen und Undo bleiben beim Ansichtswechsel erhalten. Auswahl, Originaltext, Kopieren, Pan/Zoom, eigene Haftnotizen, Linien und Pfeile sind lokal bedienbar. Nur optionaler Host-Widget-State; kein dauerhafter Notes-Store.

`window.paplyGenerative` stellt einen kleinen Debug-Zugang bereit. Änderungen an festen Beispieltexten können die vorbereiteten Anordnungen überlaufen; Produktionslayout, Dragging einzelner Objekte, langes Textlayout, Tastatur-/IME-Bedienung, große Boards und Wiederherstellung sind nicht abgedeckt. Zeichnungen lassen sich per Undo zurücknehmen, noch nicht einzeln selektieren.

Architekturkorrektur und Budgetannahmen: `../paply-notes-opus-review.md`, Abschnitt 12. Das vorherige pauschale Nein zu OpenUI ist aufgehoben.
