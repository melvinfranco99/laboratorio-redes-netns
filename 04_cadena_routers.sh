#!/bin/sh
# =====================================================================
#  FASE 4:  PC - SW - R1 - R2 - R3 - R4 - SW - PC
# =====================================================================
#  OBJETIVO: poner VARIOS routers en cadena. Ahora un router ya no
#            conoce todas las redes, así que hay que enseñarle el
#            camino con RUTAS ESTÁTICAS.
#
#   RED A                                                   RED B
#  192.168.1.0/24                                      192.168.2.0/24
#
#  [pc1]--[sw1]--[r1]-----[r2]-----[r3]-----[r4]--[sw2]--[pc2]
#   .1.10    .1.1  .1   .2  .1   .2  .1   .2  .2.1     .2.10
#                  10.0.12.0/30  10.0.23.0/30  10.0.34.0/30
#
#  CONCEPTOS:
#   - Enlaces punto a punto entre routers: redes /30 (solo 2 IPs
#     útiles, una para cada extremo).
#   - Ruta estática: "para llegar a la red X, mándalo al router Y".
#   - IMPORTANTE: hacen falta rutas de IDA y de VUELTA.
#
#  EJECUCIÓN:  sh 04_cadena_routers.sh
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
# Cadena de routers
sudo ip link add veth_r1_r2 type veth peer name veth_r2_r1
sudo ip link add veth_r2_r3 type veth peer name veth_r3_r2
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

# Routers
sudo ip link set veth_r1_sw1 netns r1
sudo ip link set veth_r1_r2 netns r1
sudo ip link set veth_r2_r1 netns r2
sudo ip link set veth_r2_r3 netns r2
sudo ip link set veth_r3_r2 netns r3
sudo ip link set veth_r3_r4 netns r3
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

# Routers
sudo ip netns exec r1 ip link set up dev lo
sudo ip netns exec r2 ip link set up dev lo
sudo ip netns exec r3 ip link set up dev lo
sudo ip netns exec r4 ip link set up dev lo
sudo ip netns exec r1 ip link set up dev veth_r1_sw1
sudo ip netns exec r1 ip link set up dev veth_r1_r2
sudo ip netns exec r2 ip link set up dev veth_r2_r1
sudo ip netns exec r2 ip link set up dev veth_r2_r3
sudo ip netns exec r3 ip link set up dev veth_r3_r2
sudo ip netns exec r3 ip link set up dev veth_r3_r4
sudo ip netns exec r4 ip link set up dev veth_r4_r3
sudo ip netns exec r4 ip link set up dev veth_r4_sw2


# ---------------------------------------------------------------------
# 5. PONER IPs
# ---------------------------------------------------------------------
# Red A
sudo ip netns exec pc1 ip addr add 192.168.1.10/24 dev veth_pc1_sw1
sudo ip netns exec r1 ip addr add 192.168.1.1/24 dev veth_r1_sw1

# Enlace r1 <-> r2  (10.0.12.0/30)
sudo ip netns exec r1 ip addr add 10.0.12.1/30 dev veth_r1_r2
sudo ip netns exec r2 ip addr add 10.0.12.2/30 dev veth_r2_r1

# Enlace r2 <-> r3  (10.0.23.0/30)
sudo ip netns exec r2 ip addr add 10.0.23.1/30 dev veth_r2_r3
sudo ip netns exec r3 ip addr add 10.0.23.2/30 dev veth_r3_r2

# Enlace r3 <-> r4  (10.0.34.0/30)
sudo ip netns exec r3 ip addr add 10.0.34.1/30 dev veth_r3_r4
sudo ip netns exec r4 ip addr add 10.0.34.2/30 dev veth_r4_r3

# Red B
sudo ip netns exec r4 ip addr add 192.168.2.1/24 dev veth_r4_sw2
sudo ip netns exec pc2 ip addr add 192.168.2.10/24 dev veth_pc2_sw2


# ---------------------------------------------------------------------
# 6. PONER RUTAS
# ---------------------------------------------------------------------
# PCs: su puerta de enlace
sudo ip netns exec pc1 ip route add default via 192.168.1.1
sudo ip netns exec pc2 ip route add default via 192.168.2.1

# IDA (hacia la red B 192.168.2.0/24): cada router se lo pasa al siguiente
sudo ip netns exec r1 ip route add 192.168.2.0/24 via 10.0.12.2
sudo ip netns exec r2 ip route add 192.168.2.0/24 via 10.0.23.2
sudo ip netns exec r3 ip route add 192.168.2.0/24 via 10.0.34.2

# VUELTA (hacia la red A 192.168.1.0/24): cada router se lo pasa al anterior
sudo ip netns exec r4 ip route add 192.168.1.0/24 via 10.0.34.1
sudo ip netns exec r3 ip route add 192.168.1.0/24 via 10.0.23.1
sudo ip netns exec r2 ip route add 192.168.1.0/24 via 10.0.12.1


# ---------------------------------------------------------------------
# 7. ACTIVAR LOS ROUTERS
# ---------------------------------------------------------------------
sudo ip netns exec r1 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r2 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r3 sysctl -w net.ipv4.ip_forward=1
sudo ip netns exec r4 sysctl -w net.ipv4.ip_forward=1


# ---------------------------------------------------------------------
# 8. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== Rutas de r2 (un router del medio) =="
sudo ip netns exec r2 ip route

echo "== pc1 hace ping a pc2 atravesando 4 routers =="
sudo ip netns exec pc1 ping -c 3 192.168.2.10

echo "== Saltos de pc1 a pc2 (deben salir r1, r2, r3, r4 y pc2) =="
sudo ip netns exec pc1 tracepath -n 192.168.2.10
