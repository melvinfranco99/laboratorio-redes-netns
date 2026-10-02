#!/bin/sh
# =====================================================================
#  FASE 1:  PC  <---->  PC
# =====================================================================
#  OBJETIVO: conectar dos ordenadores directamente con un cable.
#
#      [pc1] 10.0.0.1 ======================= 10.0.0.2 [pc2]
#             veth_pc1_pc2         veth_pc2_pc1
#
#  CONCEPTOS:
#   - Network namespace (netns): una "caja" con su propia pila de red
#     (interfaces, IPs, rutas, firewall). Cada netns es un PC.
#   - veth: un cable virtual con dos extremos. Lo que entra por uno
#     sale por el otro.
#
#  EJECUCIÓN:  sh 01_pc_pc.sh
# =====================================================================


# ---------------------------------------------------------------------
# 0. LIMPIEZA
#    Borramos todo lo que haya quedado de otras fases para empezar
#    desde cero (servicios, namespaces, bridges y archivos del lab).
# ---------------------------------------------------------------------
sudo pkill -f "/tmp/la[b]"    # para servicios del lab (el [b] evita que pkill se mate a sí mismo)
sudo ip -all netns delete
sudo ip link del sw1 2>/dev/null
sudo ip link del sw2 2>/dev/null
sudo ip link del inet 2>/dev/null


# ---------------------------------------------------------------------
# 1. CREACIÓN DE DISPOSITIVOS
#    Cada "ip netns add" crea un PC vacío (solo tiene la interfaz lo).
# ---------------------------------------------------------------------
sudo ip netns add pc1
sudo ip netns add pc2


# ---------------------------------------------------------------------
# 2. CREACIÓN DEL CABLEADO
#    Creamos un cable (par veth). Sus dos extremos se crean en el host.
# ---------------------------------------------------------------------
sudo ip link add veth_pc1_pc2 type veth peer name veth_pc2_pc1


# ---------------------------------------------------------------------
# 3. CONEXIÓN DEL CABLEADO
#    Movemos cada extremo del cable dentro de su PC.
#    Desde este momento el host ya no ve esas interfaces.
# ---------------------------------------------------------------------
sudo ip link set veth_pc1_pc2 netns pc1
sudo ip link set veth_pc2_pc1 netns pc2


# ---------------------------------------------------------------------
# 4. DAR DE ALTA LAS INTERFACES
#    Las interfaces nacen apagadas (DOWN). Las encendemos.
#    "lo" (loopback, 127.0.0.1) también hay que encenderla.
#    "ip netns exec pc1 <comando>" = ejecutar <comando> dentro de pc1.
# ---------------------------------------------------------------------
sudo ip netns exec pc1 ip link set up dev lo
sudo ip netns exec pc2 ip link set up dev lo
sudo ip netns exec pc1 ip link set up dev veth_pc1_pc2
sudo ip netns exec pc2 ip link set up dev veth_pc2_pc1


# ---------------------------------------------------------------------
# 5. PONER IPs
#    Los dos PCs están en la misma red (10.0.0.0/24), así que se ven
#    directamente sin necesidad de router.
# ---------------------------------------------------------------------
sudo ip netns exec pc1 ip addr add 10.0.0.1/24 dev veth_pc1_pc2
sudo ip netns exec pc2 ip addr add 10.0.0.2/24 dev veth_pc2_pc1


# ---------------------------------------------------------------------
# 6. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== Namespaces creados =="
sudo ip netns list

echo "== IPs de pc1 =="
sudo ip netns exec pc1 ip addr show dev veth_pc1_pc2

echo "== pc1 hace ping a pc2 =="
sudo ip netns exec pc1 ping -c 3 10.0.0.2

echo "== Tabla ARP de pc1 (MAC aprendida de pc2) =="
sudo ip netns exec pc1 ip neigh show
