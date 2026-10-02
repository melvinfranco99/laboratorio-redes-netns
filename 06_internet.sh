#!/bin/sh
# =====================================================================
#  FASE 6:  LA RED DE LA FASE 5 + INTERNET + IPs PÚBLICAS
# =====================================================================
#  OBJETIVO: conectar nuestra red de routers a un "ISP" y, a través
#            del ISP, a un trozo de Internet simulado (con IPs
#            públicas) y al Internet REAL de tu ordenador.
#
#                    INTERNET SIMULADO (203.0.113.0/24)
#                 [srv1] .10 ----[ inet ]---- .1 [ isp ] .2 ==== .1 HOST ==> Internet real
#                                (bridge)          .1    172.31.255.0/30  (NAT del host)
#                                                   |
#                                       198.51.100.0/30  (IP pública de r1)
#                                                   |
#                                                  .2
#   [pc1]--[sw1]--[ r1 ]==== red de routers de la fase 5 ====[ r4 ]--[sw2]--[pc2]
#                 (NAT)        (r2, r3)
#
#  LO NUEVO RESPECTO A LA FASE 5 está marcado con  >>> NUEVO <<<
#
#  CONCEPTOS:
#   - IP privada (192.168.x.x, 10.x.x.x): solo vale dentro de casa.
#     En Internet nadie sabe llegar a ellas.
#   - IP pública: única en Internet (aquí usamos los rangos de
#     documentación 198.51.100.0/24 y 203.0.113.0/24).
#   - NAT (MASQUERADE): r1 cambia la IP privada de origen por SU IP
#     pública al salir. Así todas las IPs privadas "salen" con una.
#   - Ruta por defecto: "lo que no sé dónde está, a Internet".
#
#  REQUISITOS: iptables.  (El host también hará NAT para salir al
#              Internet real; si usas docker/firewalld puede que
#              tengas que revisar tus reglas de FORWARD.)
#
#  EJECUCIÓN:  sh 06_internet.sh
#  Las fases 7 a 12 se construyen ENCIMA de esta. Ejecútala primero.
# =====================================================================


# ---------------------------------------------------------------------
# 0. LIMPIEZA
#    Además de lo habitual, quitamos las reglas que esta fase pone en
#    el host y los archivos de las fases 7-12.
# ---------------------------------------------------------------------
sudo pkill -f "/tmp/la[b]"    # para servicios del lab (el [b] evita que pkill se mate a sí mismo)
sudo ip -all netns delete
sudo ip link del sw1 2>/dev/null
sudo ip link del sw2 2>/dev/null
sudo ip link del inet 2>/dev/null
sudo iptables -t nat -D POSTROUTING -s 198.51.100.0/24 ! -o veth_host_isp -j MASQUERADE 2>/dev/null
sudo iptables -t nat -D POSTROUTING -s 203.0.113.0/24 ! -o veth_host_isp -j MASQUERADE 2>/dev/null
sudo iptables -D FORWARD -i veth_host_isp -j ACCEPT 2>/dev/null
sudo iptables -D FORWARD -o veth_host_isp -j ACCEPT 2>/dev/null
sudo rm -rf /tmp/lab /etc/netns/pc1 /etc/netns/pc2 /etc/netns/pc3 /etc/netns/pc4

# Carpeta de trabajo para las fases siguientes (logs, configs...)
sudo mkdir -p /tmp/lab
sudo chmod 777 /tmp/lab


# ---------------------------------------------------------------------
# 1. CREACIÓN DE DISPOSITIVOS
# ---------------------------------------------------------------------
sudo ip netns add pc1
sudo ip netns add pc2
sudo ip netns add r1
sudo ip netns add r2
sudo ip netns add r3
sudo ip netns add r4
sudo ip link add sw1 type bridge
sudo ip link add sw2 type bridge

# >>> NUEVO <<<  el ISP, el switch de "Internet" y un servidor público
sudo ip netns add isp
sudo ip netns add srv1
sudo ip link add inet type bridge


# ---------------------------------------------------------------------
# 2. CREACIÓN DEL CABLEADO
# ---------------------------------------------------------------------
# Red A
sudo ip link add veth_pc1_sw1 type veth peer name veth_sw1_pc1
sudo ip link add veth_r1_sw1 type veth peer name veth_sw1_r1
# Red de routers
sudo ip link add veth_r1_r2 type veth peer name veth_r2_r1
sudo ip link add veth_r1_r3 type veth peer name veth_r3_r1
sudo ip link add veth_r2_r3 type veth peer name veth_r3_r2
sudo ip link add veth_r2_r4 type veth peer name veth_r4_r2
sudo ip link add veth_r3_r4 type veth peer name veth_r4_r3
# Red B
sudo ip link add veth_r4_sw2 type veth peer name veth_sw2_r4
sudo ip link add veth_pc2_sw2 type veth peer name veth_sw2_pc2

# >>> NUEVO <<<
sudo ip link add veth_r1_isp type veth peer name veth_isp_r1        # r1  <-> ISP
sudo ip link add veth_isp_inet type veth peer name veth_inet_isp    # ISP <-> switch Internet
sudo ip link add veth_srv1_inet type veth peer name veth_inet_srv1  # srv1 <-> switch Internet
sudo ip link add veth_host_isp type veth peer name veth_isp_host    # HOST <-> ISP


# ---------------------------------------------------------------------
# 3. CONEXIÓN DEL CABLEADO
# ---------------------------------------------------------------------
# PCs
sudo ip link set veth_pc1_sw1 netns pc1
sudo ip link set veth_pc2_sw2 netns pc2
# r1
sudo ip link set veth_r1_sw1 netns r1
sudo ip link set veth_r1_r2 netns r1
sudo ip link set veth_r1_r3 netns r1
# r2
sudo ip link set veth_r2_r1 netns r2
sudo ip link set veth_r2_r3 netns r2
sudo ip link set veth_r2_r4 netns r2
# r3
sudo ip link set veth_r3_r1 netns r3
sudo ip link set veth_r3_r2 netns r3
sudo ip link set veth_r3_r4 netns r3
# r4
sudo ip link set veth_r4_r2 netns r4
sudo ip link set veth_r4_r3 netns r4
sudo ip link set veth_r4_sw2 netns r4
# Switches
sudo ip link set veth_sw1_pc1 master sw1
sudo ip link set veth_sw1_r1 master sw1
sudo ip link set veth_sw2_pc2 master sw2
sudo ip link set veth_sw2_r4 master sw2

# >>> NUEVO <<<
sudo ip link set veth_r1_isp netns r1
sudo ip link set veth_isp_r1 netns isp
sudo ip link set veth_isp_inet netns isp
sudo ip link set veth_isp_host netns isp
sudo ip link set veth_srv1_inet netns srv1
sudo ip link set veth_inet_isp master inet
sudo ip link set veth_inet_srv1 master inet
# (veth_host_isp se queda en el host)


# ---------------------------------------------------------------------
# 4. DAR DE ALTA LAS INTERFACES
# ---------------------------------------------------------------------
# Switches
sudo ip link set up dev sw1
sudo ip link set up dev sw2
sudo ip link set up dev veth_sw1_pc1
sudo ip link set up dev veth_sw1_r1
sudo ip link set up dev veth_sw2_pc2
sudo ip link set up dev veth_sw2_r4
# PCs
sudo ip netns exec pc1 ip link set up dev lo
sudo ip netns exec pc2 ip link set up dev lo
sudo ip netns exec pc1 ip link set up dev veth_pc1_sw1
sudo ip netns exec pc2 ip link set up dev veth_pc2_sw2
# r1
sudo ip netns exec r1 ip link set up dev lo
sudo ip netns exec r1 ip link set up dev veth_r1_sw1
sudo ip netns exec r1 ip link set up dev veth_r1_r2
sudo ip netns exec r1 ip link set up dev veth_r1_r3
# r2
sudo ip netns exec r2 ip link set up dev lo
sudo ip netns exec r2 ip link set up dev veth_r2_r1
sudo ip netns exec r2 ip link set up dev veth_r2_r3
sudo ip netns exec r2 ip link set up dev veth_r2_r4
# r3
sudo ip netns exec r3 ip link set up dev lo
sudo ip netns exec r3 ip link set up dev veth_r3_r1
sudo ip netns exec r3 ip link set up dev veth_r3_r2
sudo ip netns exec r3 ip link set up dev veth_r3_r4
# r4
sudo ip netns exec r4 ip link set up dev lo
sudo ip netns exec r4 ip link set up dev veth_r4_r2
sudo ip netns exec r4 ip link set up dev veth_r4_r3
sudo ip netns exec r4 ip link set up dev veth_r4_sw2

# >>> NUEVO <<<
sudo ip link set up dev inet
sudo ip link set up dev veth_inet_isp
sudo ip link set up dev veth_inet_srv1
sudo ip link set up dev veth_host_isp
sudo ip netns exec r1 ip link set up dev veth_r1_isp
sudo ip netns exec isp ip link set up dev lo
sudo ip netns exec isp ip link set up dev veth_isp_r1
sudo ip netns exec isp ip link set up dev veth_isp_inet
sudo ip netns exec isp ip link set up dev veth_isp_host
sudo ip netns exec srv1 ip link set up dev lo
sudo ip netns exec srv1 ip link set up dev veth_srv1_inet


# ---------------------------------------------------------------------
# 5. PONER IPs
# ---------------------------------------------------------------------
# Red A y Red B (privadas)
sudo ip netns exec pc1 ip addr add 192.168.1.10/24 dev veth_pc1_sw1
sudo ip netns exec r1 ip addr add 192.168.1.1/24 dev veth_r1_sw1
sudo ip netns exec pc2 ip addr add 192.168.2.10/24 dev veth_pc2_sw2
sudo ip netns exec r4 ip addr add 192.168.2.1/24 dev veth_r4_sw2
# Enlaces entre routers (privados)
sudo ip netns exec r1 ip addr add 10.0.12.1/30 dev veth_r1_r2
sudo ip netns exec r2 ip addr add 10.0.12.2/30 dev veth_r2_r1
sudo ip netns exec r1 ip addr add 10.0.13.1/30 dev veth_r1_r3
sudo ip netns exec r3 ip addr add 10.0.13.2/30 dev veth_r3_r1
sudo ip netns exec r2 ip addr add 10.0.23.1/30 dev veth_r2_r3
sudo ip netns exec r3 ip addr add 10.0.23.2/30 dev veth_r3_r2
sudo ip netns exec r2 ip addr add 10.0.24.1/30 dev veth_r2_r4
sudo ip netns exec r4 ip addr add 10.0.24.2/30 dev veth_r4_r2
sudo ip netns exec r3 ip addr add 10.0.34.1/30 dev veth_r3_r4
sudo ip netns exec r4 ip addr add 10.0.34.2/30 dev veth_r4_r3

# >>> NUEVO <<<  IPs PÚBLICAS
# Enlace r1 <-> ISP: 198.51.100.2 es la IP pública de nuestra red
sudo ip netns exec r1 ip addr add 198.51.100.2/30 dev veth_r1_isp
sudo ip netns exec isp ip addr add 198.51.100.1/30 dev veth_isp_r1
# Internet simulado
sudo ip netns exec isp ip addr add 203.0.113.1/24 dev veth_isp_inet
sudo ip netns exec srv1 ip addr add 203.0.113.10/24 dev veth_srv1_inet
# Enlace ISP <-> HOST (salida al Internet real)
sudo ip addr add 172.31.255.1/30 dev veth_host_isp
sudo ip netns exec isp ip addr add 172.31.255.2/30 dev veth_isp_host


# ---------------------------------------------------------------------
# 6. PONER RUTAS
# ---------------------------------------------------------------------
# PCs
sudo ip netns exec pc1 ip route add default via 192.168.1.1
sudo ip netns exec pc2 ip route add default via 192.168.2.1

# Rutas internas entre la red A y la red B (igual que en la fase 5)
sudo ip netns exec r1 ip route add 192.168.2.0/24 via 10.0.12.2 metric 100
sudo ip netns exec r1 ip route add 192.168.2.0/24 via 10.0.13.2 metric 200
sudo ip netns exec r2 ip route add 192.168.1.0/24 via 10.0.12.1 metric 100
sudo ip netns exec r2 ip route add 192.168.1.0/24 via 10.0.23.2 metric 200
sudo ip netns exec r2 ip route add 192.168.2.0/24 via 10.0.24.2 metric 100
sudo ip netns exec r2 ip route add 192.168.2.0/24 via 10.0.23.2 metric 200
sudo ip netns exec r3 ip route add 192.168.1.0/24 via 10.0.13.1 metric 100
sudo ip netns exec r3 ip route add 192.168.1.0/24 via 10.0.23.1 metric 200
sudo ip netns exec r3 ip route add 192.168.2.0/24 via 10.0.34.1 metric 100
sudo ip netns exec r3 ip route add 192.168.2.0/24 via 10.0.23.1 metric 200
sudo ip netns exec r4 ip route add 192.168.1.0/24 via 10.0.24.1 metric 100
sudo ip netns exec r4 ip route add 192.168.1.0/24 via 10.0.34.1 metric 200

# >>> NUEVO <<<  RUTAS POR DEFECTO (hacia Internet)
# r1 es el router frontera: lo desconocido se lo manda al ISP
sudo ip netns exec r1 ip route add default via 198.51.100.1
# r2 y r3 mandan lo desconocido a r1
sudo ip netns exec r2 ip route add default via 10.0.12.1
sudo ip netns exec r3 ip route add default via 10.0.13.1
# r4 lo manda a r2 (y si no a r3)
sudo ip netns exec r4 ip route add default via 10.0.24.1 metric 100
sudo ip netns exec r4 ip route add default via 10.0.34.1 metric 200
# El ISP sale al Internet real a través del host
sudo ip netns exec isp ip route add default via 172.31.255.1
# El servidor público usa al ISP como gateway
sudo ip netns exec srv1 ip route add default via 203.0.113.1
# El host tiene que saber que las IPs públicas del lab están detrás del ISP
sudo ip route add 198.51.100.0/24 via 172.31.255.2
sudo ip route add 203.0.113.0/24 via 172.31.255.2
# OJO: el ISP NO tiene rutas a 192.168.x.x ni a 10.0.x.x -> son privadas


# ---------------------------------------------------------------------
# 7. ACTIVAR LOS ROUTERS
# ---------------------------------------------------------------------
sudo ip netns exec r1 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r2 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r3 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r4 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r1 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1
sudo ip netns exec r2 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1
sudo ip netns exec r3 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1
sudo ip netns exec r4 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1

# >>> NUEVO <<<  el ISP y el host también enrutan
sudo ip netns exec isp sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.ip_forward=1


# ---------------------------------------------------------------------
# 8. >>> NUEVO <<<  NAT
# ---------------------------------------------------------------------
# r1: todo lo que sale hacia el ISP sale con la IP pública 198.51.100.2
sudo ip netns exec r1 iptables -t nat -A POSTROUTING -o veth_r1_isp -j MASQUERADE

# HOST: las IPs públicas "de mentira" del lab salen al Internet real
# con la IP del host (como haría tu router de casa).
sudo iptables -t nat -A POSTROUTING -s 198.51.100.0/24 ! -o veth_host_isp -j MASQUERADE
sudo iptables -t nat -A POSTROUTING -s 203.0.113.0/24 ! -o veth_host_isp -j MASQUERADE
# Permitir en el host el tráfico que entra y sale del ISP
sudo iptables -I FORWARD -i veth_host_isp -j ACCEPT
sudo iptables -I FORWARD -o veth_host_isp -j ACCEPT


# ---------------------------------------------------------------------
# 9. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== Rutas de r1 (router frontera) =="
sudo ip netns exec r1 ip route

echo "== pc1 -> pc2 (la red interna sigue funcionando) =="
sudo ip netns exec pc1 ping -c 2 192.168.2.10

echo "== pc1 -> srv1 (servidor con IP pública) =="
sudo ip netns exec pc1 ping -c 2 203.0.113.10

echo "== pc2 -> srv1 (atraviesa r4, r2, r1 y el ISP) =="
sudo ip netns exec pc2 tracepath -n 203.0.113.10

echo "== pc1 -> Internet REAL (8.8.8.8) =="
sudo ip netns exec pc1 ping -c 2 8.8.8.8

echo "== srv1 -> IP pública de r1: FUNCIONA =="
sudo ip netns exec srv1 ping -c 2 198.51.100.2

echo "== srv1 -> pc1 (IP privada): DEBE FALLAR, desde Internet no se ve =="
sudo ip netns exec srv1 ping -c 2 -W 1 192.168.1.10

echo "== Contadores del NAT de r1 =="
sudo ip netns exec r1 iptables -t nat -L POSTROUTING -n -v
