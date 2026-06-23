#!/usr/bin/env bash
#
# vps-init.sh — معالج إعداد VPS جديد (Ubuntu 22.04 / 24.04)
# ------------------------------------------------------------
#  • تفعيل الدخول عبر SSH بكلمة المرور (مع تجاوز إعدادات cloud-init)
#  • السماح بدخول root (اختياري)
#  • تعيين/تغيير كلمة مرور حساب
#  • تغيير منفذ SSH (يدعم socket activation في أوبنتو 24)
#  • تثبيت وضبط fail2ban لحماية SSH من هجمات brute-force
#
# الاستخدام:
#   curl -fsSL https://raw.githubusercontent.com/haydary1986/vps-init/main/setup.sh | sudo bash
#   sudo bash <(curl -fsSL https://raw.githubusercontent.com/haydary1986/vps-init/main/setup.sh)
#
set -euo pipefail

# ─────────────────────────── الألوان ───────────────────────────
if [ -t 1 ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  BOLD=""; DIM=""; RED=""; GRN=""; YLW=""; CYN=""; RST=""
fi
info() { printf "%s\n" "${CYN}➜${RST} $*"; }
ok()   { printf "%s\n" "${GRN}✔${RST} $*"; }
warn() { printf "%s\n" "${YLW}⚠${RST} $*"; }
err()  { printf "%s\n" "${RED}✗${RST} $*" >&2; }
hr()   { printf "%s\n" "${DIM}──────────────────────────────────────────────${RST}"; }

# ─────────────────────────── التحقق من root ───────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  err "هذا السكربت يحتاج صلاحيات root."
  err "أعد التشغيل هكذا:  curl -fsSL <URL> | sudo bash"
  exit 1
fi

# ─────────────────────────── الإدخال التفاعلي من الطرفية ───────────────────────────
# عند الاستدعاء عبر (curl | bash) يكون stdin مشغولًا بالسكربت نفسه،
# لذلك نقرأ المدخلات من /dev/tty مباشرةً.
if [ -r /dev/tty ]; then
  INTERACTIVE=1
else
  INTERACTIVE=0
  warn "لا توجد طرفية تفاعلية — سيتم اعتماد القيم الافتراضية تلقائيًا."
fi

ask() {  # ask "السؤال" "الافتراضي"  ← يطبع الإجابة
  local prompt="$1" def="${2:-}" ans=""
  if [ "$INTERACTIVE" -eq 1 ]; then
    if [ -n "$def" ]; then printf "%s" "${BOLD}${prompt}${RST} [${def}]: " > /dev/tty
    else                   printf "%s" "${BOLD}${prompt}${RST}: " > /dev/tty; fi
    read -r ans < /dev/tty || ans=""
  fi
  printf "%s" "${ans:-$def}"
}

ask_yn() {  # ask_yn "السؤال" "Y|N"  ← 0=نعم 1=لا
  local prompt="$1" def="${2:-Y}" ans="" hint="[Y/n]"
  [ "$def" = "N" ] && hint="[y/N]"
  if [ "$INTERACTIVE" -eq 1 ]; then
    printf "%s" "${BOLD}${prompt}${RST} ${hint}: " > /dev/tty
    read -r ans < /dev/tty || ans=""
  fi
  ans="${ans:-$def}"
  case "$ans" in [Yy]|[Yy][Ee][Ss]|نعم) return 0 ;; *) return 1 ;; esac
}

ask_pw() {  # ask_pw "النص"  ← يطبع كلمة المرور (إدخال صامت)
  local prompt="$1" pw=""
  printf "%s" "${BOLD}${prompt}${RST}: " > /dev/tty
  read -rs pw < /dev/tty || pw=""
  printf "\n" > /dev/tty
  printf "%s" "$pw"
}

# ─────────────────────────── البانر ───────────────────────────
hr
printf "%s\n" "${BOLD}   🚀  معالج إعداد VPS  —  SSH + fail2ban${RST}"
hr

# كشف نظام التشغيل
OS_NAME="غير معروف"; OS_VER=""
if [ -r /etc/os-release ]; then . /etc/os-release; OS_NAME="${ID:-?}"; OS_VER="${VERSION_ID:-?}"; fi
info "النظام المكتشف: ${BOLD}${OS_NAME} ${OS_VER}${RST}"
if [ "$OS_NAME" != "ubuntu" ] && [ "$OS_NAME" != "debian" ]; then
  warn "هذا السكربت مُحسّن لأوبنتو/دبيان. المتابعة على مسؤوليتك."
fi
CUR_PORT="$(grep -RhiE '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/ 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
CUR_PORT="${CUR_PORT:-22}"
echo

# ─────────────────────────── جمع الخيارات (Wizard) ───────────────────────────
info "${BOLD}الخطوة 1/5 — مصادقة SSH${RST}"
if ask_yn "تفعيل الدخول بكلمة المرور (PasswordAuthentication)؟" "Y"; then PW_AUTH="yes"; else PW_AUTH="no"; fi
if ask_yn "السماح بدخول root عبر SSH (PermitRootLogin)؟" "Y";  then ROOT_LOGIN="yes"; else ROOT_LOGIN="no"; fi
echo

info "${BOLD}الخطوة 2/5 — كلمة المرور${RST}"
SET_PW=0; PW_USER=""
if [ "$INTERACTIVE" -eq 1 ] && ask_yn "هل تريد تعيين/تغيير كلمة مرور حساب الآن؟" "Y"; then
  PW_USER="$(ask "اسم المستخدم" "root")"
  SET_PW=1
fi
echo

info "${BOLD}الخطوة 3/5 — منفذ SSH${RST}"
SSH_PORT="$CUR_PORT"
if ask_yn "تغيير منفذ SSH (الحالي: ${CUR_PORT})؟" "N"; then
  SSH_PORT="$(ask "المنفذ الجديد" "2222")"
fi
echo

info "${BOLD}الخطوة 4/5 — fail2ban${RST}"
INSTALL_F2B=0; F2B_MAXRETRY="5"; F2B_BANTIME="1h"; F2B_FINDTIME="10m"; F2B_IGNOREIP=""
if ask_yn "تثبيت وضبط fail2ban لحماية SSH؟" "Y"; then
  INSTALL_F2B=1
  if [ "$INTERACTIVE" -eq 1 ]; then
    F2B_MAXRETRY="$(ask "عدد المحاولات الفاشلة قبل الحظر (maxretry)" "5")"
    F2B_BANTIME="$(ask  "مدة الحظر (bantime، مثل 1h / 1d / -1 دائم)" "1h")"
    F2B_FINDTIME="$(ask "نافذة العدّ (findtime)" "10m")"
    F2B_IGNOREIP="$(ask "IP موثوق لاستثنائه من الحظر (اختياري، فراغ=لا شيء)" "")"
  fi
fi
echo

info "${BOLD}الخطوة 5/5 — مراجعة${RST}"
hr
printf "  %-28s %s\n" "الدخول بكلمة المرور:" "$PW_AUTH"
printf "  %-28s %s\n" "دخول root:"          "$ROOT_LOGIN"
printf "  %-28s %s\n" "منفذ SSH:"           "$SSH_PORT"
if [ "$SET_PW" -eq 1 ]; then printf "  %-28s %s\n" "تعيين كلمة مرور لـ:" "$PW_USER"; fi
if [ "$INSTALL_F2B" -eq 1 ]; then
  printf "  %-28s %s\n" "fail2ban:" "نعم (maxretry=$F2B_MAXRETRY, bantime=$F2B_BANTIME, findtime=$F2B_FINDTIME)"
  [ -n "$F2B_IGNOREIP" ] && printf "  %-28s %s\n" "IP مستثنى:" "$F2B_IGNOREIP"
else
  printf "  %-28s %s\n" "fail2ban:" "لا"
fi
hr
if ! ask_yn "تطبيق الإعدادات أعلاه؟" "Y"; then err "أُلغيت العملية. لم تُغيَّر أي إعدادات."; exit 0; fi
echo

# ═══════════════════════════ التطبيق ═══════════════════════════
SSHD_MAIN="/etc/ssh/sshd_config"
DROPIN_DIR="/etc/ssh/sshd_config.d"
OURFILE="${DROPIN_DIR}/00-vps-init.conf"
STAMP="$(date +%Y%m%d-%H%M%S)"

# تأكد من وجود openssh-server (الحاويات الدنيا — LXC/Proxmox — قد لا تحتويه)
if ! command -v sshd >/dev/null 2>&1; then
  warn "openssh-server غير مثبّت — يجري تثبيته..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || warn "فشل apt-get update — المتابعة."
  apt-get install -y -qq openssh-server
  systemctl enable ssh >/dev/null 2>&1 || true
fi

# نسخة احتياطية (إن وُجد الملف)
[ -f "$SSHD_MAIN" ] && { cp -a "$SSHD_MAIN" "${SSHD_MAIN}.vps-init.bak.${STAMP}"; info "نسخة احتياطية: ${SSHD_MAIN}.vps-init.bak.${STAMP}"; }

# تعطيل أي توجيهات متعارضة في الملف الرئيسي وملفات cloud-init (السبب الأول للفشل)
KEYS="PasswordAuthentication PermitRootLogin KbdInteractiveAuthentication ChallengeResponseAuthentication"
neutralize() {  # يعلّق التوجيهات الفعّالة في ملف
  local f="$1" k
  for k in $KEYS; do
    sed -i -E "s/^([[:space:]]*)(${k}[[:space:]])/\1# [vps-init] \2/I" "$f" 2>/dev/null || true
  done
}
neutralize "$SSHD_MAIN"
mkdir -p "$DROPIN_DIR"
shopt -s nullglob
for f in "$DROPIN_DIR"/*.conf; do
  [ "$f" = "$OURFILE" ] && continue
  neutralize "$f"
done
shopt -u nullglob

# كتابة ملف الإعدادات المعتمد (يُقرأ أولًا → قيمته هي الفائزة)
{
  echo "# Managed by vps-init.sh — ${STAMP}"
  echo "PasswordAuthentication ${PW_AUTH}"
  echo "PermitRootLogin ${ROOT_LOGIN}"
  echo "KbdInteractiveAuthentication no"
  echo "UsePAM yes"
  echo "Port ${SSH_PORT}"
} > "$OURFILE"
chmod 644 "$OURFILE"
ok "كُتبت إعدادات SSH في ${OURFILE}"

# منفذ SSH عبر socket activation (أوبنتو 22.10+/24.04: المنفذ في ssh.socket لا في sshd_config)
if [ "$SSH_PORT" != "22" ] && systemctl cat ssh.socket >/dev/null 2>&1; then
  mkdir -p /etc/systemd/system/ssh.socket.d
  {
    echo "[Socket]"
    echo "ListenStream="
    echo "ListenStream=${SSH_PORT}"
  } > /etc/systemd/system/ssh.socket.d/override.conf
  ok "ضُبط المنفذ ${SSH_PORT} عبر ssh.socket."
fi

# فتح المنفذ في الجدار الناري (إن كان ufw مفعّلًا)
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "${SSH_PORT}/tcp" >/dev/null 2>&1 || true
  ok "فُتح المنفذ ${SSH_PORT}/tcp في ufw."
fi

# التحقق من صحة الإعداد قبل إعادة التشغيل (يمنع قفل نفسك خارج الخادم)
if ! sshd -t; then
  err "فشل التحقق من إعداد SSH — لم تُعد الخدمة التشغيل. تُرك ملف النسخة الاحتياطية كما هو."
  exit 1
fi
ok "اجتاز sshd -t التحقق."

# إعادة التشغيل (مع مراعاة socket activation)
systemctl daemon-reload
systemctl restart ssh.socket 2>/dev/null || true
systemctl restart ssh 2>/dev/null || systemctl restart sshd 2>/dev/null || true
ok "أُعيد تشغيل خدمة SSH."

# تعيين كلمة المرور
if [ "$SET_PW" -eq 1 ] && [ -n "$PW_USER" ]; then
  if ! id "$PW_USER" >/dev/null 2>&1; then
    warn "المستخدم '$PW_USER' غير موجود — سيُنشأ."
    useradd -m -s /bin/bash "$PW_USER"
  fi
  while :; do
    P1="$(ask_pw "كلمة المرور لـ ${PW_USER}")"
    P2="$(ask_pw "أعد إدخال كلمة المرور")"
    [ -z "$P1" ] && { warn "كلمة المرور فارغة، أعد المحاولة."; continue; }
    [ "$P1" != "$P2" ] && { warn "غير متطابقة، أعد المحاولة."; continue; }
    break
  done
  echo "${PW_USER}:${P1}" | chpasswd && ok "عُيّنت كلمة المرور لـ ${PW_USER}." || err "تعذّر تعيين كلمة المرور."
  unset P1 P2
fi

# تثبيت وضبط fail2ban
if [ "$INSTALL_F2B" -eq 1 ]; then
  info "تثبيت fail2ban..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || warn "فشل apt-get update — المتابعة بالحزم المخزّنة."
  apt-get install -y -qq fail2ban
  IGNORE_LINE="ignoreip = 127.0.0.1/8 ::1"
  [ -n "$F2B_IGNOREIP" ] && IGNORE_LINE="ignoreip = 127.0.0.1/8 ::1 ${F2B_IGNOREIP}"
  cat > /etc/fail2ban/jail.local <<EOF
# Managed by vps-init.sh — ${STAMP}
[DEFAULT]
backend          = systemd
${IGNORE_LINE}
bantime          = ${F2B_BANTIME}
findtime         = ${F2B_FINDTIME}
maxretry         = ${F2B_MAXRETRY}
bantime.increment = true

[sshd]
enabled = true
port    = ${SSH_PORT}
EOF
  systemctl enable fail2ban >/dev/null 2>&1 || true
  systemctl restart fail2ban
  sleep 1
  ok "ثُبّت fail2ban وفُعّل."
fi

# ═══════════════════════════ الملخص النهائي ═══════════════════════════
echo
hr
printf "%s\n" "${BOLD}   ✅  اكتمل الإعداد${RST}"
hr
info "الإعدادات الفعّالة لـ SSH:"
sshd -T 2>/dev/null | grep -Ei "^(passwordauthentication|permitrootlogin|port|kbdinteractiveauthentication) " | sed 's/^/    /' || true
if [ "$INSTALL_F2B" -eq 1 ]; then
  echo
  info "حالة fail2ban (sshd):"
  fail2ban-client status sshd 2>/dev/null | sed 's/^/    /' || warn "تعذّر قراءة حالة fail2ban."
fi
echo
warn "${BOLD}مهم:${RST} لا تُغلق جلستك الحالية قبل اختبار الدخول من نافذة جديدة."
if [ "$SSH_PORT" != "22" ]; then
  warn "تغيّر المنفذ — اتصل الآن عبر:  ssh -p ${SSH_PORT} المستخدم@عنوان-الخادم"
fi
hr
