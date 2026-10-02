#!/bin/sh
# =====================================================================
#  FASE 10:  AÑADIR UNA VPN (WireGuard)
# =====================================================================
#  OBJETIVO: un usuario que está en su CASA (en Internet) quiere
#            entrar a nuestras redes privadas (192.168.1.x y 192.168.2.x)
#            como si estuviera dentro. Para eso creamos un túnel
#            cifrado entre su casa y r1.
#
#      [casa] 203.0.113.100                          [ r1 ] 198.51.100.2
#        wg0: 10.10.0.2  ====== TÚNEL CIFRADO ======  wg0: 10.10.0.1
#           |                  (UDP 51820)               |
#           +--> 192.168.0.0/16 va por el túnel          +--> red A, red B
#
#  CONCEPTOS:
#   - WireGuard: VPN moderna. Cada extremo tiene una clave privada
#     (secreta) y una pública (se la da al otro extremo).
#   - wg0: interfaz virtual. Lo que entra por wg0 sale cifrado por
#     UDP hacia el otro extremo, y allí se descifra.
#   - allowed-ips: qué IPs se aceptan/envían por el túnel para cada
#     extremo (hace de "ruta" y de "filtro" a la vez).
#
#  REQUISITOS: fases 6 a 9 ejecutadas.
#              sudo pacman -S wireguard-tools
#
#  EJECUCIÓN:  sh 10_vpn.sh
# =====================================================================


# ---------------------------------------------------------------------
# 1. CREACIÓN DEL EQUIPO DE CASA (un cliente en Internet)
# ---------------------------------------------------------------------
sudo ip netns add casa


# ---------------------------------------------------------------------
# 2. CABLEADO: casa <-> switch de Internet
# ---------------------------------------------------------------------
sudo ip link add veth_casa_inet type veth peer name veth_inet_casa
sudo ip link set veth_casa_inet netns casa
sudo ip link set veth_inet_casa master inet


# ---------------------------------------------------------------------
# 3. DAR DE ALTA, IP Y RUTA
# ---------------------------------------------------------------------
sudo ip link set up dev veth_inet_casa
sudo ip netns exec casa ip link set up dev lo
sudo ip netns exec casa ip link set up dev veth_casa_inet
sudo ip netns exec casa ip addr add 203.0.113.100/24 dev veth_casa_inet
sudo ip netns exec casa ip route add default via 203.0.113.1

echo "== ANTES de la VPN: casa NO llega a pc1 (IP privada) =="
sudo ip netns exec casa ping -c 2 -W 1 192.168.1.10


# ---------------------------------------------------------------------
# 4. GENERAR LAS CLAVES
#    umask 077 -> los archivos de claves solo los puede leer su dueño.
#    wg genkey  -> clave privada
#    wg pubkey  -> calcula la pública a partir de la privada
# ---------------------------------------------------------------------
mkdir -p /tmp/lab/wg
umask 077
wg genkey > /tmp/lab/wg/r1.key
wg pubkey < /tmp/lab/wg/r1.key > /tmp/lab/wg/r1.pub
wg genkey > /tmp/lab/wg/casa.key
wg pubkey < /tmp/lab/wg/casa.key > /tmp/lab/wg/casa.pub
umask 022

echo "== Clave pública de r1 y de casa =="
cat /tmp/lab/wg/r1.pub
cat /tmp/lab/wg/casa.pub


# ---------------------------------------------------------------------
# 5. SERVIDOR VPN EN r1
#    - Creamos la interfaz wg0 dentro de r1.
#    - Le damos su clave privada y el puerto donde escucha.
#    - Añadimos a casa como "peer": su clave pública y la IP que
#      puede usar dentro del túnel (10.10.0.2).
#    $(cat archivo) = pegar el contenido del archivo en el comando.
# ---------------------------------------------------------------------
sudo ip netns exec r1 ip link add wg0 type wireguard
sudo ip netns exec r1 wg set wg0 private-key /tmp/lab/wg/r1.key listen-port 51820
sudo ip netns exec r1 wg set wg0 peer $(cat /tmp/lab/wg/casa.pub) allowed-ips 10.10.0.2/32
sudo ip netns exec r1 ip addr add 10.10.0.1/24 dev wg0
sudo ip netns exec r1 ip link set up dev wg0


# ---------------------------------------------------------------------
# 6. CLIENTE VPN EN casa
#    - endpoint: dónde está el servidor (IP pública de r1 y puerto).
#    - allowed-ips: por el túnel van la red del túnel (10.10.0.0/24)
#      y nuestras redes privadas (192.168.0.0/16).
#    - persistent-keepalive: un paquete cada 25 s para mantener vivo
#      el túnel aunque no haya tráfico.
# ---------------------------------------------------------------------
sudo ip netns exec casa ip link add wg0 type wireguard
sudo ip netns exec casa wg set wg0 private-key /tmp/lab/wg/casa.key
sudo ip netns exec casa wg set wg0 peer $(cat /tmp/lab/wg/r1.pub) endpoint 198.51.100.2:51820 allowed-ips 10.10.0.0/24,192.168.0.0/16 persistent-keepalive 25
sudo ip netns exec casa ip addr add 10.10.0.2/24 dev wg0
sudo ip netns exec casa ip link set up dev wg0


# ---------------------------------------------------------------------
# 7. RUTAS
#    - casa: para llegar a las redes privadas, usar wg0.
#      (10.10.0.0/24 ya se añade sola al poner la IP en wg0)
#    - r1: conoce 10.10.0.0/24 porque está conectado a wg0.
#    - r2, r3 y r4: las respuestas a 10.10.0.2 siguen su ruta por
#      defecto hacia r1 (fase 6), así que no hay que tocar nada.
# ---------------------------------------------------------------------
sudo ip netns exec casa ip route add 192.168.0.0/16 dev wg0


# ---------------------------------------------------------------------
# 8. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== casa hace ping al otro extremo del túnel (r1) =="
sudo ip netns exec casa ping -c 2 10.10.0.1

echo "== CON la VPN: casa llega a pc1 (red A) =="
sudo ip netns exec casa ping -c 2 192.168.1.10

echo "== CON la VPN: casa llega a pc2 (red B, detrás de la red de routers) =="
sudo ip netns exec casa ping -c 2 192.168.2.10

echo "== casa abre la intranet de pc1 a través del túnel =="
sudo ip netns exec casa curl -s http://192.168.1.10

echo "== Camino: el primer salto es r1 (10.10.0.1), el túnel oculta el ISP =="
sudo ip netns exec casa tracepath -n 192.168.2.10

echo "== Estado del túnel en r1 (último handshake y bytes) =="
sudo ip netns exec r1 wg show
