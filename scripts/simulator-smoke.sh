#!/bin/bash
set -euo pipefail
xcrun simctl list devices available --json > verification-output/simulators.json
watch_id=$(python3 - <<'PY'
import json
data=json.load(open('verification-output/simulators.json'))
for runtime, devices in data['devices'].items():
    if 'watchOS' in runtime:
        for device in devices:
            if device.get('isAvailable'):
                print(device['udid']); raise SystemExit(0)
raise SystemExit('No available watchOS simulator runtime. Native smoke test is incomplete.')
PY
)
xcrun simctl boot "$watch_id"
xcrun simctl bootstatus "$watch_id" -b
app='DerivedData/Build/Products/Debug-watchsimulator/MyWatchOSApp Watch App.app'
xcrun simctl install "$watch_id" "$app"
for scene in demo demo-navigation demo-fault demo-destination; do
  printf 'Scene: %s\n' "$scene" >> verification-output/simulator-launch.txt
  xcrun simctl launch "$watch_id" com.grantknight.vescfoil.watchkitapp "--$scene" | tee -a verification-output/simulator-launch.txt
  sleep 8
  xcrun simctl spawn "$watch_id" launchctl list | grep com.grantknight.vescfoil.watchkitapp >> verification-output/simulator-launch.txt
  xcrun simctl io "$watch_id" screenshot "verification-output/watch-$scene.png"
  xcrun simctl terminate "$watch_id" com.grantknight.vescfoil.watchkitapp
done
xcrun simctl shutdown "$watch_id"
