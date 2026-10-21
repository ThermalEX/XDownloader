"""Exercise Android task reuse against an installed, ordinary probe debug APK.

Build with `flutter build apk --debug --flavor probe -t lib/main.dart`, install
on the specified device, then run this script. Never targets the production app.
"""
import argparse
import json
import re
import subprocess
import time
import xml.etree.ElementTree as ET

PACKAGE = "com.xdl.app.probe"
COMPONENT = PACKAGE + "/com.xdl.app.MainActivity"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--adb", default="adb")
    args = parser.parse_args()

    def adb(*command):
        return subprocess.check_output(
            [args.adb, "-s", args.device, *command], encoding="utf-8"
        )

    def tasks():
        state = adb("shell", "dumpsys", "activity", "activities")
        return sorted(set(re.findall(
            r"\* Hist\s+#\d+: ActivityRecord\{[^\n]*"
            + re.escape(COMPONENT) + r" t(\d+)", state
        )))

    def expect_input(expected):
        for _ in range(8):
            adb("shell", "uiautomator", "dump", "/sdcard/xdl_share_tasks_probe.xml")
            root = ET.fromstring(adb("exec-out", "cat", "/sdcard/xdl_share_tasks_probe.xml"))
            if any(n.get("class") == "android.widget.EditText" and
                   n.get("text") == expected for n in root.iter("node")):
                return
            time.sleep(0.25)
        raise AssertionError("Existing window did not receive latest share: " + expected)

    adb("shell", "pm", "path", PACKAGE)
    try:
        adb("shell", "am", "start", "-W", "-n", COMPONENT,
            "-a", "android.intent.action.MAIN", "-c", "android.intent.category.LAUNCHER")
        initial = tasks()
        assert len(initial) == 1, f"Fresh probe must start with one task: {initial}"
        # Distinct document data and MULTIPLE_TASK reproduce shares which used to
        # create separate recent-app cards, even with the same receiving Activity.
        for i, flags in enumerate(["0x10000000", "0x18080000", "0x18080000"], 1):
            text = f"xdl_share_probe_{i}"
            adb("shell", "input", "keyevent", "KEYCODE_HOME")
            adb("shell", "am", "start", "-W", "-n", COMPONENT,
                "-a", "android.intent.action.SEND", "-t", "text/plain",
                "-d", f"xdl-probe://share/{i}", "-f", flags,
                "--es", "android.intent.extra.TEXT", text)
            expect_input(text)
            current = tasks()
            print(json.dumps({"share": i, "flags": flags, "task_ids": current}), flush=True)
            assert current == initial, f"Sharing created extra app tasks: {initial} -> {current}"
        print("PASS: three background shares reuse one task and update its input")
    finally:
        adb("shell", "rm", "-f", "/sdcard/xdl_share_tasks_probe.xml")
        adb("shell", "am", "force-stop", PACKAGE)


if __name__ == "__main__":
    main()
