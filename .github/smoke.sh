#!/bin/sh
# Drives the installed WizigApp on a booted emulator: scrolls the calculator
# list, taps every calculator button and fails with logs if the process dies
# or no result shows up. POSIX sh (the Android emulator runner gives us dash).
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

dump() {
    adb shell uiautomator dump "/sdcard/$1" >/dev/null 2>&1 || true
    adb pull "/sdcard/$1" "$1" >/dev/null 2>&1 || true
    [ -s "$1" ]
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

: > ui-texts.txt
TAPPED=""
page=0
while [ "$page" -lt 9 ]; do
    page=$((page + 1))
    if ! dump ui.xml; then
        echo "no uiautomator dump on page $page (black screen?)"
        collect
        exit 1
    fi
    python3 .github/ui_targets.py ui.xml > targets.txt 2>/dev/null || true
    echo "--- page $page targets ---"
    cat targets.txt

    while read -r x y label; do
        case "${label:-}" in ""|"#"*) continue ;; esac
        case "|$TAPPED|" in *"|$label|"*) continue ;; esac
        TAPPED="$TAPPED|$label"
        echo "=== tapping: $label ($x,$y) on page $page ==="
        adb shell input tap "$x" "$y"
        sleep 2
        P=$(pid_of_app)
        echo "pid: ${P:-<dead>}"
        if [ -z "$P" ]; then
            echo "### CRASH AFTER TAPPING: $label"
            collect
            exit 1
        fi
        if dump ui2.xml; then
            {
                echo "--- after tapping $label ---"
                python3 .github/ui_texts.py ui2.xml || true
            } >> ui-texts.txt
            echo "rendered after $label:"
            python3 .github/ui_texts.py ui2.xml | tail -4 || true
        fi
    done < targets.txt

    adb shell input swipe 160 470 160 250 300 >/dev/null 2>&1 || true
    sleep 1
done

COUNT=$(printf '%s' "$TAPPED" | tr '|' '\n' | grep -c . || true)
echo "buttons exercised: $COUNT -> $TAPPED"

if ! grep -q "Your number:" ui-texts.txt; then
    echo "NO RESULT RENDERED for the random number calculator"
    collect
    exit 1
fi
echo "random number result rendered:"
grep -A2 "after tapping Pick a number" ui-texts.txt | head -5

if [ "$COUNT" -lt 7 ]; then
    echo "only $COUNT of 7 calculators were reachable"
    collect
    exit 1
fi

echo "all 7 calculators ran on device"
adb shell am force-stop dev.wizig.wizigapp || true
collect
grep -E "WizigZig|FATAL|AndroidRuntime|libc.*signal" logcat-full.txt | tail -20 || true
exit 0
