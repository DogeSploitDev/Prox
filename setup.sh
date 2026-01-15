#!/bin/bash
set -e

echo "=================================================="
echo " DietPi | Radxa Zero 3W | VPN Router Full Setup"
echo "=================================================="

#######################################
# INTERFACES
#######################################
AP_IF="wlan0"          # Built-in Wi-Fi → AP
UPLINK_IF="wlan1"      # USB Wi-Fi → Internet
VPN_IF="wg0"

#######################################
# ACCESS POINT CONFIG
#######################################
SSID="Radxa-VPN"
PASSPHRASE="vpnpassword123"
AP_IP="192.168.50.1"
DHCP_START="192.168.50.10"
DHCP_END="192.168.50.100"

#######################################
# PATH TO PROTON CONFIG (YOU PROVIDED)
#######################################
PROTON_SRC="/root/wg-US-FREE-86.conf"
PROTON_DST="/etc/wireguard/wg0.conf"

#######################################
# INSTALL REQUIRED PACKAGES
#######################################
echo "[*] Installing packages..."
apt update
apt install -y \
  wireguard \
  hostapd \
  dnsmasq \
  iptables-persistent \
  firmware-atheros \
  iw

#######################################
# USB / WIFI STABILITY FIXES (CRITICAL)
#######################################
echo "[*] Applying USB/Wi-Fi stability fixes..."

# Disable USB autosuspend
echo "options usbcore autosuspend=-1" > /etc/modprobe.d/usb-autosuspend.conf

# Stabilize ath9k_htc
echo "options ath9k_htc nohwcrypt=1" > /etc/modprobe.d/ath9k_htc.conf

#######################################
# ENABLE IP FORWARDING
#######################################
echo "[*] Enabling IP forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-router.conf
sysctl --system

#######################################
# WAIT FOR USB WIFI (wlan1)
#######################################
echo "[*] Waiting for USB Wi-Fi (${UPLINK_IF})..."

for i in {1..20}; do
  if ip link show ${UPLINK_IF} >/dev/null 2>&1; then
    echo "[+] ${UPLINK_IF} detected"
    break
  fi
  echo "  waiting... ($i)"
  sleep 2
done

#######################################
# WIFI CLIENT (UPLINK)
#######################################
if ip link show ${UPLINK_IF} >/dev/null 2>&1; then
  echo "[*] Configuring Wi-Fi uplink..."

  cat > /etc/wpa_supplicant/wpa_supplicant-${UPLINK_IF}.conf <<EOF
ctrl_interface=DIR=/run/wpa_supplicant
update_config=1
country=US

network={
  ssid="Ladoga38-!"
  psk="Westclay01$"
  priority=2
}

network={
  ssid="S25ultra"
  psk="00116868"
  priority=1
}
EOF

  chmod 600 /etc/wpa_supplicant/wpa_supplicant-${UPLINK_IF}.conf
  systemctl enable wpa_supplicant@${UPLINK_IF}
  systemctl restart wpa_supplicant@${UPLINK_IF}
else
  echo "[!] WARNING: ${UPLINK_IF} not present – uplink disabled"
fi

#######################################
# ACCESS POINT (wlan0)
#######################################
echo "[*] Configuring Access Point..."

ip link set ${AP_IF} down || true
ip addr flush dev ${AP_IF} || true
ip addr add ${AP_IP}/24 dev ${AP_IF}
ip link set ${AP_IF} up

cat > /etc/hostapd/hostapd.conf <<EOF
interface=${AP_IF}
ssid=${SSID}
hw_mode=g
channel=6
wmm_enabled=1
auth_algs=1
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sed -i 's|#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

#######################################
# DNS + DHCP
#######################################
echo "[*] Configuring DNS/DHCP..."

cat > /etc/dnsmasq.conf <<EOF
interface=${AP_IF}
dhcp-range=${DHCP_START},${DHCP_END},12h
dhcp-option=3,${AP_IP}
dhcp-option=6,10.2.0.1
EOF

#######################################
# PROTON VPN (USE YOUR FILE)
#######################################
echo "[*] Installing Proton WireGuard config..."

if [ ! -f "${PROTON_SRC}" ]; then
  echo "[!] ERROR: ${PROTON_SRC} not found"
  exit 1
fi

install -m 600 ${PROTON_SRC} ${PROTON_DST}

systemctl enable wg-quick@${VPN_IF}
systemctl restart wg-quick@${VPN_IF}

#######################################
# FIREWALL + VPN KILL SWITCH
#######################################
echo "[*] Applying firewall rules..."

iptables -F FORWARD
iptables -t nat -F

iptables -A FORWARD -i ${AP_IF} -o ${VPN_IF} -j ACCEPT
iptables -A FORWARD -i ${VPN_IF} -o ${AP_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i ${AP_IF} ! -o ${VPN_IF} -j DROP
iptables -t nat -A POSTROUTING -o ${VPN_IF} -j MASQUERADE

netfilter-persistent save

#######################################
# ENABLE SERVICES
#######################################
echo "[*] Enabling services..."

systemctl enable hostapd dnsmasq
systemctl restart dnsmasq
systemctl restart hostapd

#######################################
# DONE
#######################################
echo
echo "=================================================="
echo " SETUP COMPLETE"
echo "=================================================="
echo " AP SSID: ${SSID}"
echo " AP IP: ${AP_IP}"
echo " VPN: Proton WireGuard (${VPN_IF})"
echo " All client traffic forced through VPN"
echo
echo " >>> REBOOT REQUIRED <<<"
echo
