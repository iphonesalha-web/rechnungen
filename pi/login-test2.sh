#!/bin/bash
# Diagnose: zeigt am ENDE, was genau eingegeben wurde, und testet direkt bei Firebase
read -t 0.3 -n 10000 -s _x </dev/tty 2>/dev/null || true
FMAIL=""; while [ -z "$FMAIL" ]; do read -r -p "E-Mail: " FMAIL </dev/tty; FMAIL=$(echo "$FMAIL" | tr -d ' \r'); done
FPASS=""; while [ -z "$FPASS" ]; do read -r -s -p "Passwort (unsichtbar): " FPASS </dev/tty; echo; done
FPASS=${FPASS%$'\r'}
ERG=$(FM="$FMAIL" FP="$FPASS" node -e '
const key="AIzaSyARdbGg5dHaXKZJP-GMjRbkSSBbR-hWd_Q";
fetch("https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key="+key,{method:"POST",headers:{"Content-Type":"application/json"},
 body:JSON.stringify({email:process.env.FM,password:process.env.FP,returnSecureToken:true})})
 .then(r=>r.json()).then(j=>console.log(j.error?("ABGELEHNT: "+j.error.message):"OK: Firebase akzeptiert die Zugangsdaten"))
 .catch(e=>console.log("Netzwerkfehler: "+e.message));')
echo
echo "================ ERGEBNIS ================"
echo "E-Mail:    [$FMAIL]  (${#FMAIL} Zeichen)"
echo "Passwort:  ${#FPASS} Zeichen | erstes '${FPASS:0:1}' | zweites '${FPASS:1:1}' | letztes '${FPASS: -1}'"
echo "Firebase:  $ERG"
if [[ "$ERG" == OK* ]]; then
  cd "$HOME/pdf-sync" && node -e 'const fs=require("fs");const c=JSON.parse(fs.readFileSync("config.json","utf8"));c.email=process.env.FM;c.passwort=process.env.FP;fs.writeFileSync("config.json",JSON.stringify(c,null,2))' 2>/dev/null
  FM="$FMAIL" FP="$FPASS" node -e 'const fs=require("fs");const p=process.env.HOME+"/pdf-sync/config.json";const c=JSON.parse(fs.readFileSync(p,"utf8"));c.email=process.env.FM;c.passwort=process.env.FP;fs.writeFileSync(p,JSON.stringify(c,null,2))'
  chmod 600 "$HOME/pdf-sync/config.json"
  sudo systemctl restart salha-pdf-sync && echo "Zugangsdaten gespeichert, Dienst neu gestartet ✓"
fi
