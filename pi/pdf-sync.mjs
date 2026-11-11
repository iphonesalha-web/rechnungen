// SALHA AUTOTEILE — automatischer PDF-Abgleich: Rechnungen, Gutschriften, Einkaufsbelege -> NAS
// Läuft dauerhaft auf dem Raspberry Pi. Öffnet die App (nur lesend), erzeugt je Beleg ein PDF
// und legt es in einem Ordner ab (der NAS-Ordner ist auf dem Pi eingebunden).
import { chromium } from "playwright-core";
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const HIER = path.dirname(fileURLToPath(import.meta.url));
const CFG = Object.assign({
  appUrl: "https://iphonesalha-web.github.io/rechnungen/",
  email: "", passwort: "",
  zielOrdner: "/mnt/nas/Rechnungen",      // eingebundener NAS-Ordner
  pruefeMount: true,                       // nur schreiben, wenn der NAS wirklich eingebunden ist
  intervallMinuten: 5,
  abDatum: "",                             // z. B. "2026-01-01" — leer = alles seit Beginn
  chromium: "",                            // leer = automatisch suchen
  statusDatei: path.join(HIER, "status.json"),
  profilOrdner: path.join(HIER, "profil"),
}, JSON.parse(fs.readFileSync(process.env.SYNC_CONFIG || path.join(HIER, "config.json"), "utf8")));

const log = (...a) => console.log(new Date().toISOString().replace("T", " ").slice(0, 19), ...a);
const sleep = ms => new Promise(r => setTimeout(r, ms));
const sauber = t => String(t || "").normalize("NFC").replace(/[\\/:*?"<>|\r\n\t]/g, " ").replace(/\s+/g, " ").trim().slice(0, 40).replace(/ /g, "_");
const ARTORDNER = { rechnung: "Rechnungen", gutschrift: "Gutschriften", einkauf: "Einkauf" };
const ARTNAME = { rechnung: "Rechnung", gutschrift: "Gutschrift", einkauf: "Einkaufsbeleg" };

function chromiumPfad() {
  if (CFG.chromium) return CFG.chromium;
  for (const p of ["/usr/bin/chromium", "/usr/bin/chromium-browser", "/snap/bin/chromium"]) if (fs.existsSync(p)) return p;
  throw new Error("Chromium nicht gefunden — 'sudo apt install chromium' ausführen oder 'chromium' in config.json setzen.");
}
function nasBereit() {
  if (!fs.existsSync(CFG.zielOrdner)) return false;
  if (!CFG.pruefeMount) return true;
  try { execFileSync("mountpoint", ["-q", CFG.mountPunkt || CFG.zielOrdner]); return true; }
  catch { // zielOrdner kann ein Unterordner sein: Elternordner prüfen
    let p = path.resolve(CFG.zielOrdner);
    while (p !== "/") { try { execFileSync("mountpoint", ["-q", p]); return true; } catch {} p = path.dirname(p); }
    return false;
  }
}
const statusLesen = () => { try { return JSON.parse(fs.readFileSync(CFG.statusDatei, "utf8")); } catch { return {}; } };
const statusSchreiben = s => { const t = CFG.statusDatei + ".tmp"; fs.writeFileSync(t, JSON.stringify(s, null, 1)); fs.renameSync(t, CFG.statusDatei); };

async function zyklus(ctx) {
  const page = await ctx.newPage();
  try {
    page.on("response", async r => {
      if (/accounts:signInWithPassword/.test(r.url())) {
        let t = ""; try { t = await r.text(); } catch {}
        let m = ""; try { m = JSON.parse(t).error.message; } catch {}
        log("Firebase-Antwort auf Anmeldung: HTTP " + r.status() + (m ? " — " + m : " — OK"));
      }
    });
    await page.goto(CFG.appUrl, { waitUntil: "load", timeout: 60000 });
    let z = "laedt";
    for (let i = 0; i < 90; i++) {
      z = await page.evaluate(() => window.SALHA_EXPORT ? window.SALHA_EXPORT.zustand() : "laedt").catch(() => "laedt");
      if (z === "login" && CFG.email) {
        await page.fill("#gMail", CFG.email); await page.fill("#gPass", CFG.passwort); await page.click("#gGo");
        for (let k = 0; k < 30; k++) {          // bis zu 30 s auf das Ergebnis warten
          await sleep(1000);
          const msg = await page.evaluate(() => (document.getElementById("gMsg") || {}).textContent || "");
          if (/fehlgeschlagen/i.test(msg)) throw new Error("Anmeldung fehlgeschlagen — E-Mail/Passwort falsch (oder Konto in Firebase nicht angelegt).");
          z = await page.evaluate(() => window.SALHA_EXPORT.zustand());
          if (z !== "login") break;
        }
        if (z === "login") throw new Error("Anmeldung dauert zu lange / nicht möglich.");
      }
      if (z === "bereit") break;
      await sleep(1000);
    }
    if (z !== "bereit") throw new Error("App nicht bereit (Zustand: " + z + ")");

    const liste = await page.evaluate(() => window.SALHA_EXPORT.liste());
    if (process.argv.includes("--pruefen")) {
      log("Anmeldung OK — " + liste.length + " Belege gefunden (Rechnungen, Gutschriften, Einkauf)");
      if (!nasBereit()) throw new Error("NAS-Ordner nicht erreichbar: " + CFG.zielOrdner);
      const t = path.join(CFG.zielOrdner, ".schreibtest"); fs.writeFileSync(t, "ok"); fs.unlinkSync(t);
      log("NAS-Ordner OK (Schreibtest erfolgreich): " + CFG.zielOrdner);
      return;
    }
    const st = statusLesen(); st.belege = st.belege || {};
    const neu = liste.filter(x => {
      if (CFG.abDatum && x.datum && x.datum < CFG.abDatum) return false;
      const alt = st.belege[x.art + "|" + x.prefix + x.nr];
      return !alt || alt.hash !== x.hash;
    });
    if (!neu.length) { log("nichts Neues (" + liste.length + " Belege geprüft)"); return; }
    if (!nasBereit()) { log("WARNUNG: NAS nicht eingebunden/erreichbar (" + CFG.zielOrdner + ") — " + neu.length + " Belege warten"); return; }

    let ok = 0;
    for (const x of neu) {
      const key = x.art + "|" + x.prefix + x.nr;
      const html = await page.evaluate(([a, n, p]) => window.SALHA_EXPORT.html(a, n, p), [x.art, x.nr, x.prefix]);
      if (!html) { log("übersprungen (leer):", key); continue; }
      await page.evaluate(h => { document.getElementById("out").innerHTML = h; }, html);
      await page.evaluate(() => document.fonts && document.fonts.ready);
      await page.evaluate(() => Promise.all([...document.images].map(i => i.complete ? 0 : new Promise(r => { i.onload = i.onerror = r; }))));
      const pdf = await page.pdf({ format: "A4", printBackground: true, preferCSSPageSize: true, margin: { top: 0, right: 0, bottom: 0, left: 0 } });
      const monat = (x.datum || "").slice(0, 7) || "ohne-Datum";
      const dir = path.join(CFG.zielOrdner, ARTORDNER[x.art], monat.slice(0, 4), monat);
      fs.mkdirSync(dir, { recursive: true });
      const alt = st.belege[key];
      const ver = alt ? alt.version + 1 : 1;     // geänderter Beleg: neue Datei, die alte bleibt erhalten (GoBD)
      const basis = (x.storno ? "Einkaufsbeleg-Storno" : ARTNAME[x.art]) + "_" + x.prefix + x.nr + (x.name ? "_" + sauber(x.name) : "");
      const datei = path.join(dir, basis + (ver > 1 ? "_v" + ver : "") + ".pdf");
      fs.writeFileSync(datei + ".tmp", pdf); fs.renameSync(datei + ".tmp", datei);
      st.belege[key] = { hash: x.hash, version: ver, datei: path.relative(CFG.zielOrdner, datei), zeit: new Date().toISOString() };
      statusSchreiben(st); ok++;
      log("gespeichert:", path.relative(CFG.zielOrdner, datei));
    }
    log(ok + " PDF(s) auf dem NAS abgelegt");
  } finally { await page.close().catch(() => {}); }
}

(async () => {
  const einmal = process.argv.includes("--einmal") || process.argv.includes("--pruefen");
  log("Start — Ziel:", CFG.zielOrdner, "| alle", CFG.intervallMinuten, "Min.");
  fs.mkdirSync(CFG.profilOrdner, { recursive: true });
  while (true) {
    let ctx;
    try {
      ctx = await chromium.launchPersistentContext(CFG.profilOrdner, {
        executablePath: chromiumPfad(), headless: true, args: ["--no-sandbox", "--disable-gpu", "--disable-dev-shm-usage"],
      });
      await zyklus(ctx);
    } catch (e) { log("FEHLER:", e.message || e); if (process.argv.includes("--pruefen")) process.exitCode = 1; }
    finally { if (ctx) await ctx.close().catch(() => {}); }
    if (einmal) break;
    await sleep(CFG.intervallMinuten * 60000);
  }
})();
