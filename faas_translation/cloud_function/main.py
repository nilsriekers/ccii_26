import functions_framework
import requests
from google.cloud import storage

# ============================================================
#  TODO: Tragt hier euren DeepL-API-Key und die Zielsprache ein
# ============================================================
DEEPL_AUTH_KEY = "4fbe961c-643a-43e5-89eb-6b18f80f2163:fx"
TARGET_LANG = "EN"
# ============================================================

DEEPL_URL = "https://api-free.deepl.com/v2/translate"


@functions_framework.cloud_event
def translate_on_upload(cloud_event):
    """Wird automatisch ausgeloest, wenn eine Datei im Bucket landet."""
    data = cloud_event.data
    bucket_name = data["bucket"]
    file_name = data["name"]

    if not file_name.startswith("uploads/"):
        print(f"Uebersprungen: {file_name} (nicht im uploads/ Ordner)")
        return

    client = storage.Client()
    bucket = client.bucket(bucket_name)
    blob = bucket.blob(file_name)
    text = blob.download_as_text()

    print(f"Uebersetze {file_name} ({len(text)} Zeichen) nach {TARGET_LANG} ...")

    response = requests.post(
        DEEPL_URL,
        headers={"Authorization": f"DeepL-Auth-Key {DEEPL_AUTH_KEY}"},
        data={"text": text, "target_lang": TARGET_LANG},
    )
    response.raise_for_status()
    translated_text = response.json()["translations"][0]["text"]

    original_name = file_name.removeprefix("uploads/")
    translated_blob = bucket.blob(f"translated/{original_name}")
    translated_blob.upload_from_string(translated_text, content_type="text/plain")

    print(f"Fertig: {file_name} -> translated/{original_name}")
