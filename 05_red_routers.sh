#!/bin/sh
# =====================================================================
#  FASE 5:  PC - SW - (RED DE ROUTERS) - SW - PC
# =====================================================================
#  OBJETIVO: los routers ya no forman una línea, sino una RED con
#            varios caminos posibles. Si un enlace se cae, el tráfico
#            puede ir por otro lado (camino de respaldo).
#
#                     10.0.12.0/30            10.0.24.0/30
#                .1 +-------------.2[ r2 ].1-------------+ .2
#                   |                  | .1               |
#   [pc1]--[sw1]--[ r1 ]          10.0.23.0/30         [ r4 ]--[sw2]--[pc2]
#   .1.10      .1.1 |                  | .2               | .2.1       .2.10
#                .1 +-------------.2[ r3 ].1-------------+ .2
#                     10.0.13.0/30            10.0.34.0/30
#
#   Camino principal:  r1 -> r2 -> r4
#   Camino respaldo :  r1 -> r3 -> r4
#
#  CONCEPTOS:
#   - Métrica: si hay dos rutas a la misma red, se usa la de métrica
#     MÁS BAJA. La otra queda de reserva.
#   - Cuando una interfaz se apaga, el kernel borra las rutas que
#     salían por ella y entra en juego la de reserva.
#   - ignore_routes_with_linkdown=1: si el cable está desconectado
#     (el otro extremo apagado), no usar las rutas que salen por él.
#
#  EJECUCIÓN:  sh 05_red_routers.sh
# =====================================================================


# ---------------------------------------------------------------------
# 0. LIMPIEZA
# ---------------------------------------------------------------------
sudo pkill -f "/tmp/la[b]"    # para servicios del lab (el [b] evita que pkill se mate a sí mismo)
sudo ip -all netns delete
sudo ip link del sw1 2>/dev/null
sudo ip link del sw2 2>/dev/null
sudo ip link del inet 2>/dev/null


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


# ---------------------------------------------------------------------
# 2. CREACIÓN DEL CABLEADO
# ---------------------------------------------------------------------
# Red A
sudo ip link add veth_pc1_sw1 type veth peer name veth_sw1_pc1
sudo ip link add veth_r1_sw1 type veth peer name veth_sw1_r1
# Red de routers (5 enlaces)
sudo ip link add veth_r1_r2 type veth peer name veth_r2_r1
sudo ip link add veth_r1_r3 type veth peer name veth_r3_r1
sudo ip link add veth_r2_r3 type veth peer name veth_r3_r2
sudo ip link add veth_r2_r4 type veth peer name veth_r4_r2
sudo ip link add veth_r3_r4 type veth peer name veth_r4_r3
# Red B
sudo ip link add veth_r4_sw2 type veth peer name veth_sw2_r4
sudo ip link add veth_pc2_sw2 type veth peer name veth_sw2_pc2


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


# ---------------------------------------------------------------------
# 5. PONER IPs
# ---------------------------------------------------------------------
# Red A y Red B
sudo ip netns exec pc1 ip addr add 192.168.1.10/24 dev veth_pc1_sw1
sudo ip netns exec r1 ip addr add 192.168.1.1/24 dev veth_r1_sw1
sudo ip netns exec pc2 ip addr add 192.168.2.10/24 dev veth_pc2_sw2
sudo ip netns exec r4 ip addr add 192.168.2.1/24 dev veth_r4_sw2

# r1 <-> r2  (10.0.12.0/30)
sudo ip netns exec r1 ip addr add 10.0.12.1/30 dev veth_r1_r2
sudo ip netns exec r2 ip addr add 10.0.12.2/30 dev veth_r2_r1
# r1 <-> r3  (10.0.13.0/30)
sudo ip netns exec r1 ip addr add 10.0.13.1/30 dev veth_r1_r3
sudo ip netns exec r3 ip addr add 10.0.13.2/30 dev veth_r3_r1
# r2 <-> r3  (10.0.23.0/30)
sudo ip netns exec r2 ip addr add 10.0.23.1/30 dev veth_r2_r3
sudo ip netns exec r3 ip addr add 10.0.23.2/30 dev veth_r3_r2
# r2 <-> r4  (10.0.24.0/30)
sudo ip netns exec r2 ip addr add 10.0.24.1/30 dev veth_r2_r4
sudo ip netns exec r4 ip addr add 10.0.24.2/30 dev veth_r4_r2
# r3 <-> r4  (10.0.34.0/30)
sudo ip netns exec r3 ip addr add 10.0.34.1/30 dev veth_r3_r4
sudo ip netns exec r4 ip addr add 10.0.34.2/30 dev veth_r4_r3


# ---------------------------------------------------------------------
# 6. PONER RUTAS
#    metric 100 = camino principal,  metric 200 = camino de respaldo
# ---------------------------------------------------------------------
# PCs
sudo ip netns exec pc1 ip route add default via 192.168.1.1
sudo ip netns exec pc2 ip route add default via 192.168.2.1

# r1: hacia la red B, primero por r2 y si no por r3
sudo ip netns exec r1 ip route add 192.168.2.0/24 via 10.0.12.2 metric 100
sudo ip netns exec r1 ip route add 192.168.2.0/24 via 10.0.13.2 metric 200

# r2: red A por r1 (o por r3);  red B por r4 (o por r3)
sudo ip netns exec r2 ip route add 192.168.1.0/24 via 10.0.12.1 metric 100
sudo ip netns exec r2 ip route add 192.168.1.0/24 via 10.0.23.2 metric 200
sudo ip netns exec r2 ip route add 192.168.2.0/24 via 10.0.24.2 metric 100
sudo ip netns exec r2 ip route add 192.168.2.0/24 via 10.0.23.2 metric 200

# r3: red A por r1 (o por r2);  red B por r4 (o por r2)
sudo ip netns exec r3 ip route add 192.168.1.0/24 via 10.0.13.1 metric 100
sudo ip netns exec r3 ip route add 192.168.1.0/24 via 10.0.23.1 metric 200
sudo ip netns exec r3 ip route add 192.168.2.0/24 via 10.0.34.1 metric 100
sudo ip netns exec r3 ip route add 192.168.2.0/24 via 10.0.23.1 metric 200

# r4: hacia la red A, primero por r2 y si no por r3
sudo ip netns exec r4 ip route add 192.168.1.0/24 via 10.0.24.1 metric 100
sudo ip netns exec r4 ip route add 192.168.1.0/24 via 10.0.34.1 metric 200


# ---------------------------------------------------------------------
# 7. ACTIVAR LOS ROUTERS
#    - ip_forward: reenviar paquetes.
#    - ignore_routes_with_linkdown: no usar rutas por cables muertos.
# ---------------------------------------------------------------------
sudo ip netns exec r1 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r2 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r3 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r4 sysctl -w net.ipv4.ip_forward=1

sudo ip netns exec r1 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1
sudo ip netns exec r2 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1
sudo ip netns exec r3 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1
sudo ip netns exec r4 sysctl -w net.ipv4.conf.all.ignore_routes_with_linkdown=1


# ---------------------------------------------------------------------
# 8. COMPROBACIONES (todo funcionando)
# ---------------------------------------------------------------------
echo "== Rutas de r1 (fíjate en las dos rutas a 192.168.2.0/24) =="
sudo ip netns exec r1 ip route

echo "== pc1 -> pc2 por el camino principal (r1 -> r2 -> r4) =="
sudo ip netns exec pc1 ping -c 2 192.168.2.10
sudo ip netns exec pc1 tracepath -n 192.168.2.10


# ---------------------------------------------------------------------
# 9. SIMULAR UNA AVERÍA: se cae el enlace r1 <-> r2
# ---------------------------------------------------------------------
sudo ip netns exec r1 ip link set down dev veth_r1_r2

echo "== Rutas de r1 tras la avería (solo queda la de respaldo) =="
sudo ip netns exec r1 ip route

echo "== pc1 -> pc2 por el camino de respaldo (r1 -> r3 -> r4) =="
sudo ip netns exec pc1 ping -c 2 192.168.2.10
sudo ip netns exec pc1 tracepath -n 192.168.2.10


# ---------------------------------------------------------------------
# 10. REPARAR EL ENLACE
#    Al encender la interfaz, la ruta estática que el kernel borró
#    NO vuelve sola: hay que volver a ponerla.
# ---------------------------------------------------------------------
sudo ip netns exec r1 ip link set up dev veth_r1_r2
sudo ip netns exec r1 ip route add 192.168.2.0/24 via 10.0.12.2 metric 100

echo "== Rutas de r1 reparadas =="
sudo ip netns exec r1 ip route
