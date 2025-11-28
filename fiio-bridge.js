#!/usr/bin/env node
// Bridge script to read FiiO RM3 from /dev/input/event3
// and convert keypresses to characters for keyboard-remote.js

const fs = require('fs');

const EVENT_DEVICE = '/dev/input/event3'; // FiiO RM3 Consumer Control

// Linux input event structure (24 bytes on 64-bit systems)
const EVENT_SIZE = 24;

// Event types
const EV_KEY = 1;

// Key codes we care about
const KEY_PLAYPAUSE = 164;
const KEY_NEXTSONG = 163;
const KEY_PREVIOUSSONG = 165;

// Map key codes to characters that keyboard-remote.js will recognize
// We'll use distinct characters that can be programmed in the extension
const KEY_MAP = {
  [KEY_PLAYPAUSE]: 'p',      // Play/Pause
  [KEY_NEXTSONG]: 'n',        // Next
  [KEY_PREVIOUSSONG]: 'b',    // Previous (back)
};

console.error('FiiO RM3 Bridge starting...');
console.error('Reading from:', EVENT_DEVICE);
console.error('Key mappings:');
console.error('  Play/Pause (164) -> "p"');
console.error('  Next (163) -> "n"');
console.error('  Previous (165) -> "b"');
console.error('');
console.error('Waiting for button presses...');

try {
  const fd = fs.openSync(EVENT_DEVICE, 'r');
  const buffer = Buffer.alloc(EVENT_SIZE);

  while (true) {
    const bytesRead = fs.readSync(fd, buffer, 0, EVENT_SIZE, null);

    if (bytesRead === EVENT_SIZE) {
      // Parse the input event structure
      // struct input_event {
      //   struct timeval time; // 16 bytes (8 + 8)
      //   unsigned short type; // 2 bytes
      //   unsigned short code; // 2 bytes
      //   unsigned int value;  // 4 bytes
      // }

      const type = buffer.readUInt16LE(16);
      const code = buffer.readUInt16LE(18);
      const value = buffer.readUInt32LE(20);

      // We only care about key press events (value = 1)
      // value = 0 is key release, value = 2 is key repeat
      if (type === EV_KEY && value === 1) {
        const char = KEY_MAP[code];
        if (char) {
          // Output the character to stdout for keyboard-remote.js
          process.stdout.write(char);
          console.error(`Button pressed: ${code} -> "${char}"`);
        }
      }
    }
  }
} catch (error) {
  console.error('Error:', error.message);
  process.exit(1);
}
