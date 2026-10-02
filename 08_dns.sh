#!/bin/sh
# =====================================================================
#  FASE 8:  AÑADIR DNS
# =====================================================================
#  OBJETIVO: poder usar NOMBRES (srv1.melvin.lab) en vez de IPs.
#            Montamos un servidor DNS público en el Internet simulado.
#
#                    INTERNET SIMULADO (203.0.113.0/24)
#     [srv1] .10 ---+
#                   [ inet ]--- .1 [ isp ] ---> r1 ---> nuestras redes
#     [dns ] .53 ---+
#       |
#       +--> para nombres que no conoce (google.com...) pregunta a 8.8.8.8
#
#  CONCEPTOS:
#   - Servidor DNS: traduce nombres a IPs.
#   - Zona propia: nombres que el servidor conoce él mismo
#     (*.melvin.lab), apuntados en un archivo tipo /etc/hosts.
#   - Reenviador (forwarder): lo que no conoce se lo pregunta a otro
#     DNS (8.8.8.8) y nos devuelve la respuesta.
#   - /etc/resolv.conf: dice a cada PC qué DNS usar. Para dar uno
#     distinto a cada namespace se crea /etc/netns/<nombre>/resolv.conf
#     y "ip netns exec" lo coloca automáticamente en su lugar.
#
#  REQUISITOS: fases 6 y 7 ejecutadas.
#              sudo pacman -S dnsmasq bind      (bind trae el comando dig)
#
#  EJECUCIÓN:  sh 08_dns.sh
# =====================================================================


# ---------------------------------------------------------------------
# 1. CREACIÓN DEL SERVIDOR DNS (otro equipo en Internet)
# ---------------------------------------------------------------------
sudo ip netns add dns


# ---------------------------------------------------------------------
# 2. CABLEADO: dns <-> switch de Internet
# ---------------------------------------------------------------------
sudo ip link add veth_dns_inet type veth peer name veth_inet_dns
sudo ip link set veth_dns_inet netns dns
sudo ip link set veth_inet_dns master inet


# ---------------------------------------------------------------------
# 3. DAR DE ALTA, IP Y RUTA
#    IP pública 203.0.113.53 (el 53 es el puerto del DNS, fácil de
#    recordar). Su gateway es el ISP.
# ---------------------------------------------------------------------
sudo ip link set up dev veth_inet_dns
sudo ip netns exec dns ip link set up dev lo
sudo ip netns exec dns ip link set up dev veth_dns_inet
sudo ip netns exec dns ip addr add 203.0.113.53/24 dev veth_dns_inet
sudo ip netns exec dns ip route add default via 203.0.113.1


# ---------------------------------------------------------------------
# 4. NUESTRA ZONA: los nombres que conoce el servidor
#    Formato:  IP   nombre
# ---------------------------------------------------------------------
echo "203.0.113.1    isp.melvin.lab"  | sudo tee    /tmp/lab/dns-hosts
echo "203.0.113.10   srv1.melvin.lab" | sudo tee -a /tmp/lab/dns-hosts
echo "203.0.113.53   dns.melvin.lab"  | sudo tee -a /tmp/lab/dns-hosts
echo "198.51.100.2   r1.melvin.lab"   | sudo tee -a /tmp/lab/dns-hosts


# ---------------------------------------------------------------------
# 5. ARRANCAR EL SERVIDOR DNS (dnsmasq)
#    Opciones:
#     --no-resolv / --no-hosts     no usar la configuración del host
#     --addn-hosts                 nuestra zona (paso 4)
#     --server=8.8.8.8             reenviador para el resto de nombres
#     --listen-address             escuchar en su IP pública
#     --log-queries                apuntar cada consulta en el log
# ---------------------------------------------------------------------
sudo ip netns exec dns dnsmasq \
    --conf-file=/dev/null \
    --user=root \
    --no-resolv \
    --no-hosts \
    --addn-hosts=/tmp/lab/dns-hosts \
    --server=8.8.8.8 \
    --listen-address=203.0.113.53 \
    --bind-interfaces \
    --log-queries \
    --log-facility=/tmp/lab/dns.log \
    --pid-file=/tmp/lab/dnsmasq-dns.pid


# ---------------------------------------------------------------------
# 6. DECIR A CADA PC QUÉ DNS USAR
#    pc1 y pc2 tienen IP fija -> se lo ponemos a mano.
#    pc3 y pc4 ya lo recibieron por DHCP (fase 7), pero en la fase 7
#    le dijimos a dhcpcd que no tocara resolv.conf, así que también
#    se lo ponemos aquí.
# ---------------------------------------------------------------------
sudo mkdir -p /etc/netns/pc1 /etc/netns/pc2 /etc/netns/pc3 /etc/netns/pc4
echo "nameserver 203.0.113.53" | sudo tee /etc/netns/pc1/resolv.conf
echo "nameserver 203.0.113.53" | sudo tee /etc/netns/pc2/resolv.conf
echo "nameserver 203.0.113.53" | sudo tee /etc/netns/pc3/resolv.conf
echo "nameserver 203.0.113.53" | sudo tee /etc/netns/pc4/resolv.conf


# ---------------------------------------------------------------------
# 7. COMPROBACIONES
#    Usamos "dig" porque lee directamente el /etc/resolv.conf.
#    (ping/curl con nombres pueden saltarse este archivo si tu host
#     usa systemd-resolved; dig no.)
# ---------------------------------------------------------------------
echo "== resolv.conf que ve pc1 (distinto al del host) =="
sudo ip netns exec pc1 cat /etc/resolv.conf

echo "== pc1 pregunta por srv1.melvin.lab (nombre de nuestra zona) =="
sudo ip netns exec pc1 dig +short srv1.melvin.lab

echo "== pc2 pregunta por r1.melvin.lab =="
sudo ip netns exec pc2 dig +short r1.melvin.lab

echo "== pc3 pregunta por archlinux.org (lo reenvía a 8.8.8.8) =="
sudo ip netns exec pc3 dig +short archlinux.org

echo "== Respuesta completa (fíjate en la línea SERVER: 203.0.113.53) =="
sudo ip netns exec pc4 dig srv1.melvin.lab

# Todas las consultas llegan desde 198.51.100.2: es el NAT de r1.
echo "== Log del servidor DNS: quién preguntó qué =="
sudo cat /tmp/lab/dns.log
