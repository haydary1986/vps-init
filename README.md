# vps-init

معالج (wizard) تفاعلي لتهيئة سيرفر VPS جديد على **Ubuntu 22.04 / 24.04** بأمر واحد:
تفعيل دخول **SSH بكلمة المرور** + دخول **root** + تعيين **كلمة مرور** + تغيير **منفذ SSH** + تثبيت **fail2ban**.

---

## ⚡ التشغيل السريع — انسخ والصق

### ✅ السيناريو الافتراضي (curl مثبّت)

```bash
curl -fsSL https://raw.githubusercontent.com/haydary1986/vps-init/main/setup.sh -o /tmp/vps-init.sh && bash /tmp/vps-init.sh
```

> أنت `root` أصلًا؟ هذا كافٍ. غير ذلك ضع `sudo` قبل `bash`.

### 🧰 حاوية دنيا بدون curl (LXC / Proxmox)

```bash
apt update && apt install -y curl
curl -fsSL https://raw.githubusercontent.com/haydary1986/vps-init/main/setup.sh -o /tmp/vps-init.sh && bash /tmp/vps-init.sh
```

### 🌐 بديل عبر wget (دون تثبيت أي شيء)

```bash
wget -qO- https://raw.githubusercontent.com/haydary1986/vps-init/main/setup.sh | bash
```

السكربت يقرأ مدخلاته من `/dev/tty`، لذا تعمل أسئلة الـ wizard بشكل صحيح حتى عبر الأنبوب، ويثبّت `openssh-server` تلقائيًا إن لم يكن موجودًا.

---

## 🔌 الاتصال بعد تغيير منفذ SSH

```bash
ssh -p PORT user@server-ip
# مثال:
ssh -p 2222 root@91.109.114.90
```

نقل ملف على منفذ مخصّص (لاحظ `-P` كبيرة في scp):

```bash
scp -P 2222 file.txt root@91.109.114.90:/root/
```

اختصار دائم في `~/.ssh/config` على جهازك:

```sshconfig
Host myvps
    HostName 91.109.114.90
    User root
    Port 2222
```

ثم تتصل بـ: `ssh myvps`

---

## ماذا يفعل المعالج (5 خطوات)

1. **مصادقة SSH** — تفعيل الدخول بكلمة المرور + السماح بدخول root.
2. **كلمة المرور** — تعيين/تغيير كلمة مرور حساب (يُنشئ المستخدم إن لم يوجد).
3. **منفذ SSH** — تغيير اختياري (يدعم `ssh.socket` في أوبنتو 24 + يفتح المنفذ في `ufw`).
4. **fail2ban** — تثبيت وضبط (maxretry / bantime / findtime + IP مستثنى + حظر تصاعدي).
5. **مراجعة** — يعرض ملخصًا ويطلب تأكيدًا قبل أي تعديل.

كل مخرجات السكربت بالإنجليزية لتفادي انعكاس النص العربي (RTL) في الطرفيات.

## ضمانات السلامة

- يعطّل توجيهات `cloud-init` المتعارضة ويكتب ملفًا معتمدًا `00-vps-init.conf` (يُقرأ أولًا فتفوز قيمته) — أكثر سبب فشل شائع على أوبنتو.
- **نسخة احتياطية** من `sshd_config` + تحقّق `sshd -t` **قبل** إعادة التشغيل (يمنع قفل نفسك خارج الخادم).
- يعرض في النهاية القيم الفعلية من `sshd -T` وحالة `fail2ban`.
- **لا تُغلق جلستك الحالية** قبل اختبار الدخول من نافذة جديدة.

## ⚠️ تنبيه أمني

فتح دخول root بكلمة المرور يجعل الخادم هدفًا لهجمات brute-force:

- استخدم كلمة مرور قوية جدًا.
- أبقِ **fail2ban** مفعّلًا (افتراضي في المعالج).
- الأفضل لاحقًا: التحوّل إلى مفاتيح SSH وإعادة تعطيل الدخول بكلمة المرور.

## الترخيص

MIT
