# Esportazione PDF di documentazione Markdown

[English](README.md) · **Italiano**

Trasforma un progetto di documentazione Markdown in un unico PDF con copertina, indice con numeri di pagina, footer con numerazione, il tutto in stile GitHub. Il pacchetto sta in una cartella fissa, fuori dai progetti, e chiede quale cartella di progetto esportare.

## 1 Prerequisiti

- Windows con PowerShell 5.1 o successivo
- [Pandoc](https://pandoc.org/installing.html) (da shell: `winget install --source winget --exact --id JohnMacFarlane.Pandoc
`)
- [Node.js](https://nodejs.org/en/download) 20 o più recente ([Download-v26.13.1-x64](https://nodejs.org/dist/v26.13.1/node-v26.13.1-x64.msi))
- Google Chrome o Microsoft Edge

Alla prima esecuzione lo script installa da solo le dipendenze Node (`npm install`) nella cartella del pacchetto.

## 2 Installazione

Copiare questa cartella in un percorso fisso, per esempio `C:\Tools\pdf-export\`.

## 3 Uso

- **Doppio clic su `print.bat`**: si apre la finestra di scelta della cartella del progetto (propone l'ultima usata).
- **Trascina una cartella su `print.bat`**: salta la finestra di scelta.
- **Da PowerShell**:

  ```powershell
  powershell -ExecutionPolicy Bypass -File build-pdf.ps1 -Project "C:\percorso\progetto" [-Output nome.pdf] [-NoOpen] [-Keep]
  ```

Il PDF viene creato nella cartella del progetto con il nome `<Titolo>_<Versione>.pdf` (solo `<Titolo>.pdf` se non c'è una versione; spazi e caratteri non validi nei nomi dei file diventano `_`) e si apre al termine. Titolo e versione sono gli stessi della copertina.

Per conservare l'HTML intermedio, che resta in `<progetto>\.build-pdf\<nome-del-pdf>.html`, aggiungi `-Keep` al comando PowerShell oppure imposta `KeepBuild = $true` in `pdf-config.psd1` (l'unico modo valido anche con il doppio clic su `print.bat`).

Nel `.gitignore` del progetto conviene aggiungere `.build-pdf/` e il PDF generato.

## 4 Impostazioni per progetto

Facoltative: crea `pdf-config.psd1` nella radice del progetto partendo da `pdf-config.example.psd1`.

| Chiave | Significato | Predefinito |
| --- | --- | --- |
| `Title` | Titolo in copertina e del PDF | primo `# ...` del README, altrimenti nome cartella |
| `Subtitle`, `Author` | Sottotitolo e autore in copertina | vuoti (non mostrati) |
| `Version` | Etichetta di versione in copertina | vuoto: ultimo tag Git |
| `VersionFromGit` | Usa l'ultimo tag Git se `Version` è vuoto | `$true` |
| `ShowDate` | Data di generazione in copertina | `$true` |
| `TocTitle`, `Lang` | Titolo dell'indice e lingua | `Table of Contents`, `en` |
| `Output` | Nome del PDF (relativo al progetto) | `<Title>_<Version>.pdf` |
| `ExcludeStart`, `ExcludeStop` | Nomi dei marcatori delle zone escluse dal PDF (vuoti = disattivato) | `START_no_print_zone`, `STOP_no_print_zone` |
| `KeepBuild` | Conserva `.build-pdf\` (HTML intermedio) a fine lavoro | `$false` |
| `Files` | File inclusi, in ordine (accetta `*`, solo `.md`) | `README.md`, `chapters/*.md`, `appendices/*.md` |

Tutto ciò che non è elencato in `Files` (`LICENSE`, `assets/`, ...) resta fuori dal PDF.

## 5 Cosa fa

- Ogni file Markdown inizia su una nuova pagina; titoli, elenchi, tabelle, blocchi di codice e alert non si spezzano a metà pagina, salvo quelli più alti del 40% dell'area utile (la soglia è in `print-pdf.mjs`), che possono continuare sulla pagina dopo per non lasciare vuoti.
- In alto su ogni pagina, tranne la copertina, compare un'intestazione: a sinistra il titolo del documento (lo stesso della copertina), a destra il titolo della sezione corrente, cioè il titolo `#` del file.
- Un file con più di un titolo `#` viene trattato come più file: ogni titolo `#` dopo il primo inizia una nuova pagina e una nuova sezione, elencata allo stesso livello nell'indice e mostrata nell'intestazione.
- I link relativi tra i file diventano rimandi interni al PDF; i link verso file esclusi diventano solo testo.
- Gli alert `> [!NOTE]`, `TIP`, `IMPORTANT`, `WARNING`, `CAUTION` hanno i colori GitHub. Il testo dopo il marcatore sulla stessa riga diventa il titolo del blocco: `> [!NOTE] Titolo personalizzato` (fuori dagli standard di GitHub, ma molto apprezzabile).
- L'immagine HTML iniziale del README diventa un'immagine piatta, senza link.
- Il testo racchiuso tra `<!--START_no_print_zone-->` e `<!--STOP_no_print_zone-->` (ciascun commento su una riga propria, anche dentro elenchi o citazioni) viene escluso dal PDF e resta visibile su GitHub. Un `START` senza `STOP` esclude fino alla fine del blocco e segnala un avviso. I link che puntano a un titolo escluso non portano da nessuna parte.
- I blocchi di codice hanno i colori di GitHub (C/C++, JSON, YAML, CMake, properties, bash), in base al linguaggio indicato dopo i tre apici.

## 6 File del pacchetto

| File | Ruolo |
| --- | --- |
| `print.bat` | Avvio con doppio clic |
| `build-pdf.ps1` | Script principale |
| `export.lua` | Filtro Pandoc (link, alert, zone escluse, immagini) |
| `github-pdf.css` | Stile e regole di impaginazione |
| `code-colors.js` | Colori del codice come su GitHub |
| `print-pdf.mjs`, `package.json` | Stampa PDF con numeri di pagina e indice |
| `stamp-headers.mjs` | Intestazione in alto (titolo del documento e sezione corrente) |
| `pdf-config.example.psd1` | Modello delle impostazioni per progetto |

## 7 Problemi comuni

- **Node.js o Pandoc non trovato**: installali e riapri il terminale; se il problema resta, verifica con `node --version` e `pandoc --version`.
- **Emoji mancanti**: servono font emoji di sistema (su Windows è `Segoe UI Emoji`).
