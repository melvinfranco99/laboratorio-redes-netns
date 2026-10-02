#!/bin/sh
# =====================================================================
#  FASE 9:  AÑADIR SERVIDORES WEB
# =====================================================================
#  OBJETIVO: montar dos webs:
#   1) Una web PÚBLICA en Internet (web.melvin.lab -> 203.0.113.80)
#   2) Una INTRANET dentro de la red A, en pc1 (192.168.1.10)
#      que solo se ve desde dentro de nuestra red.
#
#                    INTERNET SIMULADO (203.0.113.0/24)
#     [srv1] .10 --+
#     [dns ] .53 --+--[ inet ]--- [ isp ] --- r1 ... red de routers
#     [web ] .80 --+                          |
#                                        [pc1] intranet (192.168.1.10:80)
#
#  CONCEPTOS:
#   - Servidor web: programa que escucha en el puerto TCP 80 y
#     responde con páginas HTML (protocolo HTTP).
#     Usamos el de python:  python3 -m http.server
#   - Registro DNS: añadimos web.melvin.lab a nuestra zona y le
#     decimos a dnsmasq que la vuelva a leer (señal HUP).
#
#  REQUISITOS: fases 6, 7 y 8 ejecutadas.  python3 y curl.
#
#  EJECUCIÓN:  sh 09_web.sh
# =====================================================================


# ---------------------------------------------------------------------
# 1. CREACIÓN DEL SERVIDOR WEB PÚBLICO
# ---------------------------------------------------------------------
sudo ip netns add web


# ---------------------------------------------------------------------
# 2. CABLEADO: web <-> switch de Internet
# ---------------------------------------------------------------------
sudo ip link add veth_web_inet type veth peer name veth_inet_web
sudo ip link set veth_web_inet netns web
sudo ip link set veth_inet_web master inet


# ---------------------------------------------------------------------
# 3. DAR DE ALTA, IP Y RUTA
# ---------------------------------------------------------------------
sudo ip link set up dev veth_inet_web
sudo ip netns exec web ip link set up dev lo
sudo ip netns exec web ip link set up dev veth_web_inet
sudo ip netns exec web ip addr add 203.0.113.80/24 dev veth_web_inet
sudo ip netns exec web ip route add default via 203.0.113.1


# ---------------------------------------------------------------------
# 4. CONTENIDO DE LAS WEBS
#    Cada web es una carpeta con un index.html.
# ---------------------------------------------------------------------
sudo mkdir -p /tmp/lab/web /tmp/lab/intranet
echo "<h1>Web publica de melvin.lab (203.0.113.80)</h1>" | sudo tee /tmp/lab/web/index.html
echo "<h1>Intranet de la red A (pc1 - 192.168.1.10)</h1>" | sudo tee /tmp/lab/intranet/index.html


# ---------------------------------------------------------------------
# 5. ARRANCAR LOS SERVIDORES WEB (en segundo plano con &)
#    --bind       IP en la que escucha
#    --directory  carpeta que publica
#    El log (quién entra a la web) se guarda en /tmp/lab/*.log
# ---------------------------------------------------------------------
sudo ip netns exec web python3 -m http.server 80 --bind 203.0.113.80 --directory /tmp/lab/web > /tmp/lab/web.log 2>&1 &
sudo ip netns exec pc1 python3 -m http.server 80 --bind 192.168.1.10 --directory /tmp/lab/intranet > /tmp/lab/intranet.log 2>&1 &

# Esperamos un segundo a que arranquen
sleep 2


# ---------------------------------------------------------------------
# 6. AÑADIR LOS NOMBRES AL DNS
#    Añadimos las líneas a la zona y avisamos a dnsmasq con HUP
#    para que relea el archivo sin reiniciarse.
# ---------------------------------------------------------------------
echo "203.0.113.80   web.melvin.lab"      | sudo tee -a /tmp/lab/dns-hosts
echo "192.168.1.10   intranet.melvin.lab" | sudo tee -a /tmp/lab/dns-hosts
sudo kill -HUP $(cat /tmp/lab/dnsmasq-dns.pid)


# ---------------------------------------------------------------------
# 7. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== ¿Qué puertos están escuchando en el servidor web? =="
sudo ip netns exec web ss -tlnp

echo "== El DNS ya conoce web.melvin.lab =="
sudo ip netns exec pc2 dig +short web.melvin.lab

echo "== pc2 visita la web pública =="
sudo ip netns exec pc2 curl -s http://203.0.113.80

echo "== pc3 visita la web pública por nombre =="
# Si tu host usa systemd-resolved y esto falla, usa la IP como arriba.
sudo ip netns exec pc3 curl -s http://web.melvin.lab

echo "== srv1 (desde Internet) visita la web pública =="
sudo ip netns exec srv1 curl -s http://203.0.113.80

echo "== pc2 (red B) visita la intranet de pc1: FUNCIONA, es nuestra red =="
sudo ip netns exec pc2 curl -s http://192.168.1.10

echo "== srv1 (Internet) intenta ver la intranet: DEBE FALLAR =="
sudo ip netns exec srv1 curl -s --max-time 3 http://192.168.1.10
echo "(sin respuesta: la intranet no es accesible desde Internet)"

echo "== Log de la web pública: IPs de los visitantes =="
# pc2 y pc3 aparecen como 198.51.100.2 (NAT de r1); srv1 con su IP.
cat /tmp/lab/web.log
