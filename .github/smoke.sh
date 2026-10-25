#!/bin/sh
# Drives the installed WizigApp on a booted emulator: taps every calculator
# button and fails with logs if the process dies. POSIX sh (the Android
# emulator runner does not give us bash).
set -u

cd "$(dirname "$0")/.." || exit 2

APK=$(ls android/app/build/outputs/apk/debug/*.apk 2>/dev/null | head -n1)
if [ -z "$APK" ]; then
    echo "no debug APK found"
    exit 2
fi
echo "APK: $APK"

pid_of_app() {
    adb shell pidof dev.wizig.wizigapp 2>/dev/null | tr -d '\r'
}

collect() {
    adb logcat -d > logcat-full.txt 2>/dev/null || true
    adb logcat -b crash -d > crash.txt 2>/dev/null || true
}

adb logcat -c 2>/dev/null || true
adb install -r "$APK" || {
    echo "INSTALL FAILED"
    collect
    exit 1
}

adb shell am start -W -n dev.wizig.wizigapp/.MainActivity
sleep 6

PID=$(pid_of_app)
echo "pid after launch: ${PID:-<dead>}"
if [ -z "$PID" ]; then
    echo "APP CRASHED AT LAUNCH"
    collect
    exit 1
fi

adb shell uiautomator dump /sdcard/ui.xml >/dev/null 2>&1 || true
adb pull /sdcard/ui.xml ui.xml >/dev/null 2>&1 || true

if [ ! -s ui.xml ]; then
    echo "uiautomator dump unavailable; dumping window hierarchy instead"
    adb shell dumpsys window windows > window.txt 2>/dev/null || true
fi

python3 - <<'PY' > targets.txt 2>&1
import re
import xml.etree.ElementTree as ET

wanted = {"Pick a number", "Roll", "Flip the coin", "Generate", "Split", "Calculate", "Grow it"}
try:
    root = ET.parse("ui.xml").getroot()
except Exception as exc:  # noqa: BLE001 - diagnostics only
    print("dump parse failed:", exc)
    raise SystemExit(0)

found = 0
for node in root.iter("node"):
    text = (node.get("text") or "").strip()
    if text not in wanted:
        continue
    bounds = node.get("bounds") or ""
    match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds)
    if not match:
        continue
    left, top, right, bottom = (int(g) for g in match.groups())
    print(f"{(left + right) // 2} {(top + bottom) // 2} {text}")
    found += 1
print("# buttons:", found, file=open("buttons.txt", "w"))
PY

echo "--- buttons found on screen ---"
grep -v '^#' targets.txt | grep -v '# buttons' || true
cat buttons.txt 2>/dev/null || true

while read -r x y label; do
    case "${label:-}" in ""|"#"*) continue ;; esac
    echo "=== tapping: $label ($x,$y) ==="
    adb shell input tap "$x" "$y"
    sleep 2
    P=$(pid_of_app)
    echo "pid: ${P:-<dead>}"
    if [ -z "$P" ]; then
        echo "### CRASH AFTER TAPPING: $label"
        collect
        echo "### tombsones:"
        adb shell "ls -l /data/tombstones 2>/dev/null" || true
        exit 1
    fi
done < targets.txt

echo "all calculator buttons survived"
adb shell am force-stop dev.wizig.wizigapp || true
collect
grep -E "WizigZig|FATAL|AndroidRuntime|libc.*signal" logcat-full.txt | tail -30 || true
exit 0
