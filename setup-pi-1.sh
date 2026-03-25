#!/bin/bash
# setup-pi-1.sh  —  raspi30 baseline setup
# Run on the Pi over SSH via ethernet adapter (192.168.177.225).
# Sets hostname, hotspot, RTC, dialout group, DVB blacklist, udev rules.
# After this script: sudo reboot, then run setup-pi-2.sh
set -e

HOSTNAME_NEW="raspi30"
HOTSPOT_SSID="raspi30"
HOTSPOT_PASS="raspi30hotspot"   # Change this if desired
HOTSPOT_BAND="bg"               # 2.4 GHz — onboard Pi Zero 2W adapter only

echo "==================================================================="
echo " raspi30  setup-pi-1.sh"
echo "==================================================================="

# ---------------------------------------------------------------------------
# [1/8]  Hostname
# ---------------------------------------------------------------------------
echo ""
echo "[1/8] Setting hostname to $HOSTNAME_NEW..."
CURRENT=$(hostname)
if [ "$CURRENT" = "$HOSTNAME_NEW" ]; then
    echo "      Already set — skipping"
else
    echo "$HOSTNAME_NEW" | sudo tee /etc/hostname > /dev/null
    sudo sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME_NEW/" /etc/hosts
    echo "      Done (was: $CURRENT)"
fi

# ---------------------------------------------------------------------------
# [2/8]  System packages
# ---------------------------------------------------------------------------
echo ""
echo "[2/8] Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y \
    python3 python3-venv python3-pip \
    i2c-tools \
    rtl-sdr \
    udev \
    build-essential \
    git \
    2>&1 | grep -E "^(Get|Inst|Remov|Err)" || true
echo "      Done"

# ---------------------------------------------------------------------------
# [3/8]  Enable I2C and configure RTC (DS3231 at 0x68)
# ---------------------------------------------------------------------------
echo ""
echo "[3/8] Enabling I2C for RTC module..."

# Enable I2C via raspi-config non-interactively
sudo raspi-config nonint do_i2c 0

# Add dtoverlay for DS3231 RTC to /boot/firmware/config.txt
CONFIG=/boot/firmware/config.txt
if grep -q "dtoverlay=i2c-rtc,ds3231" "$CONFIG"; then
    echo "      dtoverlay already present — skipping"
else
    echo "dtoverlay=i2c-rtc,ds3231" | sudo tee -a "$CONFIG" > /dev/null
    echo "      Added dtoverlay=i2c-rtc,ds3231 to $CONFIG"
fi

# Load module now (effective after reboot via dtoverlay)
if ! grep -q "rtc-ds1307" /etc/modules; then
    echo "rtc-ds1307" | sudo tee -a /etc/modules > /dev/null
    echo "      Added rtc-ds1307 to /etc/modules"
fi

# Disable fake-hwclock so real RTC is used at boot
sudo systemctl disable fake-hwclock 2>/dev/null || true
sudo apt-get remove -y fake-hwclock 2>/dev/null || true
echo "      Done (reboot required for I2C to activate)"

# ---------------------------------------------------------------------------
# [4/8]  DVB module blacklist for RTL-SDR
# ---------------------------------------------------------------------------
echo ""
echo "[4/8] Blacklisting DVB modules for RTL-SDR..."
BLACKLIST=/etc/modprobe.d/raspi30-rtlsdr.conf
sudo tee "$BLACKLIST" > /dev/null << 'EOF'
# Prevent DVB drivers claiming the RTL-SDR dongle
blacklist dvb_usb_rtl28xxu
blacklist rtl2832
blacklist rtl2830
EOF
echo "      Written $BLACKLIST"

# ---------------------------------------------------------------------------
# [5/8]  dialout group (serial port access for RAK4631 + Heltec V3)
# ---------------------------------------------------------------------------
echo ""
echo "[5/8] Adding user to dialout group..."
if id -nG "$USER" | grep -qw dialout; then
    echo "      Already in dialout — skipping"
else
    sudo usermod -aG dialout "$USER"
    echo "      Added $USER to dialout"
fi

# plugdev for RTL-SDR udev rules
if id -nG "$USER" | grep -qw plugdev; then
    echo "      Already in plugdev — skipping"
else
    sudo usermod -aG plugdev "$USER"
    echo "      Added $USER to plugdev"
fi

# ---------------------------------------------------------------------------
# [6/8]  udev rules
#   /dev/rtlsdr       — RTL-SDR dongle (idVendor 0bda)
#   /dev/meshtastic   — RAK4631 running Meshtastic (nRF52840 USB CDC, 239a:0029)
#   /dev/meshcore     — Heltec V3 running MeshCore  (CP2102, 10c4:ea60)
#
#   NOTE: To add per-device serial-number rules for extra robustness, plug
#   each device in and run:
#     udevadm info -a -n /dev/ttyACM0 | grep ATTRS{serial}
#   Then add ATTRS{serial}=="..." to the matching rule below.
# ---------------------------------------------------------------------------
echo ""
echo "[6/8] Installing udev rules..."
UDEV=/etc/udev/rules.d/99-raspi30.rules
sudo tee "$UDEV" > /dev/null << 'EOF'
# raspi30 USB device symlinks

# RTL-SDR (Realtek RTL2832U, covers all RTL-SDR variants)
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2838", MODE="0664", GROUP="plugdev", SYMLINK+="rtlsdr"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0bda", ATTRS{idProduct}=="2832", MODE="0664", GROUP="plugdev", SYMLINK+="rtlsdr"

# RAK4631 running Meshtastic firmware (Adafruit nRF52840 USB CDC)
# Appears as /dev/ttyACMx
SUBSYSTEM=="tty", ATTRS{idVendor}=="239a", ATTRS{idProduct}=="0029", MODE="0664", GROUP="dialout", SYMLINK+="meshtastic"

# Heltec LoRa32 V3 running MeshCore firmware (Silicon Labs CP2102)
# Appears as /dev/ttyUSBx
SUBSYSTEM=="tty", ATTRS{idVendor}=="10c4", ATTRS{idProduct}=="ea60", MODE="0664", GROUP="dialout", SYMLINK+="meshcore"
EOF

sudo udevadm control --reload-rules
echo "      Written $UDEV"
echo "      Rules reloaded"
echo ""
echo "      SYMLINKS after devices are plugged in:"
echo "        /dev/rtlsdr     → RTL-SDR dongle"
echo "        /dev/meshtastic → RAK4631 (Meshtastic)"
echo "        /dev/meshcore   → Heltec V3 (MeshCore)"

# ---------------------------------------------------------------------------
# [7/8]  sudoers — passwordless shutdown for the SDR web UI button
# ---------------------------------------------------------------------------
echo ""
echo "[7/8] Adding sudoers entry for passwordless shutdown..."
SUDOERS=/etc/sudoers.d/raspi30-shutdown
if [ -f "$SUDOERS" ]; then
    echo "      Already present — skipping"
else
    echo "user ALL=(ALL) NOPASSWD: /sbin/shutdown" | sudo tee "$SUDOERS" > /dev/null
    sudo chmod 440 "$SUDOERS"
    echo "      Written $SUDOERS"
fi

# ---------------------------------------------------------------------------
# [8/8]  WiFi hotspot (NetworkManager / nmcli)
# ---------------------------------------------------------------------------
echo ""
echo "[8/8] Configuring WiFi hotspot..."

# Set WiFi country code — required to unlock the radio on a fresh Bookworm
# image where WiFi was not configured in Raspberry Pi Imager.
echo "      Setting WiFi country code to DE..."
sudo raspi-config nonint do_wifi_country DE

# Polkit JS rule — required on Bookworm (polkit 121+, which dropped .pkla support)
# Allows members of the netdev group to manage NetworkManager without sudo.
POLKIT_RULE=/etc/polkit-1/rules.d/10-nm-netdev.rules
if [ ! -f "$POLKIT_RULE" ]; then
    sudo tee "$POLKIT_RULE" > /dev/null << 'EOF'
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.NetworkManager.") === 0 &&
        subject.isInGroup("netdev")) {
        return polkit.Result.YES;
    }
});
EOF
    sudo systemctl restart polkit
    echo "      Written polkit rule and restarted polkit"
else
    echo "      Polkit rule already present — skipping"
fi

# Unblock WiFi radio and bring interface up
sudo rfkill unblock wifi
sudo ip link set wlan0 up
nmcli device set wlan0 managed yes

if nmcli connection show "Hotspot" &>/dev/null 2>&1; then
    echo "      Hotspot connection already exists"
    echo "      Ensuring SSID=$HOTSPOT_SSID and autoconnect=yes..."
    nmcli connection modify "Hotspot" \
        802-11-wireless.ssid "$HOTSPOT_SSID" \
        wifi-sec.psk "$HOTSPOT_PASS" \
        connection.autoconnect yes
    echo "      Updated"
else
    nmcli device wifi hotspot \
        ifname wlan0 \
        ssid "$HOTSPOT_SSID" \
        password "$HOTSPOT_PASS" \
        band "$HOTSPOT_BAND"
    nmcli connection modify "Hotspot" connection.autoconnect yes
    echo "      Created hotspot: SSID=$HOTSPOT_SSID"
fi

echo ""
echo "==================================================================="
echo " setup-pi-1.sh COMPLETE"
echo "==================================================================="
echo ""
echo "  Hotspot SSID : $HOTSPOT_SSID"
echo "  Hotspot pass : $HOTSPOT_PASS"
echo "  Hotspot IP   : 10.42.0.1  (clients get 10.42.0.x)"
echo ""
echo "  Next steps:"
echo "    1. sudo reboot"
echo "    2. Reconnect via SSH on ethernet: ssh user@192.168.177.225"
echo "    3. Plug in USB hub with RTL-SDR, RAK4631, Heltec V3"
echo "    4. Verify RTC:   sudo hwclock -r"
echo "    5. Verify devices: ls -la /dev/rtlsdr /dev/meshtastic /dev/meshcore"
echo "    6. Run setup-pi-2.sh"
echo ""
echo "  REBOOT NOW:  sudo reboot"
