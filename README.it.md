# Local AI for Photoshop

**Un solo script PowerShell che trasforma un PC Windows con GPU NVIDIA in un motore di AI locale e
offline per Adobe Photoshop**: ComfyUI Portable, il plugin [OpenLayer](https://github.com/MehranMarxian/OpenLayer),
tutti i custom node di ComfyUI che OpenLayer richiede e tutti i modelli con licenza libera che può
usare. Ogni passaggio è verificato, riprendibile e si chiude con una generazione di prova reale.

[English](README.md)

> **Progetto comunitario non ufficiale.** Non affiliato né approvato da Adobe, Comfy Org,
> Black Forest Labs o dal progetto OpenLayer. **Non** installa, attiva o fornisce licenze di
> Photoshop o Creative Cloud: serve un Photoshop 2024 o successivo con licenza propria.

## Requisiti

| | Minimo | Consigliato |
| --- | --- | --- |
| Sistema | Windows 10 1803+ / Windows 11, 64 bit | Windows 11 |
| GPU | NVIDIA, 6 GB di VRAM | NVIDIA RTX, 8 GB+ di VRAM |
| Driver | driver NVIDIA Studio recente | 580 o superiore (CUDA 13.0) |
| RAM | 16 GB | 32 GB |
| Disco | ~25 GB (`-ModelSet Klein`) | ~140 GB liberi (`-ModelSet Full`) |
| Photoshop | 2024 (v25) o successivo, con licenza | ultima versione |
| App Creative Cloud | serve per installare il plugin, con accesso a un account Adobe qualsiasi (anche gratuito) | |

## Avvio rapido

1. Scarica il repository (**Code > Download ZIP**) ed estrailo, oppure `git clone`.
2. Apri un PowerShell **normale** (non amministratore) nella cartella e guarda cosa farebbe:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-LocalAI.ps1 -DryRun
   ```

3. Installa:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-LocalAI.ps1
   ```

4. Riavvia Photoshop e apri **Plugin > OpenLayer**. ComfyUI deve essere in esecuzione: lo avvii
   quando vuoi con `Start-ComfyUI.cmd` nella cartella di installazione.

Si è interrotto? Rilancia lo stesso comando: i file completi vengono saltati, i download parziali ripresi.

## Set di modelli

| `-ModelSet` | Modelli | Download | Strumenti OpenLayer |
| --- | --- | --- | --- |
| `Full` (predefinito) | tutti i modelli **senza** licenza restrittiva (31 oggi) | ~126 GB | tutti quelli con modelli a licenza libera |
| `Klein` | solo FLUX.2 [klein] 4B | ~12,5 GB | Text to Image, Image to Image, Edit Image, Inpaint, Multi-Reference |

I modelli che OpenLayer segna come a licenza restrittiva (FLUX.1 dev, FLUX.2 dev, Qwen-Image 2.1:
non commerciali o solo ricerca) **non vengono mai scaricati di default**. Per includerli devi
leggere le licenze e passare `-IncludeLicenseRestricted -AcceptLicenses`.

Sketch to Image, inpaint SD e Style Reference richiedono anche un **checkpoint SD 1.5** a tua scelta:
passa l'URL diretto con `-Sd15CheckpointUrl` oppure copialo in `ComfyUI\models\checkpoints`.

L'elenco dei modelli (`manifest/openlayer-requirements.json`) è generato dalla build di OpenLayer
stessa e viene aggiornato ogni settimana da una GitHub Action che apre una pull request.

## Parametri principali

| Parametro | Effetto |
| --- | --- |
| `-Root <percorso>` | cartella di installazione (predefinita `D:\AI\PhotoshopLocalAI`) |
| `-ModelSet Full\|Klein` | quali modelli installare |
| `-DryRun` | controlli + piano + dimensione download, senza modificare nulla |
| `-UpdateComfyUI` | aggiorna ComfyUI con l'updater ufficiale della versione portable |
| `-RestartComfyUI` | riavvia ComfyUI di questa installazione per caricare i nuovi nodi |
| `-InstallCreativeCloud` | installa l'app Creative Cloud con winget |
| `-SkipModels`, `-SkipCustomNodes`, `-SkipPlugin`, `-SkipTest`, `-NoStart` | salta una fase |

L'elenco completo è nel [README inglese](README.md#parameters).

## Esito e report

Alla fine lo script stampa un riepilogo e scrive `last-report.json` nella cartella di installazione.
Codici di uscita: `0` tutto OK con test superato, `2` completato con avvisi, `1` errore.

## Problemi comuni

| Sintomo | Soluzione |
| --- | --- |
| `Adobe UPI -631` | Nessun accesso a Creative Cloud: aprilo, accedi (va bene un account Adobe gratuito), rilancia. |
| `Adobe UPI -641` | Lancia lo script da un PowerShell non amministratore con Creative Cloud aperto. |
| Il `.ccx` chiede "con quale app aprire" | Manca Creative Cloud: installalo (o `-InstallCreativeCloud`). Non scegliere altre app. |
| Custom node "not loaded" | ComfyUI era già aperto: riavvialo o usa `-RestartComfyUI`. |
| Pannello non "Ready" | **Settings > Find ComfyUI Active Port** nel pannello, con ComfyUI avviato. |
| "Agent Bridge is not connected" | Riguarda solo la funzione opzionale *Ask the Agent*: premi **Generate**. |

## Disinstallazione

1. `"C:\Program Files\Common Files\Adobe\Adobe Desktop Common\RemoteComponents\UPI\UnifiedPluginInstallerAgent\UnifiedPluginInstallerAgent.exe" /remove OpenLayer`
2. Chiudi ComfyUI ed elimina la cartella di installazione.

## Licenza

Script rilasciato con [licenza MIT](LICENSE). Modelli, ComfyUI, OpenLayer e custom node mantengono
le proprie licenze: vedi [THIRD_PARTY.md](THIRD_PARTY.md). Lo script scarica tutto dalle fonti
originali e non ridistribuisce nulla.
