#!/bin/bash
# Zugangsdaten (Firebase-Konto des Pi) neu eingeben, testen und Dienst neu starten
DIR="$HOME/pdf-sync"; cd "$DIR" || { echo "Ordner $DIR fehlt — zuerst install.sh ausführen"; exit 1; }
curl -fsSL https://raw.githubusercontent.com/iphonesalha-web/rechnungen/main/pi/pdf-sync.mjs -o pdf-sync.mjs
read -r -p "E-Mail des Pi-Kontos (Firebase): " FMAIL </dev/tty
read -r -s -p "Passwort (wird nicht angezeigt): " FPASS </dev/tty; echo
node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync("config.json","utf8"));c.email=process.argv[1];c.passwort=process.argv[2];fs.writeFileSync("config.json",JSON.stringify(c,null,2))' "$FMAIL" "$FPASS"
chmod 600 config.json
echo "Teste Anmeldung …"
if node pdf-sync.mjs --pruefen; then
  sudo systemctl restart salha-pdf-sync
  echo; echo "FERTIG ✓ Der Dienst läuft. Verlauf: journalctl -u salha-pdf-sync -n 30 --no-pager"
else
  echo; echo "NICHT OK — E-Mail/Passwort prüfen und den Befehl nochmal ausführen."
fi
