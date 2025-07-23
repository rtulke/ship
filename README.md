# Ship Application Updater

ship - ships your code to next level a python updater for your application

![Python](https://img.shields.io/badge/python-3.8+-blue.svg)
![License](https://img.shields.io/badge/license-MIT-green.svg)
![Status](https://img.shields.io/badge/status-production--ready-brightgreen.svg)

<div align="right">
  <img src="logo/ship_100.png" alt="ship" width="100" />
</div>

A Python-based application update system supporting Git, HTTP/HTTPS, and SFTP sources. Designed for unattended operation on remote systems with intelligent configuration management and automatic rollback capabilities.


## 🚀 Key Features

- **Multiple Update Sources**: Git repositories, HTTP/HTTPS URLs, SFTP servers
- **Intelligent Configuration Management**: Automatic config file merging without overwriting user settings
- **Zero-Downtime Updates**: Staged rollouts and canary deployments
- **Conditional Updates**: If/then logic for situational updates
- **Automatic Rollbacks**: On failed health checks or service start problems
- **Security-First**: Checksum verification, file type validation, minimal permissions
- **Comprehensive Testing**: Post-update health checks with retry logic
- **Multi-Channel Notifications**: Slack, webhooks, logs
- **Directory Protection**: User data remains untouched (e.g. `data/`, `images/`, `uploads/`)
- **Migration Support**: Version-specific upgrade scripts

## 📋 Table of Contents

- [Installation](#installation)
- [Configuration](#configuration)
- [Update Manifest](#update-manifest)
- [Workflow](#workflow)
- [Linux Service Setup](#linux-service-setup)
- [Update Sources](#update-sources)
- [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Contributing](#contributing)

## 🛠 Installation

### System Requirements

- **Operating System**: Linux (preferably Debian/Ubuntu), macOS
- **Python**: 3.8 or higher
- **Git**: For Git-based updates
- **systemd**: For automatic execution
- **Storage**: At least 100MB for backups

### Automatic Installation

```bash
# Clone repository
git clone https://github.com/rtulke/ship.git
cd ship

# Run installation (as root)
chmod +x install.sh
sudo ./install.sh
```

### Manual Installation

```bash
# Create ship user
sudo useradd -r -s /bin/false -d /var/lib/ship ship

# Create directories
sudo mkdir -p /opt/ship /etc/ship /var/lib/ship /var/log

# Create virtual environment
cd /opt/ship
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Copy files
sudo cp ship /opt/ship/
sudo cp ship.toml /etc/ship/
sudo cp *.service *.timer /etc/systemd/system/

# Set permissions
sudo chown -R ship:ship /var/lib/ship
sudo chmod +x /opt/ship/ship
sudo chmod 600 /etc/ship/ship.toml

# Configure systemd
sudo systemctl daemon-reload
sudo systemctl enable ship.timer
sudo systemctl start ship.timer
```

## ⚙️ Configuration

### Main Configuration (`/etc/ship/ship.toml`)

```toml
[general]
# State file for tracking last execution
state_file = "/var/lib/ship/.ship_state.json"
backup_dir = "/var/lib/ship/backups"

[general.logging]
level = "INFO"
file = "/var/log/ship.log"

# Git repository as update source
[sources.main_app]
type = "git"
local_path = "/opt/myapp"
app_dir = "/opt/myapp"
branch = "main"

# HTTP/HTTPS release source
[sources.release_archive]
type = "https"
url = "https://github.com/user/repo/releases/latest/download/release.tar.gz"
app_dir = "/opt/myapp"
filename = "release.tar.gz"
checksum = "sha256:abc123..."
metadata_file = "/var/lib/ship/.http_metadata.json"

[sources.release_archive.headers]
Authorization = "Bearer YOUR_TOKEN"

# SFTP source for private deployments
[sources.sftp_deploy]
type = "sftp"
hostname = "deploy.example.com"
username = "deployer"
key_filename = "/home/ship/.ssh/id_rsa"
remote_path = "/releases/myapp-latest.tar.gz"
app_dir = "/opt/myapp"
metadata_file = "/var/lib/ship/.sftp_metadata.json"
```

### Systemd Timer Configuration

```ini
# /etc/systemd/system/ship.timer
[Unit]
Description=Run Application Updater Daily
Requires=ship.service

[Timer]
# Run daily at 6:00 AM
OnCalendar=*-*-* 06:00:00
# Run on boot if missed
Persistent=true
# Random delay up to 30 minutes
RandomizedDelaySec=1800

[Install]
WantedBy=timers.target
```

## 📄 Update Manifest

The update manifest (`update-manifest.yaml`) precisely defines how updates are applied:

### Example Manifest

```yaml
version: "1.2.3"
release_date: "2025-01-20"
description: "Bug fixes and new features"

# File-specific rules
files:
  # Configuration files - intelligent merging
  "config.toml":
    action: "merge_toml"
    merge_strategy: "preserve_user"
    backup: true

  "config/*.toml":
    action: "merge_toml"
    merge_strategy: "preserve_user"

  # Application code - always replace
  "src/**/*.py":
    action: "replace"

  "requirements.txt":
    action: "replace"

  # Sensitive files - never touch
  ".env":
    action: "skip"

  "secrets/*":
    action: "skip"

# Directory protection
directories:
  # User data - always preserve
  "data":
    preserve: true
    description: "User data"

  "images":
    preserve: true
    description: "Uploaded images"

  "logs":
    preserve: true
    cleanup_old: true
    keep_days: 30

  # Cache - can be cleared
  "cache":
    preserve: false

# Update hooks
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

# System requirements
requirements:
  min_python_version: "3.8"
  min_disk_space_mb: 100
  required_services:
    - "postgresql"
  environment_checks:
    - name: "database_connectivity"
      command: "python3 scripts/check_db.py"

# Automatic rollback triggers
rollback:
  strategy: "full_backup"
  keep_backups: 5
  auto_rollback_on:
    - "health_check_fail"
    - "service_start_fail"

# Post-update tests
post_update_tests:
  - name: "Import test"
    command: "python3 -c 'import myapp; print(\"OK\")'"
    timeout: 30

  - name: "Service health"
    command: "curl -f http://localhost:8000/health"
    timeout: 30
    retry_count: 3
    retry_delay: 5

# Notifications
notifications:
  on_success:
    - type: "webhook"
      url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
      message: "✅ MyApp successfully updated to {version}"

  on_failure:
    - type: "webhook"
      url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
      message: "❌ MyApp update failed: {error}"

# Advanced features
conditionals:
  - condition: "file_exists('/opt/myapp/.maintenance_mode')"
    action: "skip_update"
    message: "System in maintenance mode"

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

### Developer Workflow (Git-based)

#### 1. Develop new version

```bash
# Make code changes
git add .
git commit -m "Version 1.2.3: New features and bug fixes"

# Create/adjust update manifest
cat > update-manifest.yaml << EOF
version: "1.2.3"
description: "New features and bug fixes"
# ... additional configuration
EOF

# Commit manifest
git add update-manifest.yaml
git commit -m "Add update manifest for v1.2.3"
```

#### 2. Create release

```bash
# Using release helper (recommended)
./release.sh interactive

# Or manually
git tag v1.2.3
git push origin main --tags
```

#### 3. System-side update process

```bash
# Runs automatically daily at 6:00 AM
# 1. Git fetch origin
# 2. Compare commits (local vs remote)
# 3. Find new version v1.2.3
# 4. Load update manifest
# 5. Check prerequisites
# 6. Create backup
# 7. Apply file rules
# 8. Run migrations
# 9. Restart services
# 10. Perform health checks
# 11. Send notifications
```

### HTTP/HTTPS Workflow

#### 1. Create release package

```bash
# Automatically with release helper
./release.sh http v1.2.3 "New features"

# Or manually
mkdir myapp-v1.2.3
cp -r src config templates static update-manifest.yaml myapp-v1.2.3/
tar czf myapp-v1.2.3.tar.gz myapp-v1.2.3/
sha256sum myapp-v1.2.3.tar.gz > myapp-v1.2.3.tar.gz.sha256
```

#### 2. Upload to server/GitHub Releases

```bash
# GitHub Releases API
curl -H "Authorization: token YOUR_TOKEN" \
     -H "Content-Type: application/octet-stream" \
     --data-binary @myapp-v1.2.3.tar.gz \
     "https://uploads.github.com/repos/user/repo/releases/123/assets?name=myapp-v1.2.3.tar.gz"
```

### SFTP Workflow

```bash
# Using release helper
./release.sh sftp v1.2.3 "Hotfix" deploy.server.com deployer /releases/

# Or manually
scp myapp-v1.2.3.tar.gz deployer@deploy.server.com:/releases/myapp-latest.tar.gz
```

## 🐧 Linux Service Setup

### Create Systemd Service

```bash
# Service file: /etc/systemd/system/ship.service
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
ExecStart=/opt/ship/venv/bin/python /opt/ship/ship --config /etc/ship/ship.toml
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

# Timer file: /etc/systemd/system/ship.timer
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

# Enable services
sudo systemctl daemon-reload
sudo systemctl enable ship.timer
sudo systemctl start ship.timer
```

### Service Management

```bash
# Check status
sudo systemctl status ship.timer
sudo systemctl status ship.service

# Show next scheduled run
systemctl list-timers ship.timer

# Run manually
sudo systemctl start ship.service

# Follow logs
sudo journalctl -u ship.service -f
sudo tail -f /var/log/ship.log

# Stop/disable service
sudo systemctl stop ship.timer
sudo systemctl disable ship.timer
```

## 🔧 Update Sources

### Git Repository

**Advantages:**
- Automatic detection of changed files
- Branch support for different environments
- Complete version control
- No separate deployment process

**Setup:**
```bash
# Initialize repository
git clone https://github.com/user/myapp.git /opt/myapp
cd /opt/myapp
git checkout main

# SSH keys for automatic access
sudo -u ship ssh-keygen -t rsa -b 4096 -f /home/ship/.ssh/id_rsa
# Add public key to GitHub/GitLab
```

### HTTP/HTTPS

**Advantages:**
- Easy CI/CD integration
- GitHub Releases support
- ETag-based change detection
- Checksum verification

**Setup:**
```bash
# Create GitHub Personal Access Token
# Configure in ship.toml:
[sources.github_releases.headers]
Authorization = "Bearer ghp_xxxxxxxxxxxxxxxxxxxx"
```

### SFTP

**Advantages:**
- Secure transfer
- Firewall-friendly
- Simple server-to-server transfer
- SSH key-based authentication

**Setup:**
```bash
# SSH keys for SFTP access
sudo -u ship ssh-keygen -t rsa -b 4096 -f /home/ship/.ssh/sftp_key
sudo -u ship ssh-copy-id -i /home/ship/.ssh/sftp_key deployer@sftp.server.com

# Test SFTP access
sudo -u ship sftp -i /home/ship/.ssh/sftp_key deployer@sftp.server.com
```

## 💡 Examples

### Simple Update (Python files only)

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

### Complex Update with Database Migration

```yaml
version: "2.0.0"
description: "Major release with DB schema changes"

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
    message: "Major version upgrade - manual steps required"
    manual_steps:
      - "Create database backup"
      - "Review breaking changes in CHANGELOG.md"

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
      message: "🎉 MyApp v{version} successfully deployed!"
  
  on_failure:
    - type: "webhook" 
      url: "https://hooks.slack.com/services/..."
      message: "🚨 MyApp update v{version} failed: {error}"
```

### Configuration-Only Update

```yaml
version: "1.1.1"
description: "Configuration update without code changes"

files:
  "config/app.toml":
    action: "merge_toml"
    merge_strategy: "update_only"  # Only add new keys
  
  "config/features.json":
    action: "replace"

hooks:
  post_update:
    - "systemctl reload myapp.service"  # Reload instead of restart

post_update_tests:
  - name: "Config Validation"
    command: "python3 -c 'import myapp.config; myapp.config.validate()'"
```

## 🛠 CLI Usage

### Basic Commands

```bash
# Update check without applying
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --check-only

# Forced update (bypasses "once daily" rule)
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --force

# Specific update sources
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --sources main_app config_repo

# Rollback to last backup
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --rollback /var/lib/ship/backups/backup_pre_update_1.2.3

# Manifest validation
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --test-manifest /path/to/update-manifest.yaml

# Check rollout eligibility
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --check-rollout /path/to/update-manifest.yaml
```

### Release Management

```bash
# Interactive release process
./release.sh interactive

# Create Git release
./release.sh git v1.2.3 "New features and bug fixes"

# Create HTTP release package
./release.sh http v1.2.3 "Hotfix for critical bug"

# SFTP upload
./release.sh sftp v1.2.3 "Emergency fix" deploy.server.com deployer /releases/

# Create manifest only
./release.sh manifest v1.2.3
```

## 🚨 Troubleshooting

### Common Issues

#### 1. Permission Errors

```bash
# Problem: Permission denied
# Solution: Check permissions
sudo chown -R ship:ship /var/lib/ship
sudo chmod +x /opt/ship/ship
sudo chmod 600 /etc/ship/ship.toml
```

#### 2. Git Authentication Failed

```bash
# Problem: Git fetch failed
# Solution: Check SSH keys
sudo -u ship ssh -T git@github.com
sudo -u ship git -C /opt/myapp fetch origin
```

#### 3. Service Won't Start After Update

```bash
# Problem: Service failed to start
# Solution: Automatic rollback should trigger
# Manual rollback if needed:
sudo systemctl start app-rollback.service

# Or specific backup:
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --rollback /var/lib/ship/backups/backup_pre_update_1.2.2
```

#### 4. Update Hangs / Timeout

```bash
# Problem: Update process hangs
# Solution: Kill process and rollback
sudo pkill -f "ship"
sudo systemctl start app-rollback.service

# Check logs:
sudo journalctl -u ship.service --since "1 hour ago"
```

#### 5. Disk Space Issues

```bash
# Problem: Insufficient disk space
# Solution: Clean old backups
sudo find /var/lib/ship/backups -type d -mtime +30 -exec rm -rf {} \;

# Rotate logs:
sudo logrotate -f /etc/logrotate.d/ship
```

### Debug Mode

```bash
# Enable detailed logging
# In /etc/ship/ship.toml:
[general.logging]
level = "DEBUG"

# Test individual components:
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --test-manifest update-manifest.yaml
sudo -u ship /opt/ship/venv/bin/python /opt/ship/ship --check-requirements update-manifest.yaml
```

### Monitoring

```bash
# System Health Check
#!/bin/bash
# /usr/local/bin/ship-healthcheck.sh

echo "=== Spdater Health Check ==="

# Timer Status
echo "Timer Status:"
systemctl is-active ship.timer

# Last Run
echo "Last successful run:"
if [ -f /var/lib/ship/.ship_state.json ]; then
    cat /var/lib/ship/.ship_state.json | jq -r '.last_run'
else
    echo "No state file found"
fi

# Disk Space
echo "Backup disk usage:"
du -sh /var/lib/ship/backups/

# Log Errors (last 24h)
echo "Errors in last 24h:"
journalctl -u ship.service --since "24 hours ago" | grep -i error | wc -l
```

## 🔒 Security

### Security Features

- **Minimal Permissions**: Runs as dedicated `ship` user without shell access
- **Systemd Security**: NoNewPrivileges, ProtectSystem, CapabilityBoundingSet
- **Checksum Verification**: SHA256 hashes for download integrity
- **File Type Validation**: Only allowed file types are processed
- **Size Limits**: Maximum file sizes configurable
- **Secure Temp**: PrivateTmp for temporary files
- **System Call Filtering**: Restricted syscalls via SystemCallFilter

### Recommended Security Configuration

```toml
# In ship.toml
[sources.main_app.security]
verify_checksums = true
allowed_file_types = [".py", ".toml", ".json", ".sql", ".md", ".txt", ".yaml"]
max_file_size_mb = 50

# Handle privileged files separately
privileged_files = ["scripts/system_config.py"]
```

### Network Security

```bash
# Firewall rules for Git over SSH
sudo ufw allow out 22 comment "Git SSH access"

# For HTTPS updates
sudo ufw allow out 443 comment "HTTPS updates"

# Block incoming connections (outgoing only)
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

## 🤝 Contributing

### Development Setup

```bash
git clone https://github.com/rtulke/ship.git
cd ship

# Development environment
python3 -m venv dev-env
source dev-env/bin/activate
pip install -r requirements.txt
pip install -r requirements-dev.txt

# Pre-commit hooks
pre-commit install

# Run tests
python -m pytest tests/
python -m pytest tests/ --cov=ship

# Linting
flake8 .
black .
isort .
```

### Testing

```bash
# Unit tests
python -m pytest tests/unit/

# Integration tests
python -m pytest tests/integration/

# End-to-end tests (requires Docker)
python -m pytest tests/e2e/

# Performance tests
python -m pytest tests/performance/
```

### Documentation

```bash
# Generate documentation
cd docs/
make html

# API documentation
pydoc -w ship
```

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Documentation**: [GitHub Wiki](https://github.com/rtulke/ship/wiki)
- **Issues**: [GitHub Issues](https://github.com/rtulke/ship/issues)
- **Discussions**: [GitHub Discussions](https://github.com/rtulke/ship/discussions)

---

**Built with ❤️ for robust, unattended application updates**
