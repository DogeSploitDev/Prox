#!/bin/bash
set -e

echo "=== DietPi | Radxa Zero 3W VPN Router Setup ==="

AP_IF="wlan0"
UPLINK_IF="wlan1"
VPN_IF="wg0"

SSID="Radxa-VPN"
PASSPHRASE="vpnpassword123"
AP_IP="192.168.50.1"

### Install required packages
apt update
apt install -y wireguard hostapd dnsmasq iptables-persistent

### Enable IP forwarding
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-router.conf
sysctl --system

### =========================
### Wi-Fi CLIENT (UPLINK)
### =========================
cat > /etc/wpa_supplicant/wpa_supplicant-${UPLINK_IF}.conf <<EOF
ctrl_interface=DIR=/run/wpa_supplicant
country=US
update_config=1

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
systemctl start wpa_supplicant@${UPLINK_IF}

### =========================
### ACCESS POINT (wlan0)
### =========================
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
wpa=2
wpa_passphrase=${PASSPHRASE}
wpa_key_mgmt=WPA-PSK
rsn_pairwise=CCMP
EOF

sed -i 's|#DAEMON_CONF=.*|DAEMON_CONF="/etc/hostapd/hostapd.conf"|' /etc/default/hostapd

### =========================
### DNS + DHCP
### =========================
cat > /etc/dnsmasq.conf <<EOF
interface=${AP_IF}
dhcp-range=192.168.50.10,192.168.50.100,12h
dhcp-option=3,${AP_IP}
dhcp-option=6,10.2.0.1
EOF

### =========================
### PROTON VPN (WireGuard)
### =========================
cat > /etc/wireguard/${VPN_IF}.conf <<EOF
[Interface]
PrivateKey = YOUR_PRIVATE_KEY
Address = 10.2.0.2/32
DNS = 10.2.0.1

PostUp = iptables -t nat -A POSTROUTING -o ${VPN_IF} -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o ${VPN_IF} -j MASQUERADE

[Peer]
PublicKey = YOUR_PROTON_PUBLIC_KEY
AllowedIPs = 0.0.0.0/0
Endpoint = YOUR_ENDPOINT:51820
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/${VPN_IF}.conf
systemctl enable wg-quick@${VPN_IF}
systemctl start wg-quick@${VPN_IF}

### =========================
### FIREWALL (KILL SWITCH)
### =========================
iptables -F FORWARD
iptables -t nat -F

iptables -A FORWARD -i ${AP_IF} -o ${VPN_IF} -j ACCEPT
iptables -A FORWARD -i ${VPN_IF} -o ${AP_IF} -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i ${AP_IF} ! -o ${VPN_IF} -j DROP

iptables -t nat -A POSTROUTING -o ${VPN_IF} -j MASQUERADE

netfilter-persistent save

### =========================
### START SERVICES
### =========================
systemctl enable hostapd dnsmasq
systemctl restart dnsmasq
systemctl restart hostapd

echo "=== SETUP COMPLETE ==="
echo "AP SSID: ${SSID}"
echo "Reboot recommended"
