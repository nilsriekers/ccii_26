# Anleitung: VM in der Google Cloud mit Terraform erstellen

## Voraussetzungen

- Zugang zu einem GCP-Projekt (Projekt-ID + Projektnummer bereithalten)
- Eine VM oder ein lokaler Rechner mit installiertem `gcloud` CLI
- Internetzugang

---

## Schritt 1: GCP CLI authentifizieren

Falls ihr auf einer bestehenden GCP-VM arbeitet, ist `gcloud` bereits installiert.
Authentifiziert euch mit eurem Google-Account:

```bash
gcloud auth login
```

> Folgt dem Link im Terminal, meldet euch im Browser an und kopiert den Code zurück ins Terminal.

Setzt euer Projekt als Standard:

```bash
gcloud config set project EURE-PROJEKT-ID
```

Setzt die Application Default Credentials (braucht Terraform für die Authentifizierung):

```bash
gcloud auth application-default login
```

> Auch hier dem Link folgen und im Browser bestätigen.

Prüft, ob alles funktioniert:

```bash
gcloud config list
```

---

## Schritt 2: Notwendige GCP APIs aktivieren

Terraform braucht die **Compute Engine API**, um VMs erstellen zu können.
Aktiviert sie mit folgendem Befehl:

```bash
gcloud services enable compute.googleapis.com
```

Optional aber empfohlen - prüft, ob die API aktiv ist:

```bash
gcloud services list --enabled --filter="name:compute.googleapis.com"
```

> **Hinweis:** Die Aktivierung kann bis zu 1-2 Minuten dauern. Wenn Terraform direkt danach Fehler wirft, einfach kurz warten und nochmal versuchen.

### Zusammenfassung der benötigten APIs

| API | Zweck | Befehl |
|-----|-------|--------|
| `compute.googleapis.com` | VMs, Netzwerke, Firewalls | `gcloud services enable compute.googleapis.com` |

> **Hinweis:** IPv6-Netzwerk und Firewall-Regeln werden automatisch von Terraform erstellt, kein manueller Schritt nötig.

---

## Schritt 3: Terraform installieren

### Auf Debian/Ubuntu (z.B. auf einer GCP-VM):

```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
```

```bash
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
```

```bash
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
```

```bash
sudo apt-get update && sudo apt-get install terraform
```

Prüft die Installation:

```bash
terraform version
```

---

## Schritt 4: SSH-Schlüssel erzeugen (falls noch keiner existiert)

Prüft, ob ihr schon einen SSH-Schlüssel habt:

```bash
ls ~/.ssh/id_rsa.pub
```

Falls nicht, erzeugt einen neuen:

```bash
ssh-keygen -t rsa -b 4096 -C "euer-name"
```

> Einfach bei allen Fragen Enter drücken (Standard-Pfad und kein Passwort).

Kopiert den öffentlichen Schlüssel in die Zwischenablage:

```bash
cat ~/.ssh/id_rsa.pub
```

> Diesen kompletten Output braucht ihr gleich für die Konfiguration.

---

## Schritt 5: Projekt-ID und Projektnummer herausfinden

Die **Projekt-ID** findet ihr in der Cloud Console oben links neben "Google Cloud".

Die **Projektnummer** findet ihr so:

```bash
gcloud projects describe EURE-PROJEKT-ID --format="value(projectNumber)"
```

Oder in der Cloud Console unter **IAM & Admin -> Settings**.

Notiert euch beide Werte!

---

## Schritt 6: Terraform-Konfiguration anpassen

### 6.1 Repository klonen (falls noch nicht geschehen)

```bash
git clone <REPO-URL>
cd cloud_lecture04/terraform_example
```

### 6.2 Variablen-Datei erstellen

Kopiert die Beispiel-Datei:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Bearbeitet die Datei mit vim:

```bash
vim terraform.tfvars
```

### 6.3 Folgende Werte anpassen

| Variable | Was eintragen | Wo finden |
|----------|--------------|-----------|
| `project_id` | Eure GCP Projekt-ID | Cloud Console, oben links neben "Google Cloud" oder `gcloud projects list` |
| `project_number` | Eure GCP Projektnummer | `gcloud projects list` |
| `region` | z.B. `europe-west1` | Kann so bleiben (Belgien) |
| `zone` | z.B. `europe-west1-b` | Kann so bleiben |
| `vm_name` | Beliebiger Name, z.B. `max-vm` | Frei wählbar |
| `machine_type` | z.B. `g1-small` | Kann so bleiben |
| `ssh_user` | `ubuntu` | Kann so bleiben |
| `ssh_public_key` | Output von `cat ~/.ssh/id_rsa.pub` | Siehe Schritt 4 |

In vim speichern: `Esc`, dann `:wq`, dann `Enter`.

---

## Schritt 7: Terraform ausführen

### 7.1 Terraform initialisieren

Lädt den Google-Provider herunter:

```bash
terraform init
```

Erwartete Ausgabe: `Terraform has been successfully initialized!`

### 7.2 Konfiguration prüfen

Prüft die Syntax:

```bash
terraform validate
```

Erwartete Ausgabe: `Success! The configuration is valid.`

### 7.3 Plan anzeigen (Vorschau)

Zeigt, was Terraform erstellen wird, **ohne** es tatsächlich zu tun:

```bash
terraform plan
```

> Lest die Ausgabe durch! Ihr solltet sehen, dass **1 Ressource erstellt** wird.

### 7.4 VM erstellen

Erstellt die VM tatsächlich:

```bash
terraform apply
```

> Terraform fragt euch `Do you want to perform these actions?` - tippt `yes` und drückt Enter.

Wartet ca. 30-60 Sekunden. Danach seht ihr die Outputs:
- **vm_external_ip** - Die externe IP-Adresse eurer VM
- **ssh_command** - Den fertigen SSH-Befehl

---

## Schritt 8: Mit der VM verbinden

Nutzt den SSH-Befehl aus dem Terraform-Output.

Per IPv6 (wenn ihr auf einer IPv6-only VM seid):

```bash
ssh ubuntu@IPV6-ADRESSE
```

Per IPv4:

```bash
ssh ubuntu@IPV4-ADRESSE
```

Oder direkt über gcloud:

```bash
gcloud compute ssh meine-vm --zone=europe-west1-b
```

---

## Schritt 9: VM wieder löschen (später!)

> **Achtung:** Löscht eure VM nach dem Praktikum, um keine Kosten zu verursachen!

```bash
terraform destroy
```

> Bestätigt mit `yes`.

---

## Fehlerbehebung

### "API not enabled" Fehler

```bash
gcloud services enable compute.googleapis.com
```

Wartet 1-2 Minuten und versucht es erneut.

### "Permission denied" Fehler

Prüft, ob ihr authentifiziert seid:

```bash
gcloud auth list
```

Falls kein Account aktiv ist:

```bash
gcloud auth login
```

### "Could not find default credentials"

Terraform nutzt Application Default Credentials. Setzt sie mit:

```bash
gcloud auth application-default login
```

### SSH-Verbindung funktioniert nicht

1. Prüft, ob die VM läuft: `terraform show | grep status`
2. Prüft die Firewall: Die Tags `http-server` und `https-server` erlauben Port 80/443. SSH (Port 22) ist im Default-Netzwerk standardmäßig erlaubt.
3. Prüft, ob der SSH-Key korrekt ist: `terraform show | grep ssh-keys`

---

## Übersicht: Alle Befehle auf einen Blick

```bash
# 1. Authentifizierung
gcloud auth login
gcloud config set project EURE-PROJEKT-ID
gcloud auth application-default login

# 2. API aktivieren
gcloud services enable compute.googleapis.com

# 3. Terraform installieren (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install terraform

# 4. SSH-Key erzeugen (falls keiner existiert)
ssh-keygen -t rsa -b 4096 -C "euer-name"

# 5. Projektnummer herausfinden
gcloud projects describe EURE-PROJEKT-ID --format="value(projectNumber)"

# 6. Konfiguration vorbereiten
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars

# 7. Terraform ausfuehren
terraform init
terraform validate
terraform plan
terraform apply

# 8. VM loeschen
terraform destroy
```

---

## Dateistruktur

```
terraform_example/
├── main.tf                  # Haupt-Konfiguration (VM-Definition)
├── variables.tf             # Variablen-Definitionen
├── terraform.tfvars.example # Beispiel-Werte (kopieren!)
├── terraform.tfvars         # Eure Werte (nicht im Git!)
└── ANLEITUNG.md             # Diese Anleitung
```
