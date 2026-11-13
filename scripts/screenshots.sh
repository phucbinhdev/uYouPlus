#!/bin/bash
# Build Piano Go cho trình giả lập iPad, chạy các màn hình chính và chụp ảnh.
# Dùng trong GitHub Actions (macOS). Kết quả nằm trong thư mục screenshots/.
set -euo pipefail

BUNDLE_ID="com.pianogo.app"
OUT="screenshots"
mkdir -p "$OUT"

# Chọn một iPad có sẵn (ưu tiên iPad Pro / iPad Air).
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
data = json.load(sys.stdin)["devices"]
best = None
for runtime, devices in data.items():
    if "iOS" not in runtime:
        continue
    for d in devices:
        name = d["name"]
        if not name.startswith("iPad"):
            continue
        score = 3 if "Pro" in name and "13" in name else 2 if "Pro" in name else 1 if "Air" in name else 0
        if best is None or score > best[0]:
            best = (score, d["udid"], name)
print(best[1] if best else "")
')
if [ -z "$UDID" ]; then
  echo "Không tìm thấy trình giả lập iPad"; exit 1
fi
echo "Dùng trình giả lập: $UDID"

xcodebuild -project PianoGo.xcodeproj -scheme PianoGo -configuration Debug \
  -sdk iphonesimulator -destination "id=$UDID" -derivedDataPath build-sim \
  CODE_SIGNING_ALLOWED=NO build -quiet

APP=$(find build-sim/Build/Products -name "PianoGo.app" -path "*iphonesimulator*" | head -1)
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
xcrun simctl status_bar "$UDID" override --time "9:41" --batteryState charged --batteryLevel 100 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl privacy "$UDID" grant bluetooth "$BUNDLE_ID" 2>/dev/null || true

shot() {
  local name="$1"; shift
  local orientation="$1"; shift
  xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
  xcrun simctl launch "$UDID" "$BUNDLE_ID" "$@" >/dev/null
  sleep 6
  xcrun simctl io "$UDID" screenshot "$OUT/$name.png" >/dev/null
  echo "Đã chụp $name"
}

# Lần chạy đầu tiên: màn hình chào mừng.
shot 01-onboarding portrait
shot 02-path portrait -PGShot 1 -PGDemo 1 -PGTab 0
shot 03-lesson-intro portrait -PGShot 1 -PGLesson u1l2
shot 04-lesson-melody portrait -PGShot 1 -PGLesson u2l5
shot 05-lesson-staff portrait -PGShot 1 -PGLesson u3l3
shot 06-lesson-quiz portrait -PGShot 1 -PGLesson u3l1 -PGSkip 5
shot 07-lesson-theory portrait -PGShot 1 -PGLesson u1l1
shot 08-lesson-rhythm portrait -PGShot 1 -PGLesson u4l1 -PGSkip 1
shot 09-lesson-chord portrait -PGShot 1 -PGLesson u6l1 -PGSkip 2
shot 10-songs portrait -PGShot 1 -PGTab 1
shot 11-song-player portrait -PGShot 1 -PGTab 1 -PGSong fur-elise
shot 12-freeplay portrait -PGShot 1 -PGTab 2
shot 13-profile portrait -PGShot 1 -PGTab 3
shot 14-connect portrait -PGShot 1 -PGTab 0 -PGConnect 1

ls -la "$OUT"
