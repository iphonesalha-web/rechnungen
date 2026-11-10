# حفظ الفواتير تلقائياً على الـ NAS (Raspberry Pi)

كل فاتورة / Gutschrift / Einkaufsbeleg جديدة تتحوّل إلى **PDF** وتُحفظ على الـ NAS كل 5 دقائق تقريباً:

```
NAS/Rechnungen/
  Rechnungen/2026/2026-11/Rechnung_10307_اسم.pdf
  Gutschriften/2026/2026-11/Gutschrift_1280_اسم.pdf
  Einkauf/2026/2026-11/Einkaufsbeleg_17_اسم.pdf
```

- إذا تغيّرت فاتورة (خلال 7 أيام) تُحفظ نسخة جديدة `_v2` ويبقى الأصل.
- يقرأ فقط (لا يغيّر شيئاً في البرنامج).
- لا يكتب إذا الـ NAS غير موصول (يمنع الكتابة على بطاقة الـ Pi بالغلط).

## 1) ربط الـ NAS بالـ Pi (SMB)
```bash
sudo apt install -y cifs-utils
sudo mkdir -p /mnt/nas
sudo nano /root/.nas-login          # سطران:  username=اسم_المستخدم  و  password=كلمة_السر
sudo chmod 600 /root/.nas-login
sudo nano /etc/fstab                # أضف السطر (غيّر العنوان والمجلد):
//192.168.178.50/Rechnungen  /mnt/nas  cifs  credentials=/root/.nas-login,uid=1000,gid=1000,vers=3.0,_netdev,nofail,x-systemd.automount  0  0
sudo mount -a && ls /mnt/nas
```

## 2) حساب خاص بالـ Pi (قراءة فقط)
في Firebase Console → Authentication → Add user: بريد وكلمة سر جديدين للـ Pi.
أي حساب غير حسابك يدخل كـ «Steuerberatung» (قراءة فقط)، وهذا المطلوب.

## 3) تنزيل السكربت
```bash
sudo apt install -y nodejs npm chromium
mkdir -p ~/pdf-sync && cd ~/pdf-sync
# انسخ الملفات الأربعة: pdf-sync.mjs, package.json, config.example.json, salha-pdf-sync.service
npm install
cp config.example.json config.json && nano config.json     # البريد وكلمة السر، والمجلد /mnt/nas/...
node pdf-sync.mjs --einmal        # تجربة مرة واحدة
```
في أول تشغيل يحفظ **كل** الفواتير القديمة. للبدء من تاريخ معيّن اكتب في config.json: `"abDatum": "2026-01-01"`.

## 4) التشغيل الدائم
```bash
sudo cp salha-pdf-sync.service /etc/systemd/system/
sudo systemctl daemon-reload && sudo systemctl enable --now salha-pdf-sync
journalctl -u salha-pdf-sync -f      # عرض السجل
```
