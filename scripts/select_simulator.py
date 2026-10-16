"""Select an available iPhone, failing explicitly if the runner lacks one."""
import json
import os
import subprocess


if __name__ == '__main__':
    listing = json.loads(subprocess.check_output(
        ['xcrun', 'simctl', 'list', 'devices', 'available', '--json'], text=True))
    requested_runtime = os.environ.get('IOS_SIMULATOR_RUNTIME')
    candidates = [device for runtime, devices in listing['devices'].items()
                  if '.iOS-' in runtime for device in devices
                  if not requested_runtime or runtime == requested_runtime
                  if device.get('isAvailable') and device['name'].startswith('iPhone')]
    if not candidates:
        raise SystemExit(f'No available iPhone simulator for {requested_runtime or "iOS"}.')
    selected = next((device for device in candidates if device['name'] == 'iPhone 13'), candidates[0])
    print(f"Selected {selected['name']}: {selected['udid']}")
    with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
        print(f"device_id={selected['udid']}", file=output)
