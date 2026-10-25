#!/bin/sh
# Drives the installed WizigApp on a booted emulator: scrolls the calculator
# list, taps every calculator button, and fails with logs if the process dies
# or a tap renders no new output. POSIX sh (the emulator runner gives us dash).
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

shot() {
    adb exec-out screencap -p > "shot-$1.png" 2>/dev/null || true
}

texts() {
    python3 .github/ui_texts.py "$1" 2>/dev/null | LC_ALL=C sort > "$2" || true
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
: > results.txt
TAPPED=""
page=0
while [ "$page" -lt 9 ]; do
    page=$((page + 1))
    if ! dump ui.xml; then
        echo "no uiautomator dump on page $page (black screen?)"
        collect
        exit 1
    fi
    texts ui.xml before.txt
    python3 .github/ui_targets.py ui.xml > targets.txt 2>/dev/null || true
    echo "--- page $page targets ---"
    cat targets.txt

    while read -r x y label; do
        case "${label:-}" in ""|"#"*) continue ;; esac
        case "|$TAPPED|" in *"|$label|"*) continue ;; esac
        TAPPED="$TAPPED|$label"

        safe=$(printf '%s' "$label" | tr ' ' '-')
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

        shot "$safe"
        if ! dump "after-$safe.xml"; then
            echo "### no UI dump after $label"
            collect
            exit 1
        fi
        texts "after-$safe.xml" after.txt
        NEW=$(LC_ALL=C comm -13 before.txt after.txt | grep -c . || true)
        echo "new text nodes after $label: $NEW"

        if [ "$NEW" -eq 0 ]; then
            echo "no output after $label, tapping once more"
            adb shell input tap "$x" "$y"
            sleep 2
            dump "after-$safe.xml" || true
            texts "after-$safe.xml" after.txt
            NEW=$(LC_ALL=C comm -13 before.txt after.txt | grep -c . || true)
            if [ "$NEW" -eq 0 ]; then
                echo "### NO OUTPUT for $label (tap did not render a result)"
                collect
                exit 1
            fi
        fi

        echo "$label -> $(LC_ALL=C comm -13 before.txt after.txt | grep . | head -1)" >> results.txt
        {
            echo "--- after tapping $label ---"
            cat after.txt
        } >> ui-texts.txt
    done < targets.txt

    adb shell input swipe 160 470 160 250 300 >/dev/null 2>&1 || true
    sleep 1
done

COUNT=$(printf '%s' "$TAPPED" | tr '|' '\n' | grep -c . || true)
echo "buttons exercised: $COUNT -> $TAPPED"
echo "--- results observed ---"
cat results.txt

if [ "$COUNT" -lt 7 ]; then
    echo "only $COUNT of 7 calculators were reachable"
    collect
    exit 1
fi

echo "all 7 calculators ran on device and rendered output"
adb shell am force-stop dev.wizig.wizigapp || true
collect
grep -E "WizigZig|FATAL|AndroidRuntime|libc.*signal" logcat-full.txt | tail -20 || true
exit 0
