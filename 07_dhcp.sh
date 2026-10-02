#!/bin/sh
# =====================================================================
#  FASE 7:  AÑADIR DHCP
# =====================================================================
#  OBJETIVO: que los PCs nuevos reciban su IP, gateway y DNS de forma
#            AUTOMÁTICA en vez de configurarlos a mano.
#
#   [pc1] (fija .10)  --+                           +-- (fija .10) [pc2]
#                       [sw1]--[ r1 ]== ... ==[ r4 ]--[sw2]
#   [pc3] (DHCP) -------+   servidor DHCP   servidor DHCP  +------- (DHCP) [pc4]
#                           192.168.1.100-150   192.168.2.100-150
#
#  CONCEPTOS:
#   - DHCP: el PC grita "¿alguien me da una IP?" (broadcast) y el
#     servidor le contesta con IP + máscara + gateway + DNS.
#   - Rango (pool): las IPs que el servidor puede repartir. Dejamos
#     las bajas (.1 - .99) para equipos con IP fija.
#   - Lease (concesión): la IP se presta durante un tiempo (12h).
#   - Servidor: dnsmasq en r1 y r4.  Cliente: dhcpcd en pc3 y pc4.
#
#  REQUISITOS: fase 6 ejecutada.
#              sudo pacman -S dnsmasq dhcpcd
#
#  EJECUCIÓN:  sh 07_dhcp.sh
# =====================================================================


# ---------------------------------------------------------------------
# 1. CREACIÓN DE DISPOSITIVOS
#    Dos PCs nuevos: pc3 en la red A y pc4 en la red B.
# ---------------------------------------------------------------------
sudo ip netns add pc3
sudo ip netns add pc4


# ---------------------------------------------------------------------
# 2. CREACIÓN DEL CABLEADO
# ---------------------------------------------------------------------
sudo ip link add veth_pc3_sw1 type veth peer name veth_sw1_pc3
sudo ip link add veth_pc4_sw2 type veth peer name veth_sw2_pc4


# ---------------------------------------------------------------------
# 3. CONEXIÓN DEL CABLEADO
# ---------------------------------------------------------------------
sudo ip link set veth_pc3_sw1 netns pc3
sudo ip link set veth_pc4_sw2 netns pc4
sudo ip link set veth_sw1_pc3 master sw1
sudo ip link set veth_sw2_pc4 master sw2


# ---------------------------------------------------------------------
# 4. DAR DE ALTA LAS INTERFACES
#    ¡OJO! No les ponemos IP: se la dará el DHCP.
# ---------------------------------------------------------------------
sudo ip link set up dev veth_sw1_pc3
sudo ip link set up dev veth_sw2_pc4
sudo ip netns exec pc3 ip link set up dev lo
sudo ip netns exec pc4 ip link set up dev lo
sudo ip netns exec pc3 ip link set up dev veth_pc3_sw1
sudo ip netns exec pc4 ip link set up dev veth_pc4_sw2

echo "== pc3 antes del DHCP (sin IP) =="
sudo ip netns exec pc3 ip addr show dev veth_pc3_sw1


# ---------------------------------------------------------------------
# 5. SERVIDOR DHCP EN r1 (red A)
#    Opciones de dnsmasq:
#     --conf-file=/dev/null        no leer /etc/dnsmasq.conf del host
#     --port=0                     desactivar su DNS (solo queremos DHCP)
#     --interface / --bind-interfaces   escuchar solo en la red A
#     --dhcp-range                 IPs a repartir, máscara y duración
#     --dhcp-option=option:router  gateway que se entrega
#     --dhcp-option=option:dns-server  DNS que se entrega (fase 8)
#     --dhcp-leasefile             dónde apunta qué IP dio a quién
# ---------------------------------------------------------------------
sudo ip netns exec r1 dnsmasq \
    --conf-file=/dev/null \
    --user=root \
    --port=0 \
    --interface=veth_r1_sw1 \
    --bind-interfaces \
    --dhcp-range=192.168.1.100,192.168.1.150,255.255.255.0,12h \
    --dhcp-option=option:router,192.168.1.1 \
    --dhcp-option=option:dns-server,203.0.113.53 \
    --dhcp-leasefile=/tmp/lab/dhcp-r1.leases \
    --pid-file=/tmp/lab/dnsmasq-r1.pid


# ---------------------------------------------------------------------
# 6. SERVIDOR DHCP EN r4 (red B)
#    Igual que el anterior pero con los datos de la red B.
# ---------------------------------------------------------------------
sudo ip netns exec r4 dnsmasq \
    --conf-file=/dev/null \
    --user=root \
    --port=0 \
    --interface=veth_r4_sw2 \
    --bind-interfaces \
    --dhcp-range=192.168.2.100,192.168.2.150,255.255.255.0,12h \
    --dhcp-option=option:router,192.168.2.1 \
    --dhcp-option=option:dns-server,203.0.113.53 \
    --dhcp-leasefile=/tmp/lab/dhcp-r4.leases \
    --pid-file=/tmp/lab/dnsmasq-r4.pid


# ---------------------------------------------------------------------
# 7. CLIENTES DHCP EN pc3 Y pc4
#    Opciones de dhcpcd:
#     -4               solo IPv4
#     -1               pedir la IP una vez y terminar
#     -C resolv.conf   no tocar el DNS (lo ponemos nosotros en la fase 8,
#                      así no se modifica el /etc/resolv.conf del host)
#     -C hostname      no cambiar el nombre del host
#
#    Si no tienes dhcpcd, alternativa:  sudo ip netns exec pc3 dhclient -v veth_pc3_sw1
# ---------------------------------------------------------------------
sudo ip netns exec pc3 dhcpcd -4 -1 -C resolv.conf -C hostname veth_pc3_sw1
sudo ip netns exec pc4 dhcpcd -4 -1 -C resolv.conf -C hostname veth_pc4_sw2


# ---------------------------------------------------------------------
# 8. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== IP que ha recibido pc3 =="
sudo ip netns exec pc3 ip addr show dev veth_pc3_sw1

echo "== Ruta por defecto que ha recibido pc3 =="
sudo ip netns exec pc3 ip route

echo "== IP que ha recibido pc4 =="
sudo ip netns exec pc4 ip addr show dev veth_pc4_sw2

echo "== Concesiones apuntadas por los servidores (caducidad, MAC, IP) =="
cat /tmp/lab/dhcp-r1.leases
cat /tmp/lab/dhcp-r4.leases

# Nota: dnsmasq no reparte las IPs en orden (.100, .101...), las elige
# a partir de la MAC. Mira arriba qué IP le tocó a cada uno.

echo "== pc3 -> pc2 (de la red A a la red B) =="
sudo ip netns exec pc3 ping -c 2 192.168.2.10

echo "== pc3 -> Internet =="
sudo ip netns exec pc3 ping -c 2 8.8.8.8
