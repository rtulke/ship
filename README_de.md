# Ship ein Anwendungs-Updater

![Python](https://img.shields.io/badge/python-3.8+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Status](https://img.shields.io/badge/status-production--ready-brightgreen.svg)

Ein Python-basiertes Update-System für Anwendungen mit Unterstützung für Git, HTTP/HTTPS und SFTP-Quellen. Entwickelt für unbeaufsichtigten Betrieb auf Remote-Systemen mit intelligenter Konfigurationsverwaltung und automatischen Rollback-Funktionen.

## 🚀 Hauptfeatures

- **Multiple Update-Quellen**: Git-Repositories, HTTP/HTTPS-URLs, SFTP-Server
- **Intelligente Konfigurationsverwaltung**: Automatisches Merging von Config-Dateien ohne Überschreibung von Benutzereinstellungen
- **Zero-Downtime Updates**: Staged Rollouts und Canary-Deployments
- **Conditional Updates**: If/Then-Logik für situationsabhängige Updates
- **Automatische Rollbacks**: Bei fehlgeschlagenen Health-Checks oder Service-Startproblemen
- **Security-First**: Checksum-Verifikation, Dateityp-Validation, minimale Berechtigungen
- **Comprehensive Testing**: Post-Update Health-Checks mit Retry-Logik
- **Multi-Channel Benachrichtigungen**: Slack, Webhooks, E-Mail, Logs
- **Directory Protection**: Benutzerdaten bleiben unberührt (`data/`, `images/`, `uploads/`)
- **Migration Support**: Versions-spezifische Upgrade-Scripts

## 📋 Inhaltsverzeichnis

- [Installation](#installation)
- [Konfiguration](#konfiguration)
- [Update-Manifest](#update-manifest)
- [Workflow](#workflow)
- [Linux Service Setup](#linux-service-setup)
- [Update-Quellen](#update-quellen)
- [Beispiele](#beispiele)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Contributing](#contributing)

## 🛠 Installation

### Systemanforderungen

- **Betriebssystem**: Linux
- **Python**: 3.8 oder höher
- **Git**: Für Git-basierte Updates
- **systemd**: Für automatische Ausführung
- **Speicherplatz**: Mindestens 100MB für Backups

### Automatische Installation

```bash
# Repository klonen
git clone https://github.com/rtulke/ship.git
cd ship

# Installation ausführen (als root)
chmod +x install.sh
sudo ./install.sh
```

### Manuelle Installation

```bash
# ship-Benutzer erstellen
sudo useradd -r -s /bin/false -d /var/lib/ship ship

# Verzeichnisse erstellen
sudo mkdir -p /opt/ship /etc/ship /var/lib/ship /var/log

# Virtual Environment erstellen
cd /opt/ship
python3 -m venv venv
source venv/bin/activate

# Dependencies installieren
pip install -r requirements.txt

# Dateien kopieren
sudo cp ship.py /opt/ship/
sudo cp ship.toml /etc/ship/
sudo cp *.service *.timer /etc/systemd/system/

# Berechtigungen setzen
sudo chown -R ship:ship /var/lib/ship
sudo chmod +x /opt/ship/ship.py
sudo chmod 600 /etc/ship/ship.toml

# Systemd konfigurieren
sudo systemctl daemon-reload
sudo systemctl enable ship.timer
sudo systemctl start ship.timer
```

## ⚙️ Konfiguration

### Hauptkonfiguration (`/etc/ship/ship.toml`)

```toml
[general]
# State-Datei für Tracking der letzten Ausführung
state_file = "/var/lib/shipr/.ship_state.json"
backup_dir = "/var/lib/ship/backups"

[general.logging]
level = "INFO"
file = "/var/log/ship.log"

# Git Repository als Update-Quelle
[sources.main_app]
type = "git"
local_path = "/opt/myapp"
app_dir = "/opt/myapp"
branch = "main"

# HTTP/HTTPS Release-Quelle
[sources.release_archive]
type = "https"
url = "https://github.com/user/repo/releases/latest/download/release.tar.gz"
app_dir = "/opt/myapp"
filename = "release.tar.gz"
checksum = "sha256:abc123..."
metadata_file = "/var/lib/ship/.http_metadata.json"

[sources.release_archive.headers]
Authorization = "Bearer YOUR_TOKEN"

# SFTP-Quelle für private Deployments
[sources.sftp_deploy]
type = "sftp"
hostname = "deploy.example.com"
username = "deployer"
key_filename = "/home/ship/.ssh/id_rsa"
remote_path = "/releases/myapp-latest.tar.gz"
app_dir = "/opt/myapp"
metadata_file = "/var/lib/ship/.sftp_metadata.json"
```

### Systemd Timer Konfiguration

```ini
# /etc/systemd/system/ship.timer
[Unit]
Description=Run Ship Application Updater Daily
Requires=ship.service

[Timer]
# Täglich um 6:00 Uhr ausführen
OnCalendar=*-*-* 06:00:00
# Bei Boot ausführen falls verpasst
Persistent=true
# Zufällige Verzögerung bis zu 30 Minuten
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
```

## 📄 Update-Manifest

Das Update-Manifest (`update-manifest.yaml`) definiert präzise, wie Updates angewendet werden:

### Beispiel-Manifest

```yaml
version: "1.2.3"
release_date: "2025-01-20"
description: "Bugfixes und neue Features"

# Datei-spezifische Regeln
files:
  # Konfigurationsdateien - intelligentes Merging
  "config.toml":
    action: "merge_toml"
    merge_strategy: "preserve_user"
    backup: true

  "config/*.toml":
    action: "merge_toml"
    merge_strategy: "preserve_user"

  # Anwendungscode - immer ersetzen
  "src/**/*.py":
    action: "replace"

  "requirements.txt":
    action: "replace"

  # Sensible Dateien - nie anfassen
  ".env":
    action: "skip"

  "secrets/*":
    action: "skip"

# Verzeichnis-Schutz
directories:
  # Benutzerdaten - immer bewahren
  "data":
    preserve: true
    description: "Benutzerdaten"

  "images":
    preserve: true
    description: "Hochgeladene Bilder"

  "logs":
    preserve: true
    cleanup_old: true
    keep_days: 30

  # Cache - kann gelöscht werden
  "cache":
    preserve: false

# Update-Hooks
hooks:
  pre_update:
    - "systemctl stop myapp.service"
    - "python3 scripts/pre_update_check.py"

  post_update:
    - "pip install -r requirements.txt"
    - "python3 scripts/migrate.py"
    - "systemctl start myapp.service"
    - "python3 scripts/health_check.py"

  rollback:
    - "systemctl stop myapp.service"
    - "systemctl start myapp.service"

# Systemanforderungen
requirements:
  min_python_version: "3.8"
  min_disk_space_mb: 100
  required_services:
    - "postgresql"
  environment_checks:
    - name: "database_connectivity"
      command: "python3 scripts/check_db.py"

# Automatische Rollback-Trigger
rollback:
  strategy: "full_backup"
  keep_backups: 5
  auto_rollback_on:
    - "health_check_fail"
    - "service_start_fail"

# Post-Update Tests
post_update_tests:
  - name: "Import-Test"
    command: "python3 -c 'import myapp; print(\"OK\")'"
    timeout: 30

  - name: "Service Health"
    command: "curl -f http://localhost:8000/health"
    timeout: 30
    retry_count: 3
    retry_delay: 5

# Benachrichtigungen
notifications:
  on_success:
    - type: "webhook"
      url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
      message: "✅ MyApp erfolgreich auf {version} aktualisiert"

  on_failure:
    - type: "webhook"
      url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
      message: "❌ MyApp Update fehlgeschlagen: {error}"

# Erweiterte Features
conditionals:
  - condition: "file_exists('/opt/myapp/.maintenance_mode')"
    action: "skip_update"
    message: "System im Wartungsmodus"

migrations:
  "1.2.0":
    - "python3 scripts/migrate_database.py"
    - "python3 scripts/update_config_format.py"

cleanup:
  remove_files: ["*.pyc", "__pycache__"]
  remove_directories: ["legacy_modules"]
  commands:
    - "find /opt/myapp -name '*.pyc' -delete"
```

## 🔄 Workflow

### Entwickler-Workflow (Git-basiert)

#### 1. Neue Version entwickeln

```bash
# Code-Änderungen machen
git add .
git commit -m "Version 1.2.3: Neue Features und Bugfixes"

# Update-Manifest erstellen/anpassen
cat > update-manifest.yaml << EOF
version: "1.2.3"
description: "Neue Features und Bugfixes"
# ... weitere Konfiguration
EOF

# Manifest committen
git add update-manifest.yaml
git commit -m "Add update manifest for v1.2.3"
```

#### 2. Release erstellen

```bash
# Mit Release-Helper (empfohlen)
./release.sh interactive

# Oder manuell
git tag v1.2.3
git push origin main --tags
```

#### 3. System-seitiger Update-Prozess

```bash
# Läuft automatisch täglich um 6:00 Uhr
# 1. Git fetch origin
# 2. Vergleicht Commits (local vs remote)
# 3. Findet neue Version v1.2.3
# 4. Lädt Update-Manifest
# 5. Prüft Voraussetzungen
# 6. Erstellt Backup
# 7. Wendet Datei-Regeln an
# 8. Führt Migrations aus
# 9. Startet Services neu
# 10. Führt Health-Checks durch
# 11. Sendet Benachrichtigungen
```

### HTTP/HTTPS-Workflow

#### 1. Release-Paket erstellen

```bash
# Automatisch mit Release-Helper
./release.sh http v1.2.3 "Neue Features"

# Oder manuell
mkdir myapp-v1.2.3
cp -r src config templates static update-manifest.yaml myapp-v1.2.3/
tar czf myapp-v1.2.3.tar.gz myapp-v1.2.3/
sha256sum myapp-v1.2.3.tar.gz > myapp-v1.2.3.tar.gz.sha256
```

#### 2. Upload zu Server/GitHub Releases

```bash
# GitHub Releases API
curl -H "Authorization: token YOUR_TOKEN" \
     -H "Content-Type: application/octet-stream" \
     --data-binary @myapp-v1.2.3.tar.gz \
     "https://uploads.github.com/repos/user/repo/releases/123/assets?name=myapp-v1.2.3.tar.gz"
```

### SFTP-Workflow

```bash
# Mit Release-Helper
./release.sh sftp v1.2.3 "Hotfix" deploy.server.com deployer /releases/

# Oder manuell
scp myapp-v1.2.3.tar.gz deployer@deploy.server.com:/releases/myapp-latest.tar.gz
```

## 🐧 Linux Service Setup

### Systemd Service erstellen

```bash
# Service-Datei: /etc/systemd/system/ship.service
sudo tee /etc/systemd/system/ship.service > /dev/null << 'EOF'
[Unit]
Description=Ship Application Updater Service
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
User=ship
Group=ship
Environment=PYTHONPATH=/opt/ship
WorkingDirectory=/opt/ship
ExecStart=/opt/ship/venv/bin/python /opt/ship/ship.py --config /etc/ship/ship.toml
StandardOutput=journal
StandardError=journal

# Security Hardening
PrivateTmp=true
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/var/lib/ship /var/log /opt/myapp
ProtectHome=true
CapabilityBoundingSet=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@debug @mount @cpu-emulation @obsolete @privileged @reboot @swap @raw-io

[Install]
WantedBy=multi-user.target
EOF

# Timer-Datei: /etc/systemd/system/ship.timer
sudo tee /etc/systemd/system/ship.timer > /dev/null << 'EOF'
[Unit]
Description=Run Ship Application Updater Daily
Requires=ship.service

[Timer]
OnCalendar=*-*-* 06:00:00
Persistent=true
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
EOF

# Services aktivieren
sudo systemctl daemon-reload
sudo systemctl enable ship.timer
sudo systemctl start ship.timer
```

### Service-Management

```bash
# Status prüfen
sudo systemctl status ship.timer
sudo systemctl status ship.service

# Nächsten geplanten Lauf anzeigen
systemctl list-timers ship.timer

# Manuell ausführen
sudo systemctl start ship.service

# Logs verfolgen
sudo journalctl -u ship.service -f
sudo tail -f /var/log/ship.log

# Service stoppen/deaktivieren
sudo systemctl stop ship.timer
sudo systemctl disable ship.timer
```

## 🔧 Update-Quellen

### Git Repository

**Vorteile:**
- Automatische Erkennung geänderter Dateien
- Branch-Support für verschiedene Umgebungen
- Vollständige Versionskontrolle
- Kein separater Deployment-Prozess

**Setup:**
```bash
# Repository initialisieren
git clone https://github.com/user/myapp.git /opt/myapp
cd /opt/myapp
git checkout main

# SSH-Keys für automatischen Zugriff
sudo -u ship ssh-keygen -t rsa -b 4096 -f /home/ship/.ssh/id_rsa
# Public Key zu GitHub/GitLab hinzufügen
```

### HTTP/HTTPS

**Vorteile:**
- Einfache Integration mit CI/CD
- Unterstützung für GitHub Releases
- ETag-basierte Change-Detection
- Checksum-Verifikation

**Setup:**
```bash
# GitHub Personal Access Token erstellen
# In ship.toml konfigurieren:
[sources.github_releases.headers]
Authorization = "Bearer ghp_xxxxxxxxxxxxxxxxxxxx"
```

### SFTP

**Vorteile:**
- Sichere Übertragung
- Firewall-freundlich
- Einfache Server-zu-Server Übertragung
- SSH-Key basierte Authentifizierung

**Setup:**
```bash
# SSH-Keys für SFTP-Zugriff
sudo -u ship ssh-keygen -t rsa -b 4096 -f /home/ship/.ssh/sftp_key
sudo -u ship ssh-copy-id -i /home/ship/.ssh/sftp_key deployer@sftp.server.com

# SFTP-Zugriff testen
sudo -u ship sftp -i /home/ship/.ssh/sftp_key deployer@sftp.server.com
```

## 💡 Beispiele

### Einfaches Update (nur Python-Dateien)

```yaml
# update-manifest.yaml
version: "1.0.1"
description: "Bugfix Release"

files:
  "*.py":
    action: "replace"
  "src/**/*.py":
    action: "replace"

hooks:
  post_update:
    - "systemctl restart myapp.service"
```

### Komplexes Update mit Datenbank-Migration

```yaml
version: "2.0.0"
description: "Major Release mit DB-Schema Änderungen"

files:
  "config.toml":
    action: "merge_toml"
    merge_strategy: "preserve_user"
  "src/**/*.py":
    action: "replace"

directories:
  "data":
    preserve: true
  "uploads":
    preserve: true

requirements:
  min_disk_space_mb: 500
  required_services:
    - "postgresql"

conditionals:
  - condition: "current_version < '2.0.0'"
    action: "require_manual_intervention"
    message: "Major Version Upgrade - manuelle Schritte erforderlich"
    manual_steps:
      - "Datenbank-Backup erstellen"
      - "Breaking Changes in CHANGELOG.md prüfen"

migrations:
  "2.0.0":
    - "python3 scripts/migrate_database_v2.py"
    - "python3 scripts/rebuild_search_index.py"

hooks:
  pre_update:
    - "systemctl stop myapp.service"
    - "python3 scripts/backup_database.py"
  
  post_update:
    - "python3 scripts/migrate_database.py"
    - "systemctl start myapp.service"

post_update_tests:
  - name: "Database Migration"
    command: "python3 scripts/verify_db_schema.py"
    timeout: 120

  - name: "API Health"
    command: "curl -f http://localhost:8000/api/health"
    retry_count: 5
    retry_delay: 10

rollback:
  auto_rollback_on:
    - "health_check_fail"
    - "service_start_fail"

notifications:
  on_success:
    - type: "webhook"
      url: "https://hooks.slack.com/services/..."
      message: "🎉 MyApp v{version} erfolgreich deployed!"
  
  on_failure:
    - type: "webhook" 
      url: "https://hooks.slack.com/services/..."
      message: "🚨 MyApp Update v{version} fehlgeschlagen: {error}"
```

### Konfiguration-Only Update

```yaml
version: "1.1.1"
description: "Konfiguration-Update ohne Code-Änderungen"

files:
  "config/app.toml":
    action: "merge_toml"
    merge_strategy: "update_only"  # Nur neue Keys hinzufügen
  
  "config/features.json":
    action: "replace"

hooks:
  post_update:
    - "systemctl reload myapp.service"  # Reload statt Restart

post_update_tests:
  - name: "Config Validation"
    command: "python3 -c 'import myapp.config; myapp.config.validate()'"
```

## 🛠 CLI-Nutzung

### Grundlegende Kommandos

```bash
# Update-Check ohne Anwendung
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --check-only

# Erzwungenes Update (umgeht "einmal täglich" Regel)
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --force

# Spezifische Update-Quellen
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --sources main_app config_repo

# Rollback zum letzten Backup
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --rollback /var/lib/ship/backups/backup_pre_update_1.2.3

# Manifest-Validierung
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --test-manifest /path/to/update-manifest.yaml

# Rollout-Berechtigung prüfen
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --check-rollout /path/to/update-manifest.yaml
```

### Release-Management

```bash
# Interaktiver Release-Prozess
./release.sh interactive

# Git-Release erstellen
./release.sh git v1.2.3 "Neue Features und Bugfixes"

# HTTP-Release-Paket erstellen
./release.sh http v1.2.3 "Hotfix für kritischen Bug"

# SFTP-Upload
./release.sh sftp v1.2.3 "Emergency Fix" deploy.server.com deployer /releases/

# Nur Manifest erstellen
./release.sh manifest v1.2.3
```

## 🚨 Troubleshooting

### Häufige Probleme

#### 1. Berechtigungsfehler

```bash
# Problem: Permission denied
# Lösung: Berechtigungen prüfen
sudo chown -R ship:ship /var/lib/ship
sudo chmod +x /opt/ship/ship.py
sudo chmod 600 /etc/ship/ship.toml
```

#### 2. Git-Authentifizierung fehlgeschlagen

```bash
# Problem: Git fetch failed
# Lösung: SSH-Keys prüfen
sudo -u ship ssh -T git@github.com
sudo -u ship git -C /opt/myapp fetch origin
```

#### 3. Service startet nach Update nicht

```bash
# Problem: Service failed to start
# Lösung: Automatischer Rollback sollte greifen
# Manueller Rollback falls nötig:
sudo systemctl start app-rollback.service

# Oder spezifisches Backup:
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --rollback /var/lib/ship/backups/backup_pre_update_1.2.2
```

#### 4. Update hängt / Timeout

```bash
# Problem: Update process hangs
# Lösung: Process beenden und Rollback
sudo pkill -f "ship.py"
sudo systemctl start app-rollback.service

# Logs prüfen:
sudo journalctl -u ship.service --since "1 hour ago"
```

#### 5. Disk Space Issues

```bash
# Problem: Insufficient disk space
# Lösung: Alte Backups bereinigen
sudo find /var/lib/ship/backups -type d -mtime +30 -exec rm -rf {} \;

# Logs rotieren:
sudo logrotate -f /etc/logrotate.d/ship
```

### Debug-Modus

```bash
# Detailliertes Logging aktivieren
# In /etc/ship/ship.toml:
[general.logging]
level = "DEBUG"

# Einzelne Komponenten testen:
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship.py --test-manifest update-manifest.yaml
sudo -u ship /opt/ship/venv/bin/python /optshipr/ship.py --check-requirements update-manifest.yaml
```

### Monitoring

```bash
# System Health Check
#!/bin/bash
# /usr/local/bin/ship-healthcheck.sh

echo "=== Ship Health Check ==="

# Timer Status
echo "Timer Status:"
systemctl is-active ship.timer

# Letzter Run
echo "Letzter erfolgreicher Run:"
if [ -f /var/lib/ship/.ship_state.json ]; then
    cat /var/lib/ship/.ship_state.json | jq -r '.last_run'
else
    echo "Keine State-Datei gefunden"
fi

# Disk Space
echo "Backup Disk Usage:"
du -sh /var/lib/ship/backups/

# Log Errors (letzte 24h)
echo "Fehler in den letzten 24h:"
journalctl -u ship.service --since "24 hours ago" | grep -i error | wc -l
```

## 🔒 Security

### Sicherheits-Features

- **Minimale Berechtigungen**: Läuft als eigener `ship` User ohne Shell-Zugriff
- **Systemd Security**: NoNewPrivileges, ProtectSystem, CapabilityBoundingSet
- **Checksum-Verifikation**: SHA256-Hashes für Download-Integrität
- **File-Type Validation**: Nur erlaubte Dateitypen werden verarbeitet
- **Size Limits**: Maximale Dateigrößen konfigurierbar
- **Secure Temp**: PrivateTmp für temporäre Dateien
- **System Call Filtering**: Eingeschränkte Syscalls via SystemCallFilter

### Empfohlene Sicherheitskonfiguration

```toml
# In ship.toml
[sources.main_app.security]
verify_checksums = true
allowed_file_types = [".py", ".toml", ".json", ".sql", ".md", ".txt", ".yaml"]
max_file_size_mb = 50

# Privilegierte Dateien separat behandeln
privileged_files = ["scripts/system_config.py"]
```

### Netzwerk-Sicherheit

```bash
# Firewall-Regeln für Git über SSH
sudo ufw allow out 22 comment "Git SSH access"

# Für HTTPS-Updates
sudo ufw allow out 443 comment "HTTPS updates"

# Eingehende Verbindungen blockieren (nur ausgehend)
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## 🤝 Contributing

### Development Setup

```bash
git clone https://github.com/rtulke/ship.git
cd ship

# Development Environment
python3 -m venv dev-env
source dev-env/bin/activate
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Pre-commit hooks
pre-commit install

# Tests ausführen
python -m pytest tests/
python -m pytest tests/ --cov=ship

# Linting
flake8 .
black .
isort .
```

### Testing

```bash
# Unit Tests
python -m pytest tests/unit/

# Integration Tests
python -m pytest tests/integration/

# End-to-End Tests (benötigt Docker)
python -m pytest tests/e2e/

# Performance Tests
python -m pytest tests/performance/
```

### Dokumentation

```bash
# Dokumentation generieren
cd docs/
make html

# API-Dokumentation
pydoc -w ship
```

## 📄 Lizenz

MIT License - siehe [LICENSE](LICENSE) Datei für Details.

## 🆘 Support

- **Dokumentation**: [GitHub Wiki](https://github.com/rtulke/ship/wiki)
- **Issues**: [GitHub Issues](https://github.com/rtulke/ship/issues)
- **Discussions**: [GitHub Discussions](https://github.com/rtulke/ship/discussions)

---

**Entwickelt mit ❤️ für robuste, unbeaufsichtigte Anwendungs-Updates**
