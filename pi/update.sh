#!/bin/bash
# Skript auf dem Pi aktualisieren (Zugangsdaten bleiben). Mit "neu": alle automatisch erzeugten PDFs löschen und frisch erzeugen.
DIR="$HOME/pdf-sync"; cd "$DIR" || { echo "Ordner $DIR fehlt"; exit 1; }
sudo systemctl stop salha-pdf-sync
curl -fsSL "https://raw.githubusercontent.com/iphonesalha-web/rechnungen/main/pi/pdf-sync.mjs?v=$(date +%s)" -o pdf-sync.mjs
if [ "$1" = "neu" ]; then
  ZIEL=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("config.json","utf8")).zielOrdner)')
  echo "Das löscht ALLE Dateien in: $ZIEL"
  echo "(nur die automatisch erzeugten PDFs; andere Ordner in HDD/Rechnung bleiben)"
  read -r -p "Wirklich löschen und neu erzeugen? (ja/nein) " A </dev/tty
  if [ "$A" = "ja" ]; then
    case "$ZIEL" in */Automatisch) rm -rf "$ZIEL"/* ; rm -f status.json; echo "Gelöscht.";; *) echo "Sicherheitsabbruch: Zielordner endet nicht auf /Automatisch"; exit 1;; esac
  else echo "Abgebrochen."; sudo systemctl start salha-pdf-sync; exit 0; fi
fi
sudo systemctl start salha-pdf-sync
echo "FERTIG ✓  Verlauf: journalctl -u salha-pdf-sync -n 15 --no-pager"
