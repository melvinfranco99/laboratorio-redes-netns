#!/bin/sh
# =====================================================================
#  FASE 2:  PC  ----  SWITCH  ----  PC
# =====================================================================
#  OBJETIVO: en vez de un cable directo, conectar los PCs a un switch.
#            Así podríamos enchufar todos los PCs que quisiéramos.
#
#      [pc1] 192.168.1.10                     192.168.1.20 [pc2]
#         |                                          |
#    veth_pc1_sw1                              veth_pc2_sw1
#         |                                          |
#    veth_sw1_pc1 ---------[ sw1 ]---------- veth_sw1_pc2
#                         (bridge)
#
#  CONCEPTOS:
#   - Bridge: un switch virtual de capa 2. Aprende las MAC de lo que
#     tiene conectado y reenvía las tramas al puerto correcto.
#   - El switch lo creamos en el host (no necesita IP).
#
#  EJECUCIÓN:  sh 02_pc_sw_pc.sh
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
#    Dos PCs (namespaces) y un switch (bridge).
# ---------------------------------------------------------------------
sudo ip netns add pc1
sudo ip netns add pc2
sudo ip link add sw1 type bridge


# ---------------------------------------------------------------------
# 2. CREACIÓN DEL CABLEADO
#    Un cable por cada PC, que va del PC al switch.
# ---------------------------------------------------------------------
sudo ip link add veth_pc1_sw1 type veth peer name veth_sw1_pc1
sudo ip link add veth_pc2_sw1 type veth peer name veth_sw1_pc2


# ---------------------------------------------------------------------
# 3. CONEXIÓN DEL CABLEADO
#    - El extremo "pc" entra dentro del PC.
#    - El extremo "sw" se enchufa al switch con "master sw1".
# ---------------------------------------------------------------------
sudo ip link set veth_pc1_sw1 netns pc1
sudo ip link set veth_pc2_sw1 netns pc2
sudo ip link set veth_sw1_pc1 master sw1
sudo ip link set veth_sw1_pc2 master sw1


# ---------------------------------------------------------------------
# 4. DAR DE ALTA LAS INTERFACES
#    Encendemos el switch, sus puertos y las interfaces de los PCs.
# ---------------------------------------------------------------------
sudo ip link set up dev sw1
sudo ip link set up dev veth_sw1_pc1
sudo ip link set up dev veth_sw1_pc2

sudo ip netns exec pc1 ip link set up dev lo
sudo ip netns exec pc2 ip link set up dev lo
sudo ip netns exec pc1 ip link set up dev veth_pc1_sw1
sudo ip netns exec pc2 ip link set up dev veth_pc2_sw1


# ---------------------------------------------------------------------
# 5. PONER IPs
#    Misma red (192.168.1.0/24): el switch no necesita IP, solo
#    reenvía tramas.
# ---------------------------------------------------------------------
sudo ip netns exec pc1 ip addr add 192.168.1.10/24 dev veth_pc1_sw1
sudo ip netns exec pc2 ip addr add 192.168.1.20/24 dev veth_pc2_sw1


# ---------------------------------------------------------------------
# 6. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== Puertos conectados al switch sw1 =="
ip link show master sw1

echo "== pc1 hace ping a pc2 a través del switch =="
sudo ip netns exec pc1 ping -c 3 192.168.1.20

echo "== Tabla MAC del switch (MACs aprendidas en cada puerto) =="
bridge fdb show br sw1 | grep -v permanent
