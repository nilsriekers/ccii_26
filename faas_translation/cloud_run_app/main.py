import io
import os

from flask import Flask, Response, jsonify, request
from google.cloud import storage

app = Flask(__name__)

# ============================================================
#  TODO: Tragt hier euren Bucket-Namen ein
# ============================================================
BUCKET_NAME = "gen-lang-client-0761701245-translation"
# ============================================================


@app.route("/")
def index():
    return """<!DOCTYPE html>
<html lang="de">
<head>
    <meta charset="utf-8">
    <title>Uebersetzungsservice</title>
    <style>
        body { font-family: system-ui, sans-serif; max-width: 700px; margin: 60px auto; padding: 0 20px; color: #1a1a1a; }
        h1 { border-bottom: 2px solid #4285f4; padding-bottom: 10px; }
        code { background: #f1f3f4; padding: 2px 6px; border-radius: 4px; font-size: 0.95em; }
        pre { background: #f1f3f4; padding: 16px; border-radius: 8px; overflow-x: auto; }
        .endpoint { margin: 20px 0; padding: 16px; border-left: 4px solid #4285f4; background: #f8f9fa; }
        .method { font-weight: bold; color: #4285f4; }
    </style>
</head>
<body>
    <h1>Uebersetzungsservice</h1>
    <p>Diese App nimmt Textdateien entgegen, speichert sie in einem Cloud Storage Bucket
       und eine Cloud Function uebersetzt sie automatisch.</p>

    <div class="endpoint">
        <p><span class="method">POST</span> <code>/upload</code></p>
        <p>Datei hochladen:</p>
        <pre>curl -F "file=@meine_datei.txt" DIESE_URL/upload</pre>
    </div>

    <div class="endpoint">
        <p><span class="method">GET</span> <code>/translations</code></p>
        <p>Alle uebersetzten Dateien auflisten.</p>
    </div>

    <div class="endpoint">
        <p><span class="method">GET</span> <code>/download/DATEINAME</code></p>
        <p>Uebersetzte Datei herunterladen.</p>
    </div>
</body>
</html>"""


@app.route("/upload", methods=["POST"])
def upload():
    if "file" not in request.files:
        return jsonify({"error": "Kein 'file' im Request. Nutze: curl -F 'file=@datei.txt' URL/upload"}), 400

    uploaded_file = request.files["file"]
    if uploaded_file.filename == "":
        return jsonify({"error": "Kein Dateiname"}), 400

    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    blob = bucket.blob(f"uploads/{uploaded_file.filename}")
    blob.upload_from_file(uploaded_file, content_type="text/plain")

    return jsonify({
        "status": "ok",
        "datei": uploaded_file.filename,
        "bucket_pfad": f"gs://{BUCKET_NAME}/uploads/{uploaded_file.filename}",
        "hinweis": "Die Cloud Function uebersetzt die Datei automatisch. "
                   "Pruefe in ein paar Sekunden GET /translations",
    })


@app.route("/translations")
def list_translations():
    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    blobs = list(bucket.list_blobs(prefix="translated/"))

    files = []
    for blob in blobs:
        name = blob.name.removeprefix("translated/")
        if name:
            files.append({"name": name, "download": f"/download/{name}"})

    return jsonify({"anzahl": len(files), "translations": files})


@app.route("/download/<filename>")
def download(filename):
    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    blob = bucket.blob(f"translated/{filename}")

    if not blob.exists():
        return jsonify({
            "error": f"'{filename}' noch nicht uebersetzt.",
            "tipp": "Warte ein paar Sekunden und versuche es erneut.",
        }), 404

    content = blob.download_as_bytes()
    return Response(
        content,
        mimetype="text/plain",
        headers={"Content-Disposition": f"attachment; filename=translated_{filename}"},
    )


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", 8080)))
