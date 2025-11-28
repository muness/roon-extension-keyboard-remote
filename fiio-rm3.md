# FiiO RM3 Bluetooth Remote Integration

## Overview

This document captures the learnings from integrating the FiiO RM3 Bluetooth LE remote control with the Roon extension in a Debian VM environment. These learnings can be applied to other Roon sidecar projects that need Bluetooth remote support.

## Key Findings

### 1. BlueZ Experimental Mode is Required

**Critical Discovery:** BLE HID devices (like the FiiO RM3) require BlueZ to run with the `--experimental` flag to properly create `/dev/input/event*` devices.

Without `--experimental`:
- BlueZ connects to the device successfully
- GATT services are discovered (UUID 0x1812 - HID over GATT)
- But BlueZ's HOG (HID over GATT) library fails with errors:
  ```
  profiles/input/hog-lib.c:report_reference_cb() Read Report Reference descriptor failed
  profiles/input/hog-lib.c:info_read_cb() HID Information read failed
  ```
- No input devices are created in `/dev/input/`

With `--experimental`:
- All the above errors still occur in logs (they're benign)
- But the uhid kernel module successfully creates input devices:
  ```
  input: FiiO RM3 Consumer Control as /devices/virtual/misc/uhid/.../input3
  input: FiiO RM3 Mouse as /devices/virtual/misc/uhid/.../input4
  input: FiiO RM3 as /devices/virtual/misc/uhid/.../input5
  input: FiiO RM3 Keyboard as /devices/virtual/misc/uhid/.../input6
  ```

**Configuration:**
```bash
# Edit bluetooth service
nano /lib/systemd/system/bluetooth.service

# Change:
ExecStart=/usr/libexec/bluetooth/bluetoothd
# To:
ExecStart=/usr/libexec/bluetooth/bluetoothd --experimental

# Reload and restart
systemctl daemon-reload
systemctl restart bluetooth
```

### 2. Input Device Mapping

The FiiO RM3 creates four input devices, but only one is needed:

- **event3**: `FiiO RM3 Consumer Control` - **This is the one we use**
  - Contains media control keys (play/pause, next, previous)
  - Also has volume up/down
- **event4**: `FiiO RM3 Mouse` - Mouse movement (unused)
- **event5**: `FiiO RM3` - Generic device (unused)
- **event6**: `FiiO RM3 Keyboard` - Full keyboard (unused for media remote)

### 3. Key Code Mappings

From evtest on `/dev/input/event3`:

| Button | Linux Key Code | Key Name | Usage |
|--------|---------------|----------|-------|
| Play/Pause (center) | 164 | KEY_PLAYPAUSE | Primary transport control |
| Next | 163 | KEY_NEXTSONG | Skip forward |
| Previous | 165 | KEY_PREVIOUSSONG | Skip backward |
| Volume Up | 115 | KEY_VOLUMEUP | Volume control |
| Volume Down | 114 | KEY_VOLUMEDOWN | Volume control |

Raw HID scan codes observed in btmon:
- `c00cd` - Play/Pause
- `c00b5` - Next
- `c00b6` - Previous
- `c00e9` - Volume Up
- `c00ea` - Volume Down

### 4. Bluetooth Pairing Process

```bash
bluetoothctl
scan on
# Wait for device to appear: FiiO RM3 (F4:4F:16:00:2C:D8)
pair F4:4F:16:00:2C:D8
trust F4:4F:16:00:2C:D8
connect F4:4F:16:00:2C:D8
exit
```

**Important:**
- Device must be `trusted` for auto-reconnect
- Pairing info is stored in `/var/lib/bluetooth/<adapter_mac>/<device_mac>/`
- After pairing once, device auto-connects on subsequent boots if trusted

### 5. USB Bluetooth Adapter (TP-Link UBH4A)

**Hardware Used:** TP-Link UBH4A USB Bluetooth 5.0 adapter
- Chipset: Realtek RTL8761B
- Requires `firmware-realtek` package from Debian non-free-firmware repo
- Firmware files loaded: `rtl_bt/rtl8761bu_fw.bin` and `rtl_bt/rtl8761bu_config.bin`

**VMware Passthrough:**
- Must connect USB device via VMware Fusion GUI: Virtual Machine > USB & Bluetooth > USB Devices
- Connection does not persist across VM reboots (must reconnect via GUI each time)
- No command-line method available in `vmrun` to connect USB devices

### 6. Reading Input Events in Node.js

**Linux Input Event Structure** (64-bit systems):
```c
struct input_event {
    struct timeval time;    // 16 bytes (8 + 8)
    unsigned short type;    // 2 bytes at offset 16
    unsigned short code;    // 2 bytes at offset 18
    unsigned int value;     // 4 bytes at offset 20
}
// Total: 24 bytes
```

**Reading Events:**
```javascript
const fs = require('fs');
const EVENT_DEVICE = '/dev/input/event3';
const EVENT_SIZE = 24;
const EV_KEY = 1;

const fd = fs.openSync(EVENT_DEVICE, 'r');
const buffer = Buffer.alloc(EVENT_SIZE);

while (true) {
  fs.readSync(fd, buffer, 0, EVENT_SIZE, null);

  const type = buffer.readUInt16LE(16);
  const code = buffer.readUInt16LE(18);
  const value = buffer.readUInt32LE(20);

  if (type === EV_KEY && value === 1) {  // Key press
    // Handle key code
  }
}
```

**Event Values:**
- `0` = Key release
- `1` = Key press
- `2` = Key repeat (auto-repeat when held)

### 7. Integration with stdin-based Extensions

The `keyboard-remote.js` extension expects stdin input with `setRawMode()`, which fails when stdin is a pipe.

**Solution:**
```javascript
// In the extension (keyboard-remote.js)
var stdin = process.stdin;
if (stdin.setRawMode) {
    stdin.setRawMode(true);  // Only set if available (TTY)
}
stdin.resume();
stdin.setEncoding('utf8');
stdin.on('data', key_press);
```

**Bridge Script Architecture:**
```
/dev/input/event3 → fiio-bridge.js → stdout (chars) → keyboard-remote.js → stdin
```

The bridge:
1. Reads binary input events from `/dev/input/event3`
2. Converts key codes to simple characters (e.g., 164 → 'p')
3. Outputs to stdout
4. Extension reads from stdin in pipe mode

### 8. Debian Trixie vs Alpine Linux

**Why we switched from Alpine to Debian:**
- Alpine's Bluetooth support was problematic (needed lts kernel, painful pairing)
- Debian has better BlueZ integration
- More stable Bluetooth firmware support
- Easier to find solutions for Debian-specific issues

### 9. VMware Configuration for Development

**Bridged Networking Required:**
- VM must be on bridged network to communicate with Roon Core on main network
- NAT networking isolates VM, preventing Roon extension discovery

**Shared Folders:**
- VMware shared folders work but require GUI configuration first
- After GUI setup, auto-mount via fstab works:
  ```bash
  .host:/ /mnt/hgfs fuse.vmhgfs-fuse defaults,allow_other 0 0
  ```
- Enables seamless development: edit on host, run in VM

## Architecture for Roon Sidecar Integration

### Design Goals

**Multi-Remote, Multi-Zone Setup:**
- Support multiple Bluetooth remotes paired to a single Raspberry Pi
- Each remote can be assigned to control a specific Roon zone
- Web UI for pairing remotes and assigning zones
- Persistent configuration (survives reboots)
- Auto-reconnect all paired remotes on boot

**User Experience:**
1. User opens sidecar web app
2. Clicks "Add Remote" → Scans for BLE devices
3. Selects FiiO RM3 from list → Pairs automatically
4. Assigns remote to a Roon zone (e.g., "Living Room")
5. Remote immediately starts controlling that zone
6. Can add more remotes for different zones

### Recommended Approach

For a more sophisticated Roon sidecar with Bluetooth support:

#### 1. Bluetooth Management Layer

Auto-reconnect trusted devices on boot, detect when BLE remotes connect/disconnect, provide pairing UI/API for new devices, and store pairing state persistently.

**Web-based Pairing via Node.js:**

```javascript
const { spawn, exec } = require('child_process');
const util = require('util');
const execPromise = util.promisify(exec);

class BluetoothManager {
  constructor() {
    this.devices = this.loadTrustedDevices();
    this.setupAutoReconnect();
  }

  // Scan for BLE devices (called from web UI)
  async scanDevices(timeoutMs = 10000) {
    return new Promise((resolve) => {
      const devices = [];
      const bt = spawn('bluetoothctl', []);

      bt.stdout.on('data', (data) => {
        const output = data.toString();
        // Parse: [NEW] Device F4:4F:16:00:2C:D8 FiiO RM3
        const match = output.match(/\[NEW\] Device ([0-9A-F:]+) (.+)/);
        if (match) {
          devices.push({ mac: match[1], name: match[2] });
        }
      });

      bt.stdin.write('scan on\n');

      setTimeout(() => {
        bt.stdin.write('scan off\n');
        bt.stdin.write('exit\n');
        resolve(devices);
      }, timeoutMs);
    });
  }

  async pairDevice(mac) {
    await execPromise(`echo -e "pair ${mac}\n" | bluetoothctl`);
  }

  async trustDevice(mac) {
    await execPromise(`echo -e "trust ${mac}\n" | bluetoothctl`);
  }

  async connectDevice(mac) {
    await execPromise(`echo -e "connect ${mac}\n" | bluetoothctl`);
  }

  // Full pairing workflow (called from web UI)
  async fullPairing(mac, zoneName) {
    await this.pairDevice(mac);
    await this.trustDevice(mac);
    await this.connectDevice(mac);

    // Save to config
    const config = {
      mac,
      zoneName,
      pairedAt: new Date().toISOString()
    };
    this.saveTrustedDevice(config);

    return config;
  }

  async autoReconnect() {
    for (const device of this.devices) {
      await this.connectDevice(device.mac);
    }
  }

  loadTrustedDevices() {
    // Load from JSON file
    const fs = require('fs');
    try {
      const data = fs.readFileSync('/etc/roon-sidecar/remotes.json', 'utf8');
      return JSON.parse(data);
    } catch {
      return [];
    }
  }

  saveTrustedDevice(config) {
    const devices = this.loadTrustedDevices();
    devices.push(config);
    fs.writeFileSync('/etc/roon-sidecar/remotes.json', JSON.stringify(devices, null, 2));
  }
}
```

#### 2. Input Event Aggregator

Monitor multiple `/dev/input/event*` devices simultaneously, handle device hotplug, and route button presses to the correct zone controller.

**Multi-Remote Zone Routing:**

```javascript
const fs = require('fs');

class InputEventAggregator {
  constructor(roonApi) {
    this.roonApi = roonApi;
    this.devices = new Map(); // deviceMAC -> { eventPath, zoneName, reader }
    this.config = this.loadConfig();
    this.initializeDevices();
  }

  loadConfig() {
    // Load remotes.json: [{ mac, zoneName, pairedAt }]
    const data = fs.readFileSync('/etc/roon-sidecar/remotes.json', 'utf8');
    return JSON.parse(data);
  }

  // Find which /dev/input/eventX corresponds to which MAC address
  async detectInputDevices() {
    const mapping = {};

    // Read /proc/bus/input/devices to map event devices to Bluetooth MACs
    const devices = fs.readFileSync('/proc/bus/input/devices', 'utf8');
    const deviceBlocks = devices.split('\n\n');

    for (const block of deviceBlocks) {
      // Look for FiiO RM3 Consumer Control devices
      if (block.includes('Consumer Control')) {
        // Extract MAC from Uniq: f4:4f:16:00:2c:d8
        const uniqMatch = block.match(/U: Uniq=([0-9a-f:]+)/i);
        // Extract event handler: H: Handlers=kbd event3
        const handlerMatch = block.match(/H: Handlers=.*event(\d+)/);

        if (uniqMatch && handlerMatch) {
          const mac = uniqMatch[1];
          const eventNum = handlerMatch[1];
          mapping[mac] = `/dev/input/event${eventNum}`;
        }
      }
    }

    return mapping;
  }

  async initializeDevices() {
    const inputMapping = await this.detectInputDevices();

    // For each configured remote, start reading its input events
    for (const remote of this.config) {
      const eventPath = inputMapping[remote.mac];
      if (eventPath) {
        this.addDevice(remote.mac, eventPath, remote.zoneName);
      }
    }
  }

  addDevice(mac, eventPath, zoneName) {
    const EVENT_SIZE = 24;
    const EV_KEY = 1;

    const fd = fs.openSync(eventPath, 'r');
    const buffer = Buffer.alloc(EVENT_SIZE);

    // Start reading in a loop (could use worker threads for better performance)
    const reader = setInterval(() => {
      try {
        const bytesRead = fs.readSync(fd, buffer, 0, EVENT_SIZE, null);

        if (bytesRead === EVENT_SIZE) {
          const type = buffer.readUInt16LE(16);
          const code = buffer.readUInt16LE(18);
          const value = buffer.readUInt32LE(20);

          if (type === EV_KEY && value === 1) { // Key press
            this.handleKeyPress(mac, zoneName, code);
          }
        }
      } catch (err) {
        // Device disconnected
        clearInterval(reader);
        this.devices.delete(mac);
      }
    }, 10); // Poll every 10ms

    this.devices.set(mac, {
      eventPath,
      zoneName,
      fd,
      reader
    });

    console.log(`Monitoring ${mac} (${zoneName}) on ${eventPath}`);
  }

  handleKeyPress(mac, zoneName, keyCode) {
    // Map key codes to Roon transport actions
    const actions = {
      164: 'playpause',  // KEY_PLAYPAUSE
      163: 'next',       // KEY_NEXTSONG
      165: 'previous'    // KEY_PREVIOUSSONG
    };

    const action = actions[keyCode];
    if (action) {
      console.log(`Remote ${mac} → Zone "${zoneName}" → ${action}`);
      this.roonApi.controlZone(zoneName, action);
    }
  }

  removeDevice(mac) {
    const device = this.devices.get(mac);
    if (device) {
      clearInterval(device.reader);
      fs.closeSync(device.fd);
      this.devices.delete(mac);
    }
  }
}
```

#### 3. Web API for Configuration

Express API endpoints for the sidecar web app to manage remotes and zones:

```javascript
const express = require('express');
const app = express();

app.use(express.json());

// Scan for available Bluetooth devices
app.get('/api/bluetooth/scan', async (req, res) => {
  try {
    const devices = await bluetoothManager.scanDevices();
    res.json({ devices });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Pair a new remote and assign to zone
app.post('/api/remotes/add', async (req, res) => {
  try {
    const { mac, zoneName } = req.body;

    // Pair via Bluetooth
    await bluetoothManager.fullPairing(mac, zoneName);

    // Detect which event device it created
    await inputAggregator.initializeDevices();

    res.json({ success: true, mac, zoneName });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// List all configured remotes
app.get('/api/remotes', (req, res) => {
  const remotes = JSON.parse(
    fs.readFileSync('/etc/roon-sidecar/remotes.json', 'utf8')
  );
  res.json({ remotes });
});

// Update zone assignment for a remote
app.put('/api/remotes/:mac/zone', (req, res) => {
  const { mac } = req.params;
  const { zoneName } = req.body;

  const remotes = JSON.parse(
    fs.readFileSync('/etc/roon-sidecar/remotes.json', 'utf8')
  );

  const remote = remotes.find(r => r.mac === mac);
  if (remote) {
    remote.zoneName = zoneName;
    fs.writeFileSync('/etc/roon-sidecar/remotes.json', JSON.stringify(remotes, null, 2));

    // Reload input aggregator
    inputAggregator.initializeDevices();

    res.json({ success: true });
  } else {
    res.status(404).json({ error: 'Remote not found' });
  }
});

// Remove a remote
app.delete('/api/remotes/:mac', async (req, res) => {
  const { mac } = req.params;

  // Remove from aggregator
  inputAggregator.removeDevice(mac);

  // Remove from config
  let remotes = JSON.parse(
    fs.readFileSync('/etc/roon-sidecar/remotes.json', 'utf8')
  );
  remotes = remotes.filter(r => r.mac !== mac);
  fs.writeFileSync('/etc/roon-sidecar/remotes.json', JSON.stringify(remotes, null, 2));

  // Unpair from Bluetooth
  await bluetoothManager.removeDevice(mac);

  res.json({ success: true });
});

// Get available Roon zones
app.get('/api/roon/zones', (req, res) => {
  const zones = roonApi.getZones(); // From Roon API
  res.json({ zones });
});

app.listen(3000, () => {
  console.log('Roon Sidecar API listening on port 3000');
});
```

#### 4. Multi-Zone Support
- Map different remotes to different zones
- Allow zone switching via button combinations
- Support "follow active zone" mode

### System Service Architecture

```
┌─────────────────────────────────────────┐
│         Roon Sidecar Service            │
├─────────────────────────────────────────┤
│  BluetoothManager                       │
│    - Auto-pair/reconnect                │
│    - Device discovery                   │
│    - State persistence                  │
├─────────────────────────────────────────┤
│  InputEventAggregator                   │
│    - /dev/input/event* monitoring       │
│    - Hotplug detection                  │
│    - Multi-device support               │
├─────────────────────────────────────────┤
│  RemoteConfiguration                    │
│    - Button mapping storage             │
│    - Programming mode                   │
│    - Profile management                 │
├─────────────────────────────────────────┤
│  RoonExtension (via roon-api)           │
│    - Zone control                       │
│    - Transport commands                 │
│    - Status reporting                   │
└─────────────────────────────────────────┘
```

## Implementation Checklist for Sidecar

### Phase 1: Basic Bluetooth Support
- [ ] Detect if BlueZ is running with `--experimental` flag
- [ ] Auto-enable experimental mode if needed
- [ ] Implement Bluetooth device scanning
- [ ] Implement pairing workflow
- [ ] Store trusted devices persistently

### Phase 2: Input Event Handling
- [ ] Detect FiiO RM3 (and similar devices) in `/dev/input/`
- [ ] Read input events from event3 (Consumer Control)
- [ ] Map key codes to Roon actions
- [ ] Handle device connect/disconnect gracefully

### Phase 3: Configuration & Programming
- [ ] Web UI for device pairing
- [ ] Button programming mode
- [ ] Store button mappings per device
- [ ] Zone assignment per device

### Phase 4: Advanced Features
- [ ] Support multiple remotes simultaneously
- [ ] Hotplug support (udev integration)
- [ ] Battery level monitoring (from Battery Service 0x180F)
- [ ] Auto-reconnect on boot
- [ ] Fallback to BTMon/DBus if experimental mode unavailable

## Known Limitations

1. **BlueZ Experimental Mode Required**
   - Not ideal for production (marked experimental for a reason)
   - May have bugs in edge cases
   - Alternative: Read directly from GATT characteristics via DBus

2. **USB Bluetooth Adapter Passthrough**
   - Cannot be automated in VMware (requires GUI interaction)
   - Not an issue for physical hardware deployments

3. **Device-Specific Key Codes**
   - Different remotes may use different HID scan codes
   - Need per-device mappings

4. **No Noble/BLE Library Compatibility**
   - Noble doesn't work well with bluetoothd running
   - Better to use system BlueZ + input events

## References

- BlueZ HID over GATT: https://git.kernel.org/pub/scm/bluetooth/bluez.git/tree/profiles/input/hog-lib.c
- Linux Input Subsystem: https://www.kernel.org/doc/html/latest/input/input.html
- FiiO RM3: https://www.fiio.com/rm3
- Roon Extension API: https://github.com/RoonLabs/node-roon-api

## Files in This Implementation

- `fiio-bridge.js` - Reads from `/dev/input/event3` and outputs characters
- `keyboard-remote.js` - Modified to accept piped input (no setRawMode requirement)
- `debian-dev.pkr.hcl` - Packer config with BlueZ experimental mode enabled
- `README.md` - Complete setup documentation

## Testing Notes

**Tested Configuration:**
- Hardware: Apple Silicon Mac (M-series)
- VM: Debian Trixie ARM64 (VMware Fusion)
- Bluetooth: TP-Link UBH4A USB adapter (Realtek RTL8761B)
- Remote: FiiO RM3 (BLE HID device)
- Roon Extension: keyboard-remote.js with fiio-bridge.js

**Verified Working:**
- Bluetooth pairing and auto-reconnect
- Input device creation with experimental mode
- Button press detection (play/pause, next, previous)
- Roon transport control
- Zone configuration
- Button programming workflow

**Performance:**
- Button response time: ~50-100ms latency (acceptable)
- Bluetooth reconnect time: ~2-3 seconds after boot
- No dropped button presses observed during testing
