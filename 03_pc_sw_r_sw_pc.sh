#!/bin/sh
# =====================================================================
#  FASE 3:  PC  ----  SW  ----  ROUTER  ----  SW  ----  PC
# =====================================================================
#  OBJETIVO: unir DOS redes distintas con un router.
#
#     RED A: 192.168.1.0/24                 RED B: 192.168.2.0/24
#
#  [pc1]------[sw1]------[ r1 ]------[sw2]------[pc2]
#  .1.10              .1.1    .2.1              .2.10
#
#  CONCEPTOS:
#   - Un router es un PC con dos (o más) interfaces y con el
#     reenvío de paquetes activado (ip_forward = 1).
#   - Puerta de enlace (gateway): cuando un PC quiere hablar con
#     otra red, le manda el paquete al router. Eso se configura con
#     una ruta "default".
#
#  EJECUCIÓN:  sh 03_pc_sw_r_sw_pc.sh
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
sudo ip link add sw1 type bridge
sudo ip link add sw2 type bridge


# ---------------------------------------------------------------------
# 2. CREACIÓN DEL CABLEADO
#    pc1 <-> sw1,  sw1 <-> r1,  r1 <-> sw2,  sw2 <-> pc2
# ---------------------------------------------------------------------
sudo ip link add veth_pc1_sw1 type veth peer name veth_sw1_pc1
sudo ip link add veth_r1_sw1 type veth peer name veth_sw1_r1
sudo ip link add veth_r1_sw2 type veth peer name veth_sw2_r1
sudo ip link add veth_pc2_sw2 type veth peer name veth_sw2_pc2


# ---------------------------------------------------------------------
# 3. CONEXIÓN DEL CABLEADO
# ---------------------------------------------------------------------
# Extremos que van dentro de los PCs y del router
sudo ip link set veth_pc1_sw1 netns pc1
sudo ip link set veth_pc2_sw2 netns pc2
sudo ip link set veth_r1_sw1 netns r1
sudo ip link set veth_r1_sw2 netns r1

# Extremos que se enchufan a los switches
sudo ip link set veth_sw1_pc1 master sw1
sudo ip link set veth_sw1_r1 master sw1
sudo ip link set veth_sw2_pc2 master sw2
sudo ip link set veth_sw2_r1 master sw2


# ---------------------------------------------------------------------
# 4. DAR DE ALTA LAS INTERFACES
# ---------------------------------------------------------------------
# Switches y sus puertos (en el host)
sudo ip link set up dev sw1
sudo ip link set up dev sw2
sudo ip link set up dev veth_sw1_pc1
sudo ip link set up dev veth_sw1_r1
sudo ip link set up dev veth_sw2_pc2
sudo ip link set up dev veth_sw2_r1

# PCs
sudo ip netns exec pc1 ip link set up dev lo
sudo ip netns exec pc2 ip link set up dev lo
sudo ip netns exec pc1 ip link set up dev veth_pc1_sw1
sudo ip netns exec pc2 ip link set up dev veth_pc2_sw2

# Router
sudo ip netns exec r1 ip link set up dev lo
sudo ip netns exec r1 ip link set up dev veth_r1_sw1
sudo ip netns exec r1 ip link set up dev veth_r1_sw2


# ---------------------------------------------------------------------
# 5. PONER IPs
#    El router tiene una IP en cada red (la .1 por convención).
# ---------------------------------------------------------------------
sudo ip netns exec pc1 ip addr add 192.168.1.10/24 dev veth_pc1_sw1
sudo ip netns exec pc2 ip addr add 192.168.2.10/24 dev veth_pc2_sw2
sudo ip netns exec r1 ip addr add 192.168.1.1/24 dev veth_r1_sw1
sudo ip netns exec r1 ip addr add 192.168.2.1/24 dev veth_r1_sw2


# ---------------------------------------------------------------------
# 6. PONER RUTAS (puerta de enlace de cada PC)
#    "Todo lo que no sea de mi red, mándaselo al router".
#    El router no necesita rutas: conoce las dos redes porque está
#    conectado directamente a ellas.
# ---------------------------------------------------------------------
sudo ip netns exec pc1 ip route add default via 192.168.1.1
sudo ip netns exec pc2 ip route add default via 192.168.2.1


# ---------------------------------------------------------------------
# 7. ACTIVAR EL ROUTER
#    Sin esto r1 recibe los paquetes pero no los reenvía.
# ---------------------------------------------------------------------
sudo ip netns exec r1 sysctl -w net.ipv4.ip_forward=1


# ---------------------------------------------------------------------
# 8. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== Tabla de rutas de pc1 =="
sudo ip netns exec pc1 ip route

echo "== Tabla de rutas de r1 =="
sudo ip netns exec r1 ip route

echo "== pc1 hace ping a su gateway =="
sudo ip netns exec pc1 ping -c 2 192.168.1.1

echo "== pc1 hace ping a pc2 (otra red) =="
sudo ip netns exec pc1 ping -c 3 192.168.2.10

echo "== Camino que siguen los paquetes de pc1 a pc2 =="
sudo ip netns exec pc1 tracepath -n 192.168.2.10
