# roon-extension-keyboard-remote

Roon Extension to control playback via keypresses, and hence via any remote control that can
generate a keypress. This includes Harmony Hubs and many cost-effective RF remotes. It's
designed to be installed on (and probably makes most sense with) players running DietPi and
Roon Bridge, although may work on other Linux platforms with a recent NodeJS and systemd.

------------

## Local Development Setup

### VMware Fusion VM with Alpine Linux

For development with a Bluetooth remote control that needs exclusive device access, use a lightweight Alpine Linux VM on VMware Fusion. This provides reliable Bluetooth/USB passthrough that macOS lacks.

#### Initial Setup

1. **Install prerequisites**
   ```bash
   # Install VMware Fusion (free as of Nov 2024)
   # Download from: https://www.vmware.com/products/fusion.html

   # Install Packer
   brew install packer
   ```

2. **Create and provision the VM**
   ```bash
   packer init dev.pkr.hcl
   packer build dev.pkr.hcl
   ```

   **Note:** Defaults to Apple Silicon (aarch64). For Intel Macs, use:
   ```bash
   packer build -var="alpine_arch=x86_64" dev.pkr.hcl
   ```

   This single command automatically:
   - Downloads Alpine Linux ISO
   - Creates the VM (512MB RAM, 8GB disk, 1 CPU)
   - Installs Alpine unattended
   - Installs Node.js, npm, git, Bluetooth tools
   - Clones and sets up the extension
   - Starts the VM
   - Shows you the IP address

   That's it! The VM is ready to use.

#### Starting the VM (Subsequent Uses)

After the initial setup, you can start the VM again using:

```bash
vmrun -T fusion start output-alpine/roon-remote-alpine.vmx nogui
```

To find the VM's IP address:

```bash
# Check DHCP leases
cat /var/db/vmware/vmnet-dhcpd-vmnet8.leases | grep lease | tail -5

# Or start with GUI to see console
vmrun -T fusion start output-alpine/roon-remote-alpine.vmx gui
```

Other useful commands:

```bash
# Check if VM is running
vmrun -T fusion list

# Stop the VM
vmrun -T fusion stop output-alpine/roon-remote-alpine.vmx

# Power off from inside VM
ssh root@<VM_IP> poweroff
```

#### Working with Code in the VM

Your Mac's project directory is automatically mounted at `/mnt/hgfs` in the VM via VMware shared folders. You can:

1. **Edit files on your Mac** using any editor (VS Code, vim, etc.)
2. **Run code in the VM** where it has Bluetooth support

SSH into the VM and work directly on the shared folder:
```bash
ssh root@<VM_IP>
cd /mnt/hgfs
node keyboard-remote.js
```

**Alternative: VS Code Remote-SSH**

For a full remote development experience:

1. **Install VS Code Remote-SSH extension** on your Mac

2. **Add the VM to your SSH config** (`~/.ssh/config`):
   ```
   Host alpine-dev
     HostName <VM_IP>
     User root
   ```

3. **Connect via VS Code**:
   - Press `Cmd+Shift+P` and search for "Remote-SSH: Connect to Host"
   - Select `alpine-dev`
   - Open `/mnt/hgfs` folder in VS Code

#### Connecting Your Bluetooth Remote

1. **Pair Bluetooth Remote on macOS First**
   - Pair your Bluetooth remote/keyboard with macOS normally
   - Go to System Settings > Bluetooth
   - Pair your device

2. **Pass Through Bluetooth Device to VM**
   - In VMware Fusion, go to Virtual Machine > USB & Bluetooth
   - Check "Enable Bluetooth"
   - Select your Bluetooth remote from the list
   - OR if using a USB Bluetooth dongle:
     - Plug in the dongle
     - Go to Virtual Machine > USB & Bluetooth > USB Devices
     - Connect the USB Bluetooth adapter

3. **Verify Device in VM**
   ```bash
   # List input devices
   ls -la /dev/input/

   # You should see event devices (event0, event1, etc.)
   # Test which one is your remote
   sudo evtest
   # Select your device number and press buttons to verify
   ```

#### Troubleshooting

**VM can't see Bluetooth device:**
- Ensure device is connected in VM menu (Virtual Machine > USB & Bluetooth)
- Try disconnecting/reconnecting the device
- For USB dongles, ensure they're connected to the VM, not the host

**Extension can't find Roon Core:**
- Ensure VM network is set to Bridged or NAT
- Check VM can reach your network: `ping 8.8.8.8`
- Verify Roon Core is on the same network

**Keypresses not working:**
- Verify device is sending events: `sudo evtest`
- Check the extension is reading from stdin correctly
- Ensure VM console/terminal is focused (not headless mode) during initial testing

#### Running the Extension

1. **SSH into the VM**
   ```bash
   ssh root@192.168.x.x  # Use your VM's IP
   ```

2. **Start the extension**
   ```bash
   cd /opt/roon-extension-keyboard-remote
   node keyboard-remote.js
   ```

3. **Enable in Roon**
   - Open Roon on any device (on the same network)
   - Go to Settings > Extensions
   - Enable the extension and configure keys

------------

**IMPORTANT:**

* After installation, the main systemd service for this extension will autostart and start receiving keypresses on the
  second virtual console. A second service will, five seconds after boot, automatically switch the active virtual console to
  the second one. If you need to login directly on the physical console, you will need to switch back to the first to see
  a login prompt. To do this, use Alt+F1, or Alt+Left. To switch back and resume remote control, use Alt+F2, or Alt+Right.

* Ensure that you **have not** enabled 'PSU noise reduction' enabled in dietpi-config > Audio options. It isn't on by default,
  so you would have to have done this deliberately. If it is enabled, it will disable HDMI, including the virtual console.
  Boot-up will not complete, because this extension needs the console to operate, and you won't be able to SSH in. If you
  find yourself in this situation, to recover take out the MicroSD card and, on another computer, edit dietpi.txt in the
  root directory. Find the line:

  ```
  rpi_hdmi_output=0
  ```

  and change it to:

  ```
  rpi_hdmi_output=1
  ```

  You will then be able to boot once with HDMI on. Log in, start dietpi-config, go to Audio options and turn off
  'PSU noise reduction' to fix the problem.

* If you're installing this extension on multiple endpoints, you'll need to set different hostnames using
  dietpi-config > Security Options > Change Hostname. This way, multiple extensions (with the hostname in brackets)
  will appear in the Roon > Settings > Extensions, enabling independent configuration.

------------

## Installation on DietPi

1. Install Node.js from dietpi-software > Software Additional

1. Download the Keyboard Remote extension.

   ```bash
   apt-get install git
   cd /opt
   git clone https://github.com/mjmaisey/roon-extension-keyboard-remote.git
   ```

1. Install the dependencies:
    ```bash
    cd roon-extension-keyboard-remote
    npm install
    ```

1. Install to start on the second virtual console automatically on startup
    ```bash
    mkdir /etc/roon-extension-keyboard-remote
    cp changevt.service roon-extension-keyboard-remote.service /lib/systemd/system
    systemctl enable roon-extension-keyboard-remote.service
    systemctl enable changevt.service
    ```

1. Reboot
    ```bash
    shutdown -r now
    ```

    The extension should appear in Roon now. See Settings->Setup->Extensions and you should see it in the list.


------------

## Using a Bluetooth keyboard with a Raspberry Pi

1. Enable Bluetooth in dietpi-config > Advanced

1. Run bluetoothctl and pair the Bluetooth keyboard, which should look something like the following (with
   different device addresses, of course)
    ```
    [NEW] Controller 11:22:33:44:55:66 dietpi [default]
    [bluetooth] agent on
    Agent registered
    [bluetooth] default-agent
    Default agent request successful
    [bluetooth] scan on
    [CHG] Controller 11:22:33:44:55:66 Discovering: yes
    [NEW] Device AA:BB:CC:DD:EE:FF Harmony Keyboard
    [bluetooth] pair AA:BB:CC:DD:EE:FF
    Attempting to pair with AA:BB:CC:DD:EE:FF
    Pairing successful
    [bluetooth] connect AA:BB:CC:DD:EE:FF
    Attempting to connect to AA:BB:CC:DD:EE:FF
    Connection successful
    [bluetooth] trust AA:BB:CC:DD:EE:FF
    Changing AA:BB:CC:DD:EE:FF trust succeeded
    [bluetooth] exit
    ```

------------

## Using a Harmony Hub as a bluetooth keyboard for a Raspberry Pi

1. Create a new 'Windows PC' device in the Harmony app

1. Create a new Activity using the device in the Harmony app (and any amp you'd like to control). This
   should then prompt you to pair, at least in the iOS app - this doesn't seem to work in the Harmony
   desktop app. Do the pairing on the Raspberry Pi as above.

1. You'll need to alter the buttons on the activity, as Harmony's default media key mappings only seem to
   result in a null keypress on a Raspberry Pi. I found space for play/pause and left/right direction
   keys for previous and next track respectively work well.

------------

## Enabling and programming the extension

1. Open Roon on any device (PC, Mac, iPad etc.)

1. Go to Settings > Extensions

1. Enable the Extension. The status should change to 'Program - press Next'

1. Press the relevant keys on your control device (currently Next, Previous, Play/Pause) in response to the
   prompts

1. Go into the extension settings and select your controlled zone, then click 'Save'

1. The status should now read 'Controlling zone <zone name>'. Enjoy.

If you do not have particular keys on your control device, going into the settings and entering a dash into
the fields for the relevant key and pressing 'Save' will result in the key being skipped during programming.

If you wish to reprogram any key, simply delete the contents of the field for the key(s) in the extension
Settings and it will go back into programming mode for the keys.
