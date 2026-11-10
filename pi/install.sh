#!/bin/bash
# SALHA AUTOTEILE — Einrichtung PDF-Abgleich auf dem Raspberry Pi (fragt alles Nötige ab)
set -e
RAW="https://raw.githubusercontent.com/iphonesalha-web/rechnungen/main/pi"
DIR="$HOME/pdf-sync"
ask(){ local v; read -r -p "$1 " v </dev/tty; echo "$v"; }
asks(){ local v; read -r -s -p "$1 " v </dev/tty; echo >&2; echo "$v"; }

echo "=== 1/5  Programme installieren (dauert ein paar Minuten) ==="
sudo apt-get update -qq
sudo apt-get install -y -qq nodejs npm curl
sudo apt-get install -y -qq chromium || sudo apt-get install -y -qq chromium-browser

echo "=== 2/5  Skript herunterladen ==="
mkdir -p "$DIR"; cd "$DIR"
curl -fsSL "$RAW/pdf-sync.mjs" -o pdf-sync.mjs
curl -fsSL "$RAW/package.json" -o package.json
npm install --silent --no-audit --no-fund

echo "=== 3/5  Speicherort prüfen ==="
ZIEL="$HOME/HDD/Rechnung/Automatisch"
[ -d "$HOME/HDD" ] || { echo "FEHLER: Ordner $HOME/HDD nicht gefunden (Festplatte nicht eingebunden?)."; exit 1; }
mkdir -p "$ZIEL"
if mountpoint -q "$HOME/HDD"; then PM=true; else PM=false; fi
echo "Die PDFs werden gespeichert in: $ZIEL"

echo "=== 4/5  Zugang zur Rechnungs-App ==="
FMAIL=$(ask "E-Mail des Pi-Kontos (Firebase):")
FPASS=$(asks "Passwort des Pi-Kontos (wird nicht angezeigt):")
node -e 'const fs=require("fs");fs.writeFileSync("config.json",JSON.stringify({email:process.argv[1],passwort:process.argv[2],zielOrdner:process.argv[3],pruefeMount:process.argv[4]==="true",mountPunkt:process.argv[5],intervallMinuten:5,abDatum:""},null,2))' "$FMAIL" "$FPASS" "$ZIEL" "$PM" "$HOME/HDD"
chmod 600 config.json
echo "Teste Anmeldung und NAS …"
node pdf-sync.mjs --pruefen

echo "=== 5/5  Dauerbetrieb einrichten ==="
sudo tee /etc/systemd/system/salha-pdf-sync.service >/dev/null <<EOF
[Unit]
Description=SALHA Rechnungen -> NAS (PDF-Abgleich)
After=network-online.target
Wants=network-online.target
[Service]
User=$(id -un)
WorkingDirectory=$DIR
ExecStart=$(command -v node) $DIR/pdf-sync.mjs
Restart=always
RestartSec=30
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now salha-pdf-sync
echo
echo "FERTIG ✓  Die PDFs erscheinen in: HDD/Rechnung/Automatisch (beim ersten Mal werden alle alten Belege abgelegt — das dauert)."
echo "Verlauf ansehen:  journalctl -u salha-pdf-sync -n 30 --no-pager"
