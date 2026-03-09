# Anleitung: Automatische Datei-Übersetzung mit Cloud Run, Cloud Functions & Cloud Storage

## Was macht dieses Setup?

Eine Textdatei wird per `curl` an eine Flask-App (Cloud Run) hochgeladen.
Die App speichert die Datei in einem Cloud Storage Bucket.
Eine Cloud Function wird automatisch getriggert, übersetzt den Inhalt über die DeepL-API und legt die Übersetzung zurück in den Bucket.
Die übersetzte Datei kann anschließend über die Flask-App heruntergeladen werden.

| Komponente | Dienst | Aufgabe |
|---|---|---|
| **Flask-App** | Cloud Run | Nimmt Dateien entgegen, speichert sie im Bucket, stellt Übersetzungen zum Download bereit |
| **Bucket** | Cloud Storage | Speichert Original-Dateien (`uploads/`) und Übersetzungen (`translated/`) |
| **Übersetzer** | Cloud Function | Wird bei Upload automatisch ausgelöst, übersetzt per DeepL-API |

```
                        curl -F "file=@text.txt"
                                │
                                ▼
                    ┌───────────────────────┐
                    │   Cloud Run (Flask)   │
                    │   POST /upload        │
                    └───────────┬───────────┘
                                │ speichert
                                ▼
                    ┌───────────────────────┐
                    │   Cloud Storage       │
                    │   uploads/text.txt    │──── automatischer Trigger
                    │   translated/text.txt │◄─┐
                    └───────────────────────┘  │
                                               │
                    ┌───────────────────────┐  │
                    │   Cloud Function      │  │
                    │   translate_on_upload  │──┘
                    │   (DeepL-API)         │ schreibt Übersetzung
                    └───────────────────────┘
```

---

## Voraussetzungen

- Google Cloud CLI (`gcloud`) ist installiert und konfiguriert
- Ein GCP-Projekt mit aktivem Billing
- Ihr kennt eure **Project-ID** (findet ihr mit `gcloud config get project`)

---

## Schritt 1: APIs aktivieren

Aktiviert die benötigten Google Cloud APIs:

```bash
gcloud services enable \
  cloudfunctions.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  storage.googleapis.com \
  artifactregistry.googleapis.com \
  eventarc.googleapis.com
```

> Das dauert ca. 30 Sekunden. Diese APIs werden für Cloud Run, Cloud Functions (Gen 2) und den Storage-Trigger benötigt.

---

## Schritt 2: Eventarc-Berechtigungen setzen

Cloud Functions Gen 2 nutzt **Eventarc** für Storage-Trigger. Dafür müssen zwei Berechtigungen gesetzt werden:

```bash
PROJECT_ID=$(gcloud config get project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# 1) Eventarc Service Agent darf Events empfangen
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver"

# 2) Cloud Storage darf Pub/Sub-Nachrichten senden (fuer den Trigger)
GCS_SA=$(gcloud storage service-agent --project=$PROJECT_ID)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${GCS_SA}" \
  --role="roles/pubsub.publisher"
```

> Falls ihr nach einer Condition gefragt werdet, wählt `None`.
>
> **Warum?** Wenn eine Datei im Bucket landet, schickt Cloud Storage eine Nachricht über Pub/Sub an Eventarc, und Eventarc leitet sie an die Cloud Function weiter. Ohne diese Berechtigungen schlägt das Deployment fehl.

---

## Schritt 3: Bucket erstellen

> **Was ist `gsutil`?**
> `gsutil` ist das Kommandozeilen-Tool für Google Cloud Storage -- vergleichbar mit `aws s3` bei AWS.
> Damit könnt ihr Buckets erstellen (`mb`), Dateien hoch-/herunterladen (`cp`), auflisten (`ls`) und löschen (`rm`).
> Es ist Teil der Google Cloud CLI und bereits vorinstalliert.

Erstellt einen Cloud Storage Bucket. Der Name muss **global eindeutig** sein:

```bash
PROJECT_ID=$(gcloud config get project)
BUCKET_NAME="${PROJECT_ID}-translation"
REGION="europe-west1"

gsutil mb -l $REGION gs://$BUCKET_NAME
```

Prüft, ob der Bucket existiert:

```bash
gsutil ls gs://$BUCKET_NAME
```

> **Kein Output?** Das ist korrekt! `gsutil ls` listet den *Inhalt* des Buckets auf.
> Ein frisch erstellter Bucket ist leer, daher keine Ausgabe. Solange kein Fehler kommt, existiert der Bucket.

> Merkt euch den `BUCKET_NAME` – ihr braucht ihn in den nächsten Schritten!
>
> Den Bucket-Namen könnt ihr jederzeit mit `echo $BUCKET_NAME` anzeigen (solange ihr im selben Terminal bleibt).

---

## Schritt 4: Cloud Function anpassen

Öffnet die Datei `cloud_function/main.py`:

```bash
vim cloud_function/main.py
```

Tragt im oberen Block **zwei Werte** ein:

| Variable | Wert | Beschreibung |
|---|---|---|
| `DEEPL_AUTH_KEY` | `4fbe961c-643a-43e5-89eb-6b18f80f2163:fx` | Euer DeepL-API-Key |
| `TARGET_LANG` | z.B. `EN`, `FR`, `ES` | Zielsprache ([Liste](https://developers.deepl.com/docs/resources/supported-languages)) |

Vorher:

```python
DEEPL_AUTH_KEY = "EUER_DEEPL_KEY"
TARGET_LANG = "EN"
```

Nachher (Beispiel):

```python
DEEPL_AUTH_KEY = "4fbe961c-643a-43e5-89eb-6b18f80f2163:fx"
TARGET_LANG = "FR"
```

Speichern und schließen: `Esc` → `:wq` → `Enter`

---

## Schritt 5: Cloud Function deployen

Deployt die Funktion mit einem **Storage-Trigger** auf euren Bucket:

```bash
gcloud functions deploy translate_on_upload \
  --gen2 \
  --runtime python312 \
  --region $REGION \
  --source ./cloud_function \
  --entry-point translate_on_upload \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=$BUCKET_NAME" \
  --memory 256Mi \
  --timeout 120s
```

> Das Deployment dauert ca. **2–4 Minuten**. In der Zwischenzeit könnt ihr schon Schritt 5 vorbereiten.

Falls ihr nach Berechtigungen gefragt werdet, bestätigt mit `y`.

Prüft nach dem Deployment:

```bash
gcloud functions describe translate_on_upload --region $REGION --gen2 --format="value(state)"
```

Erwartete Ausgabe: `ACTIVE`

---

## Schritt 6: Cloud Run App anpassen

Öffnet die Datei `cloud_run_app/main.py`:

```bash
vim cloud_run_app/main.py
```

Tragt euren **Bucket-Namen** ein:

| Variable | Wert |
|---|---|
| `BUCKET_NAME` | Der Name aus Schritt 2 (z.B. `mein-projekt-translation`) |

Vorher:

```python
BUCKET_NAME = "EUER_BUCKET_NAME"
```

Nachher (Beispiel):

```python
BUCKET_NAME = "mein-projekt-translation"
```

> Tipp: `echo $BUCKET_NAME` zeigt euch den Namen an.

Speichern und schließen: `Esc` → `:wq` → `Enter`

---

## Schritt 7: Cloud Run App deployen

> **Was passiert hier?**
> Cloud Run führt eure App als **Docker-Container** aus. Im Ordner `cloud_run_app/` liegt ein `Dockerfile`,
> das beschreibt, wie der Container gebaut wird:
>
> 1. Basis-Image: `python:3.12-slim` (schlankes Linux mit Python)
> 2. Abhängigkeiten installieren (`pip install -r requirements.txt`)
> 3. App-Code kopieren (`main.py`)
> 4. Startbefehl: `gunicorn --bind :8080 main:app` (Produktions-Webserver für Flask)
>
> Der Befehl `gcloud run deploy --source .` baut diesen Container automatisch in der Cloud (via Cloud Build)
> und deployed ihn auf Cloud Run -- ihr braucht Docker **nicht** lokal installiert zu haben.

Deployt die Flask-App auf Cloud Run:

```bash
cd cloud_run_app

gcloud run deploy translate-upload-service \
  --source . \
  --region $REGION \
  --allow-unauthenticated

cd ..
```

> Das Deployment dauert ca. **3–5 Minuten** (beim ersten Mal wird das Container-Image gebaut).

Falls ihr gefragt werdet, ob ein Artifact Registry Repository erstellt werden soll, bestätigt mit `y`.

Notiert euch die **Service URL** aus der Ausgabe, z.B.:

```
Service URL: https://translate-upload-service-xxxxx-ew.a.run.app
```

Speichert sie in einer Variable:

```bash
SERVICE_URL="https://translate-upload-service-xxxxx-ew.a.run.app"
```

---

## Schritt 8: Testen!

### 7.1 Testdatei erstellen

```bash
echo "Dies ist ein deutscher Beispieltext. Cloud Computing ist ein spannendes Thema." > test.txt
```

### 7.2 Datei hochladen

```bash
curl -F "file=@test.txt" $SERVICE_URL/upload
```

Erwartete Ausgabe:

```json
{
  "status": "ok",
  "datei": "test.txt",
  "bucket_pfad": "gs://EUER-BUCKET/uploads/test.txt",
  "hinweis": "Die Cloud Function uebersetzt die Datei automatisch. ..."
}
```

### 7.3 Warten & Übersetzungen prüfen

Die Cloud Function braucht ein paar Sekunden. Wartet kurz und prüft dann:

```bash
curl -s $SERVICE_URL/translations | python3 -m json.tool
```

Erwartete Ausgabe:

```json
{
  "anzahl": 1,
  "translations": [
    {
      "name": "test.txt",
      "download": "/download/test.txt"
    }
  ]
}
```

> Falls die Liste noch leer ist, wartet 10–15 Sekunden und versucht es erneut.

### 7.4 Übersetzte Datei herunterladen

```bash
curl -s $SERVICE_URL/download/test.txt
```

Ihr solltet den übersetzten Text sehen!

### 7.5 Alternative: Direkt im Bucket prüfen

```bash
gsutil ls gs://$BUCKET_NAME/translated/
gsutil cat gs://$BUCKET_NAME/translated/test.txt
```

---

## Schritt 9: Logs anschauen

### Cloud Function Logs

```bash
gcloud functions logs read translate_on_upload --region $REGION --gen2 --limit 20
```

Hier seht ihr, ob die Funktion ausgelöst wurde und ob Fehler aufgetreten sind.

### Cloud Run Logs

```bash
gcloud run services logs read translate-upload-service --region $REGION --limit 20
```

---

## Zusammenfassung: Alle Befehle auf einen Blick

```bash
# 0. Ins Verzeichnis wechseln
cd ~/cloud_lecture04_aufgaben/faas_translation

# 1. APIs aktivieren
gcloud services enable cloudfunctions.googleapis.com run.googleapis.com \
  cloudbuild.googleapis.com storage.googleapis.com \
  artifactregistry.googleapis.com eventarc.googleapis.com

# 2. Eventarc-Berechtigungen setzen
PROJECT_ID=$(gcloud config get project)
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver"
GCS_SA=$(gcloud storage service-agent --project=$PROJECT_ID)
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${GCS_SA}" \
  --role="roles/pubsub.publisher"

# 3. Bucket erstellen
BUCKET_NAME="${PROJECT_ID}-translation"
REGION="europe-west1"
gsutil mb -l $REGION gs://$BUCKET_NAME

# 4. Cloud Function anpassen (DEEPL_AUTH_KEY + TARGET_LANG eintragen)
vim cloud_function/main.py

# 5. Cloud Function deployen
gcloud functions deploy translate_on_upload \
  --gen2 --runtime python312 --region $REGION \
  --source ./cloud_function --entry-point translate_on_upload \
  --trigger-event-filters="type=google.cloud.storage.object.v1.finalized" \
  --trigger-event-filters="bucket=$BUCKET_NAME" \
  --memory 256Mi --timeout 120s

# 6. Cloud Run App anpassen (BUCKET_NAME eintragen)
vim cloud_run_app/main.py

# 7. Cloud Run App deployen
cd cloud_run_app
gcloud run deploy translate-upload-service \
  --source . --region $REGION --allow-unauthenticated
cd ..

# 8. Testen
SERVICE_URL="EURE_SERVICE_URL"
echo "Dies ist ein Testtext." > test.txt
curl -F "file=@test.txt" $SERVICE_URL/upload
sleep 15
curl -s $SERVICE_URL/translations | python3 -m json.tool
curl -s $SERVICE_URL/download/test.txt
```

---

## Aufräumen

Wenn ihr fertig seid, könnt ihr die Ressourcen löschen, um Kosten zu vermeiden:

```bash
# Cloud Run Service löschen
gcloud run services delete translate-upload-service --region $REGION --quiet

# Cloud Function löschen
gcloud functions delete translate_on_upload --region $REGION --gen2 --quiet

# Bucket leeren und löschen
gsutil -m rm -r gs://$BUCKET_NAME
```

---

## Fehlerbehebung

### "Permission denied" beim Function-Deployment

Eventarc braucht bestimmte Berechtigungen. Führt folgendes aus:

```bash
PROJECT_NUMBER=$(gcloud projects describe $PROJECT_ID --format="value(projectNumber)")

# Eventarc Service Agent Rolle vergeben
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:service-${PROJECT_NUMBER}@gcp-sa-eventarc.iam.gserviceaccount.com" \
  --role="roles/eventarc.eventReceiver"

# Storage Service Account für Eventarc
SERVICE_ACCOUNT="$(gsutil kms serviceaccount -p $PROJECT_ID)"
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${SERVICE_ACCOUNT}" \
  --role="roles/pubsub.publisher"
```

### Cloud Function wird nicht ausgelöst

1. Prüft, ob die Datei im richtigen Ordner liegt:

```bash
gsutil ls gs://$BUCKET_NAME/uploads/
```

2. Prüft die Logs:

```bash
gcloud functions logs read translate_on_upload --region $REGION --gen2 --limit 10
```

3. Prüft, ob der Trigger korrekt ist:

```bash
gcloud functions describe translate_on_upload --region $REGION --gen2 \
  --format="yaml(eventTrigger)"
```

### "EUER_BUCKET_NAME" oder "EUER_DEEPL_KEY" Fehler

Ihr habt vergessen, die Platzhalter in den Python-Dateien zu ersetzen. Geht zurück zu Schritt 3 bzw. 5.

### Übersetzung dauert zu lange

Die Cloud Function braucht beim **ersten Aufruf** etwas länger (Cold Start). Wartet bis zu 30 Sekunden und prüft dann erneut. Bei weiteren Uploads geht es schneller.

### Cloud Run gibt 403 zurück

Die App wurde ohne `--allow-unauthenticated` deployed. Löscht den Service und deployed erneut:

```bash
gcloud run services delete translate-upload-service --region $REGION --quiet
cd cloud_run_app
gcloud run deploy translate-upload-service \
  --source . --region $REGION --allow-unauthenticated
cd ..
```

---

## Dateistruktur

```
faas_translation/
├── ANLEITUNG.md                     # Diese Anleitung
├── cloud_function/
│   ├── main.py                      # Cloud Function: übersetzt Dateien aus dem Bucket
│   └── requirements.txt             # Abhängigkeiten (functions-framework, requests, gcs)
└── cloud_run_app/
    ├── Dockerfile                   # Container-Definition für Cloud Run
    ├── main.py                      # Flask-App: Upload + Download Endpunkte
    └── requirements.txt             # Abhängigkeiten (flask, gunicorn, gcs)
```

## Was ist was?

| Datei | Rolle |
|---|---|
| `cloud_function/main.py` | Wird bei jedem Datei-Upload im Bucket automatisch ausgeführt. Liest die Datei, schickt den Text an die DeepL-API und speichert die Übersetzung zurück im Bucket. |
| `cloud_run_app/main.py` | Flask-Webserver mit drei Endpunkten: Datei hochladen, Übersetzungen auflisten, übersetzte Datei herunterladen. |
| `Dockerfile` | Beschreibt, wie der Container für Cloud Run gebaut wird: Basis-Image, Abhängigkeiten, App-Code, Startbefehl. Wird von `gcloud run deploy --source .` automatisch erkannt und gebaut. |

## Konzepte in dieser Übung

| Konzept | Wo in der Übung |
|---|---|
| **Function as a Service (FaaS)** | Cloud Function wird automatisch bei Events ausgeführt, kein eigener Server nötig |
| **Container as a Service** | Cloud Run führt die Flask-App als Container aus, skaliert automatisch |
| **Object Storage (Buckets)** | Cloud Storage speichert Dateien in `uploads/` und `translated/` Ordnern |
| **Event-driven Architecture** | Upload im Bucket triggert automatisch die Cloud Function |
| **Serverless** | Beide Dienste (Cloud Run + Cloud Functions) sind serverless: keine Server-Verwaltung, Pay-per-Use |
