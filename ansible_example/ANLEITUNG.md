# Anleitung: Monitoring mit Ansible aufsetzen (Node Exporter + Prometheus + Grafana)

## Was macht dieses Setup?

Mit diesem Ansible-Playbook wird automatisch ein Monitoring-Stack installiert:

| Komponente | Wo | Was macht sie |
|------------|----|---------------|
| **Node Exporter** | Lokale VM + Remote VM | Sammelt System-Metriken (CPU, RAM, Disk, Netzwerk) und stellt sie auf Port 9100 bereit |
| **Prometheus** | Lokale VM | Fragt die Node Exporter regelmäßig ab und speichert die Metriken in einer Zeitreihen-Datenbank |
| **Grafana** | Lokale VM | Web-Dashboard zur Visualisierung der Metriken (Port 3000) |

```
                  ┌──────────────────────┐
                  │   Lokale VM          │
                  │                      │
                  │  Grafana (:3000)     │
                  │    ↓ liest von       │
                  │  Prometheus (:9090)  │
                  │    ↓ scraped         │
                  │  Node Exporter(:9100)│
                  │    ↓ scraped auch    │
                  └──────────┬───────────┘
                             │
                     IPv6-Verbindung
                             │
                  ┌──────────┴───────────┐
                  │   Remote VM          │
                  │  Node Exporter(:9100)│
                  └──────────────────────┘
```

---

## Voraussetzungen

- Ansible ist installiert (`sudo apt-get install -y ansible`)
- Die Remote-VM wurde mit Terraform erstellt (siehe `terraform_example/ANLEITUNG.md`)
- SSH-Zugang zur Remote-VM funktioniert (testen mit `ssh ubuntu@IPV6-ADRESSE`)

---

## Schritt 1: Inventory anpassen

Bearbeitet die Datei `inventory.ini`:

```bash
vim inventory.ini
```

Ersetzt `EURE_IPV6_ADRESSE` mit der IPv6-Adresse eurer Terraform-VM.

Die IPv6-Adresse findet ihr so:

```bash
cd ../terraform_example
terraform output vm_external_ipv6
```

Beispiel-Ergebnis im Inventory:

```ini
[local]
localhost ansible_connection=local

[remote_vms]
meine-vm ansible_host=2600:1900:4010:154:: ansible_user=ubuntu
```

---

## Schritt 2: Verbindung testen

Prüft, ob Ansible alle Hosts erreichen kann:

```bash
cd ~/git/cloud_lecture04/ansible_example
ansible all -m ping
```

Erwartete Ausgabe:

```
localhost | SUCCESS => { "ping": "pong" }
meine-vm | SUCCESS => { "ping": "pong" }
```

Falls die Remote-VM nicht erreichbar ist, prüft:
1. Stimmt die IPv6-Adresse? `terraform output vm_external_ipv6`
2. Funktioniert SSH direkt? `ssh ubuntu@EURE-IPV6-ADRESSE`
3. Ist Port 22 offen? (Firewall-Regeln werden von Terraform erstellt)

---

## Schritt 3: Playbook ausführen

Startet die Installation:

```bash
ansible-playbook playbook.yml
```

> Das dauert ca. 2-5 Minuten. Ansible zeigt euch für jeden Schritt an, was passiert.

Erwartete Ausgabe am Ende:

```
PLAY RECAP *************************************************************
localhost    : ok=X  changed=X  unreachable=0  failed=0
meine-vm    : ok=X  changed=X  unreachable=0  failed=0
```

> Wichtig: `failed=0` bei allen Hosts!

---

## Schritt 4: Prüfen ob alles läuft

### Node Exporter (auf beiden VMs)

```bash
curl -s http://localhost:9100/metrics | head -5
```

Auf der Remote-VM:

```bash
curl -s http://[EURE-IPV6-ADRESSE]:9100/metrics | head -5
```

### Prometheus (auf der lokalen VM)

```bash
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool
```

> Ihr solltet zwei Targets sehen: `localhost:9100` und `[ipv6]:9100`, beide mit `state: "up"`.

### Grafana (auf der lokalen VM)

Grafana läuft auf Port **3000**:

```bash
curl -s http://localhost:3000/api/health
```

Erwartete Ausgabe: `{"commit":"...","database":"ok","version":"..."}`

---

## Schritt 5: Zugriff auf die Web-Oberflächen (SSH-Tunnel)

Die Services laufen auf der VM und sind nicht direkt aus dem Internet erreichbar.
Ihr müsst einen **SSH-Tunnel** aufbauen, um die Ports auf euren lokalen Rechner weiterzuleiten.

### 5.1 SSH-Tunnel aufbauen

Öffnet ein **neues Terminal auf eurem lokalen Rechner** (nicht auf der VM!) und baut den Tunnel auf:

```bash
ssh \
  -L 3000:localhost:3000 \
  -L 9090:localhost:9090 \
  -L 9100:localhost:9100 \
  -L 9101:[REMOTE-VM-IPV6]:9100 \
  -J bridge_user@84.252.121.147 \
  ubuntu@2001:7c0:2320:2:f816:3eff:fe02:13c3
```

> Ersetzt `REMOTE-VM-IPV6` mit der IPv6-Adresse eurer Terraform-VM (z.B. `2600:1900:4010:154::`).

**Was passiert hier?**

| Flag | Bedeutung |
|------|-----------|
| `-L 3000:localhost:3000` | Grafana: euer `localhost:3000` wird auf die VM weitergeleitet |
| `-L 9090:localhost:9090` | Prometheus: euer `localhost:9090` wird auf die VM weitergeleitet |
| `-L 9100:localhost:9100` | Node Exporter (lokal): Metriken der lokalen VM |
| `-L 9101:[IPV6]:9100` | Node Exporter (remote): Metriken der Terraform-VM, auf Port 9101 weil 9100 schon belegt |
| `-J bridge_user@...` | SSH-Jump-Host (Zwischenstation) |

> Lasst dieses Terminal **offen**, solange ihr auf die Weboberflächen zugreifen wollt.

### 5.2 Im Browser aufrufen

Solange der SSH-Tunnel steht, könnt ihr in eurem lokalen Browser folgende Adressen öffnen:

| Service | URL | Beschreibung |
|---------|-----|--------------|
| Grafana | `http://localhost:3000` | Dashboards und Visualisierung |
| Prometheus | `http://localhost:9090` | Metriken-Datenbank, Targets prüfen |
| Node Exporter (lokale VM) | `http://localhost:9100/metrics` | Rohe Metriken der lokalen VM |
| Node Exporter (Remote VM) | `http://localhost:9101/metrics` | Rohe Metriken der Terraform-VM |

### 5.3 Grafana einrichten

Öffnet `http://localhost:3000` im Browser.

Standard-Login:
- **Benutzer:** `admin`
- **Passwort:** `admin`

> Beim ersten Login werdet ihr aufgefordert ein neues Passwort zu setzen.

### 5.4 Prometheus als Datenquelle hinzufügen

1. Im Menü links: **Connections** -> **Data Sources**
2. **Add data source** klicken
3. **Prometheus** auswählen
4. Bei **URL** eingeben: `http://localhost:9090`
5. Ganz unten: **Save & Test** klicken
6. Erwartete Meldung: "Successfully queried the Prometheus API"

### 5.5 Dashboard importieren

1. Im Menü links: **Dashboards** -> **New** -> **Import**
2. Bei "Import via grafana.com" die ID **1860** eingeben
3. **Load** klicken
4. Bei "Prometheus" die eben erstellte Datenquelle auswählen
5. **Import** klicken

> Dashboard 1860 ist das offizielle "Node Exporter Full" Dashboard. Ihr seht dann CPU, RAM, Disk, Netzwerk etc. für alle Hosts.

---

## Zusammenfassung: Alle Befehle auf einen Blick

```bash
# 1. Ins Ansible-Verzeichnis wechseln
cd ~/git/cloud_lecture04/ansible_example

# 2. Inventory anpassen (IPv6-Adresse eintragen)
vim inventory.ini

# 3. Verbindung testen
ansible all -m ping

# 4. Playbook ausfuehren
ansible-playbook playbook.yml

# 5. Pruefen
curl -s http://localhost:9100/metrics | head -5
curl -s http://localhost:9090/api/v1/targets | python3 -m json.tool
curl -s http://localhost:3000/api/health

# 6. SSH-Tunnel aufbauen (auf EUREM lokalen Rechner, nicht auf der VM!)
ssh -L 3000:localhost:3000 -L 9090:localhost:9090 -L 9100:localhost:9100 -L 9101:[REMOTE-VM-IPV6]:9100 -J bridge_user@84.252.121.147 ubuntu@2001:7c0:2320:2:f816:3eff:fe02:13c3

# 7. Im lokalen Browser oeffnen
# Grafana:                http://localhost:3000
# Prometheus:             http://localhost:9090
# Node Exporter (lokal):  http://localhost:9100/metrics
# Node Exporter (remote): http://localhost:9101/metrics
```

---

## Fehlerbehebung

### "UNREACHABLE" bei der Remote-VM

Prüft die SSH-Verbindung:

```bash
ssh ubuntu@EURE-IPV6-ADRESSE
```

Falls das nicht geht: IPv6-Adresse im Inventory prüfen und sicherstellen, dass die Terraform-Firewall SSH erlaubt.

### Prometheus zeigt Target als "down"

Prüft, ob der Node Exporter auf der Remote-VM läuft:

```bash
ssh ubuntu@EURE-IPV6-ADRESSE "systemctl status prometheus-node-exporter"
```

Prüft, ob Port 9100 erreichbar ist:

```bash
curl -s http://[EURE-IPV6-ADRESSE]:9100/metrics | head -5
```

### "No space left on device" bei Grafana-Installation

Grafana braucht ca. 725 MB Speicherplatz. Prüft zuerst wie viel frei ist:

```bash
df -h /
```

Falls zu wenig frei ist, könnt ihr Speicher freigeben:

```bash
# 1. APT-Cache leeren (oft 200-300 MB)
sudo apt-get clean

# 2. Nicht mehr benoetigte Pakete entfernen
sudo apt-get autoremove -y

# 3. BPF/LLVM Debugging-Tools entfernen (ca. 250 MB, werden nicht benoetigt)
sudo apt-get remove -y bpfcc-tools bpftrace python3-bpfcc libbpfcc libclang-cpp18 libclang1-18 libllvm18
sudo apt-get autoremove -y

# 4. Alte Kernel entfernen (falls vorhanden, spart ca. 80 MB pro Kernel)
# Zuerst pruefen welcher Kernel laeuft:
uname -r
# Dann alte Kernel auflisten:
dpkg -l | grep linux-image | grep -v $(uname -r)
# Alte Kernel entfernen (NICHT den laufenden!):
# sudo apt-get remove -y linux-image-X.X.X-XX-generic linux-modules-X.X.X-XX-generic

# 5. Nochmal pruefen
df -h /
```

> Danach `ansible-playbook playbook.yml` erneut ausfuehren.

### Grafana startet nicht

```bash
sudo systemctl status grafana-server
sudo journalctl -u grafana-server -n 50
```

---

## Dateistruktur

```
ansible_example/
├── ansible.cfg                  # Ansible-Einstellungen
├── inventory.ini                # Host-Liste (hier IPv6 eintragen!)
├── playbook.yml                 # Haupt-Playbook (alle 3 Plays)
├── config_files/
│   └── prometheus.yml.j2        # Prometheus-Konfiguration (Template)
└── ANLEITUNG.md                 # Diese Anleitung
```

## Was ist was?

| Datei | Rolle |
|-------|-------|
| `ansible.cfg` | Sagt Ansible wo das Inventory liegt und deaktiviert Host-Key-Checking (praktisch im Lab) |
| `inventory.ini` | Liste aller Hosts, gruppiert in `local` und `remote_vms` |
| `playbook.yml` | Die eigentlichen Installationsschritte, aufgeteilt in 3 Plays |
| `prometheus.yml.j2` | Jinja2-Template: generiert die Prometheus-Config dynamisch aus dem Inventory |
