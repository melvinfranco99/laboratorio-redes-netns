#!/bin/sh
# =====================================================================
#  FASE 11:  AÑADIR REGLAS DE IPTABLES (CORTAFUEGOS)
# =====================================================================
#  OBJETIVO: proteger la red. Hasta ahora todo estaba permitido.
#            Ponemos dos cortafuegos:
#
#   1) r1 (router frontera): decide qué entra y qué sale de la red.
#   2) web (servidor público): solo deja ver la web (puerto 80).
#
#  POLÍTICA DE r1:
#   - La red A puede ir a cualquier sitio.
#   - La red B puede ir a Internet, y a la red A solo ping y web.
#   - La VPN (wg0) puede entrar a todas las redes privadas.
#   - Desde Internet NO se entra, salvo:
#       * la VPN (UDP 51820)
#       * la intranet de pc1, publicada en 198.51.100.2:8080
#         (port forwarding / DNAT)
#
#  CONCEPTOS:
#   - Cadenas: INPUT (para el propio equipo), FORWARD (lo que el
#     router reenvía), OUTPUT (lo que sale del propio equipo).
#   - Política (-P): qué pasa con lo que no cumple ninguna regla.
#     Usamos DROP: "todo prohibido salvo lo permitido".
#   - Las reglas se leen de arriba abajo: gana la primera que coincide.
#   - ESTABLISHED,RELATED: dejar pasar las RESPUESTAS de conexiones
#     ya permitidas.
#   - DNAT: cambiar el DESTINO de un paquete (publicar un servicio
#     interno). Es lo contrario del MASQUERADE de la fase 6.
#
#  REQUISITOS: fases 6 a 10 ejecutadas.
#
#  EJECUCIÓN:  sh 11_iptables.sh
# =====================================================================


# ---------------------------------------------------------------------
# 1. r1: EMPEZAR DE CERO
#    -F borra las reglas de la tabla filter (la normal).
#    La tabla nat NO la tocamos: el MASQUERADE de la fase 6 sigue.
# ---------------------------------------------------------------------
sudo ip netns exec r1 iptables -F


# ---------------------------------------------------------------------
# 2. r1: CADENA INPUT (tráfico dirigido al propio router)
# ---------------------------------------------------------------------
# Todo prohibido por defecto
sudo ip netns exec r1 iptables -P INPUT DROP
# Su propio loopback
sudo ip netns exec r1 iptables -A INPUT -i lo -j ACCEPT
# Respuestas a lo que el router ha pedido
sudo ip netns exec r1 iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
# Ping (útil para diagnosticar)
sudo ip netns exec r1 iptables -A INPUT -p icmp -j ACCEPT
# Peticiones DHCP de la red A (fase 7)
sudo ip netns exec r1 iptables -A INPUT -i veth_r1_sw1 -p udp --dport 67 -j ACCEPT
# Conexiones VPN que llegan desde Internet (fase 10)
sudo ip netns exec r1 iptables -A INPUT -i veth_r1_isp -p udp --dport 51820 -j ACCEPT


# ---------------------------------------------------------------------
# 3. r1: CADENA FORWARD (tráfico que el router reenvía)
#    Recordatorio de por dónde llega cada red a r1:
#     red A   -> veth_r1_sw1
#     red B   -> veth_r1_r2 o veth_r1_r3 (a través de la red de routers)
#     Internet-> veth_r1_isp
#     VPN     -> wg0
# ---------------------------------------------------------------------
# Todo prohibido por defecto
sudo ip netns exec r1 iptables -P FORWARD DROP
# Respuestas de conexiones ya permitidas
sudo ip netns exec r1 iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Red A: puede ir a cualquier sitio
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_sw1 -j ACCEPT

# Red B -> Internet: permitido
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_r2 -o veth_r1_isp -j ACCEPT
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_r3 -o veth_r1_isp -j ACCEPT

# Red B -> Red A: solo ping y web (TCP 80)
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_r2 -o veth_r1_sw1 -p icmp -j ACCEPT
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_r3 -o veth_r1_sw1 -p icmp -j ACCEPT
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_r2 -o veth_r1_sw1 -p tcp --dport 80 -j ACCEPT
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_r3 -o veth_r1_sw1 -p tcp --dport 80 -j ACCEPT

# VPN: el usuario de casa entra a todo
sudo ip netns exec r1 iptables -A FORWARD -i wg0 -j ACCEPT

# Internet -> intranet de pc1, SOLO si viene del port forwarding (paso 4)
sudo ip netns exec r1 iptables -A FORWARD -i veth_r1_isp -o veth_r1_sw1 -d 192.168.1.10 -p tcp --dport 80 -m conntrack --ctstate DNAT -j ACCEPT


# ---------------------------------------------------------------------
# 4. r1: PORT FORWARDING (DNAT)
#    Quien entre a 198.51.100.2:8080 llega en realidad a
#    192.168.1.10:80 (la intranet de pc1).
# ---------------------------------------------------------------------
sudo ip netns exec r1 iptables -t nat -A PREROUTING -i veth_r1_isp -p tcp --dport 8080 -j DNAT --to-destination 192.168.1.10:80


# ---------------------------------------------------------------------
# 5. SERVIDOR web: un "panel de administración" que NO debe verse
#    Arrancamos otro servidor en el puerto 8000. Sin cortafuegos
#    cualquiera de Internet podría entrar.
# ---------------------------------------------------------------------
sudo mkdir -p /tmp/lab/admin
echo "<h1>PANEL DE ADMINISTRACION (privado)</h1>" | sudo tee /tmp/lab/admin/index.html
sudo ip netns exec web python3 -m http.server 8000 --directory /tmp/lab/admin > /tmp/lab/admin.log 2>&1 &
sleep 2

echo "== SIN cortafuegos: srv1 entra al panel de admin de web (MAL) =="
sudo ip netns exec srv1 curl -s --max-time 3 http://203.0.113.80:8000


# ---------------------------------------------------------------------
# 6. SERVIDOR web: CORTAFUEGOS (cadena INPUT)
#    Solo se permite la web (80) y el ping. El panel (8000) solo
#    se puede usar desde el propio servidor (lo).
# ---------------------------------------------------------------------
sudo ip netns exec web iptables -F
sudo ip netns exec web iptables -P INPUT DROP
sudo ip netns exec web iptables -A INPUT -i lo -j ACCEPT
sudo ip netns exec web iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo ip netns exec web iptables -A INPUT -p icmp -j ACCEPT
sudo ip netns exec web iptables -A INPUT -p tcp --dport 80 -j ACCEPT


# ---------------------------------------------------------------------
# 7. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== [OK] pc1 (red A) -> Internet =="
sudo ip netns exec pc1 ping -c 2 8.8.8.8

echo "== [OK] pc2 (red B) -> web pública =="
sudo ip netns exec pc2 curl -s http://203.0.113.80

echo "== [OK] pc2 (red B) -> intranet de pc1 (puerto 80 permitido) =="
sudo ip netns exec pc2 curl -s http://192.168.1.10

echo "== [BLOQUEADO] pc2 (red B) -> pc1 puerto 22 =="
# Se queda esperando hasta el timeout: DROP no contesta nada.
# (Sin cortafuegos diría "Connection refused" al instante.)
sudo ip netns exec pc2 curl -s --max-time 3 http://192.168.1.10:22
echo "(timeout: bloqueado por r1)"

echo "== [OK] casa -> intranet por la VPN =="
sudo ip netns exec casa curl -s http://192.168.1.10

echo "== [OK] srv1 (Internet) -> intranet por el port forwarding 198.51.100.2:8080 =="
sudo ip netns exec srv1 curl -s http://198.51.100.2:8080

echo "== [BLOQUEADO] srv1 (Internet) -> r1 puerto 22 =="
sudo ip netns exec srv1 curl -s --max-time 3 http://198.51.100.2:22
echo "(timeout: bloqueado por r1)"

echo "== [OK] srv1 -> web pública (puerto 80) =="
sudo ip netns exec srv1 curl -s http://203.0.113.80

echo "== [BLOQUEADO] srv1 -> panel de admin (puerto 8000) =="
sudo ip netns exec srv1 curl -s --max-time 3 http://203.0.113.80:8000
echo "(timeout: bloqueado por el cortafuegos de web)"

echo "== [OK] el panel sí funciona desde dentro del propio servidor =="
sudo ip netns exec web curl -s http://127.0.0.1:8000

echo "== Reglas de r1 con contadores (pkts = paquetes que han coincidido) =="
sudo ip netns exec r1 iptables -L -n -v --line-numbers
sudo ip netns exec r1 iptables -t nat -L -n -v
