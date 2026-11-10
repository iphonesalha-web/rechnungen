#!/bin/bash
# SALHA AUTOTEILE — Einrichtung PDF-Abgleich auf dem Raspberry Pi (fragt alles Nötige ab)
set -e
RAW="https://raw.githubusercontent.com/iphonesalha-web/rechnungen/main/pi"
DIR="$HOME/pdf-sync"
ask(){ local v; read -r -p "$1 " v </dev/tty; echo "$v"; }
asks(){ local v; read -r -s -p "$1 " v </dev/tty; echo >&2; echo "$v"; }

echo "=== 1/5  Programme installieren (dauert ein paar Minuten) ==="
sudo apt-get update -qq
sudo apt-get install -y -qq nodejs npm cifs-utils curl
sudo apt-get install -y -qq chromium || sudo apt-get install -y -qq chromium-browser

echo "=== 2/5  Skript herunterladen ==="
mkdir -p "$DIR"; cd "$DIR"
curl -fsSL "$RAW/pdf-sync.mjs" -o pdf-sync.mjs
curl -fsSL "$RAW/package.json" -o package.json
npm install --silent --no-audit --no-fund

echo "=== 3/5  NAS verbinden ==="
NHOST=$(ask "NAS-Adresse (z.B. 192.168.178.50 oder fritz.nas):")
NSHARE=$(ask "Name des freigegebenen Ordners (Share):")
NUSER=$(ask "NAS-Benutzername:")
NPASS=$(asks "NAS-Passwort (wird nicht angezeigt):")
printf 'username=%s\npassword=%s\n' "$NUSER" "$NPASS" | sudo tee /root/.nas-login >/dev/null
sudo chmod 600 /root/.nas-login
sudo mkdir -p /mnt/nas
sudo umount /mnt/nas 2>/dev/null || true
OK=""
for V in 3.0 2.1 2.0; do
  if sudo mount -t cifs "//$NHOST/$NSHARE" /mnt/nas -o "credentials=/root/.nas-login,uid=$(id -u),gid=$(id -g),vers=$V,iocharset=utf8" 2>/dev/null; then OK=$V; break; fi
done
[ -n "$OK" ] || { echo "FEHLER: NAS konnte nicht verbunden werden. Adresse, Ordnername, Benutzer und Passwort prüfen."; exit 1; }
echo "NAS verbunden (SMB $OK)"
sudo umount /mnt/nas
sudo sed -i '\# /mnt/nas #d' /etc/fstab
echo "//$NHOST/$NSHARE /mnt/nas cifs credentials=/root/.nas-login,uid=$(id -u),gid=$(id -g),vers=$OK,iocharset=utf8,_netdev,nofail,x-systemd.automount,x-systemd.mount-timeout=30 0 0" | sudo tee -a /etc/fstab >/dev/null
sudo systemctl daemon-reload
sudo mount /mnt/nas 2>/dev/null || ls /mnt/nas >/dev/null
mkdir -p /mnt/nas/Salha-Rechnungen

echo "=== 4/5  Zugang zur Rechnungs-App ==="
FMAIL=$(ask "E-Mail des Pi-Kontos (Firebase):")
FPASS=$(asks "Passwort des Pi-Kontos (wird nicht angezeigt):")
node -e 'const fs=require("fs");fs.writeFileSync("config.json",JSON.stringify({email:process.argv[1],passwort:process.argv[2],zielOrdner:"/mnt/nas/Salha-Rechnungen",intervallMinuten:5,abDatum:""},null,2))' "$FMAIL" "$FPASS"
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
echo "FERTIG ✓  Die PDFs erscheinen in: $NSHARE/Salha-Rechnungen (beim ersten Mal werden alle alten Belege abgelegt — das dauert)."
echo "Verlauf ansehen:  journalctl -u salha-pdf-sync -n 30 --no-pager"
