#!/bin/bash
# Zugangsdaten (Firebase-Konto des Pi) neu eingeben, testen und Dienst neu starten
DIR="$HOME/pdf-sync"; cd "$DIR" || { echo "Ordner $DIR fehlt — zuerst install.sh ausführen"; exit 1; }
curl -fsSL https://raw.githubusercontent.com/iphonesalha-web/rechnungen/main/pi/pdf-sync.mjs -o pdf-sync.mjs
read -t 0.3 -n 10000 -s _x </dev/tty 2>/dev/null || true   # alte Eingaben verwerfen
FMAIL=""; while [ -z "$FMAIL" ]; do read -r -p "E-Mail des Pi-Kontos (Firebase): " FMAIL </dev/tty; FMAIL=$(echo "$FMAIL" | tr -d ' '); done
FPASS=""; while [ -z "$FPASS" ]; do read -r -s -p "Passwort (wird nicht angezeigt): " FPASS </dev/tty; echo; done
echo "Eingegeben: E-Mail = $FMAIL"
echo "Passwort: ${#FPASS} Zeichen, erstes Zeichen '${FPASS:0:1}', letztes Zeichen '${FPASS: -1}'"
echo "Direkter Test bei Firebase …"
node -e '
const key="AIzaSyARdbGg5dHaXKZJP-GMjRbkSSBbR-hWd_Q";
fetch("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="+key,{method:"POST",headers:{"Content-Type":"application/json"},
 body:JSON.stringify({email:process.argv[1],password:process.argv[2],returnSecureToken:true})})
 .then(r=>r.json()).then(j=>console.log(j.error?("-> ABGELEHNT: "+j.error.message):"-> Firebase akzeptiert die Zugangsdaten (OK)"))
 .catch(e=>console.log("-> Netzwerkfehler: "+e.message));' "$FMAIL" "$FPASS"
node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync("config.json","utf8"));c.email=process.argv[1];c.passwort=process.argv[2];fs.writeFileSync("config.json",JSON.stringify(c,null,2))' "$FMAIL" "$FPASS"
chmod 600 config.json
echo "Teste Anmeldung …"
if node pdf-sync.mjs --pruefen; then
  sudo systemctl restart salha-pdf-sync
  echo; echo "FERTIG ✓ Der Dienst läuft. Verlauf: journalctl -u salha-pdf-sync -n 30 --no-pager"
else
  echo; echo "NICHT OK — E-Mail/Passwort prüfen und den Befehl nochmal ausführen."
fi
