#!/bin/sh
# =====================================================================
#  FASE 12:  CREAR UNA RED TOR PRIVADA CON NAMESPACES
# =====================================================================
#  OBJETIVO: montar nuestra propia red Tor (no la real) en el
#            Internet simulado y navegar de forma anónima desde pc1
#            hasta la web pública.
#
#                    INTERNET SIMULADO (203.0.113.0/24)
#   [ da ]   .201  autoridad de directorio (+ relay de entrada)
#   [ mid ]  .202  relay intermedio
#   [ exit ] .203  relay de salida  ----------->  [ web ] .80
#        ^
#        |  circuito cifrado en 3 capas (cebolla)
#        |
#   [pc1] cliente Tor (SOCKS en 127.0.0.1:9050) detrás de r1
#
#  CONCEPTOS:
#   - Relay (nodo): reenvía tráfico cifrado. Un circuito usa 3:
#     entrada (guard) -> intermedio -> salida (exit).
#   - Cada relay solo conoce el anterior y el siguiente: la web ve
#     la IP del EXIT, nunca la de pc1.
#   - Autoridad de directorio (DA): lleva la lista de relays de la
#     red ("consenso"). Todos los nodos tienen que conocerla.
#   - TestingTorNetwork 1: modo de pruebas de Tor (tiempos cortos,
#     permite IPs privadas, varios relays en la misma subred...).
#   - Huella (fingerprint): identificador único de cada relay.
#
#  REQUISITOS: fases 6 a 11 ejecutadas.
#              sudo pacman -S tor
#
#  EJECUCIÓN:  sh 12_tor.sh
# =====================================================================


# ---------------------------------------------------------------------
# 0. LIMPIEZA DE UNA EJECUCIÓN ANTERIOR DE ESTA FASE
# ---------------------------------------------------------------------
sudo pkill -f "/tmp/lab/to[r]"
sudo ip netns del da 2>/dev/null
sudo ip netns del mid 2>/dev/null
sudo ip netns del exit 2>/dev/null
sudo rm -rf /tmp/lab/tor


# ---------------------------------------------------------------------
# 1. CREACIÓN DE LOS NODOS TOR
# ---------------------------------------------------------------------
sudo ip netns add da
sudo ip netns add mid
sudo ip netns add exit


# ---------------------------------------------------------------------
# 2. CABLEADO: cada nodo al switch de Internet
# ---------------------------------------------------------------------
sudo ip link add veth_da_inet type veth peer name veth_inet_da
sudo ip link add veth_mid_inet type veth peer name veth_inet_mid
sudo ip link add veth_exit_inet type veth peer name veth_inet_exit

sudo ip link set veth_da_inet netns da
sudo ip link set veth_mid_inet netns mid
sudo ip link set veth_exit_inet netns exit
sudo ip link set veth_inet_da master inet
sudo ip link set veth_inet_mid master inet
sudo ip link set veth_inet_exit master inet


# ---------------------------------------------------------------------
# 3. DAR DE ALTA, IPs Y RUTAS
# ---------------------------------------------------------------------
sudo ip link set up dev veth_inet_da
sudo ip link set up dev veth_inet_mid
sudo ip link set up dev veth_inet_exit

sudo ip netns exec da ip link set up dev lo
sudo ip netns exec mid ip link set up dev lo
sudo ip netns exec exit ip link set up dev lo
sudo ip netns exec da ip link set up dev veth_da_inet
sudo ip netns exec mid ip link set up dev veth_mid_inet
sudo ip netns exec exit ip link set up dev veth_exit_inet

sudo ip netns exec da ip addr add 203.0.113.201/24 dev veth_da_inet
sudo ip netns exec mid ip addr add 203.0.113.202/24 dev veth_mid_inet
sudo ip netns exec exit ip addr add 203.0.113.203/24 dev veth_exit_inet

sudo ip netns exec da ip route add default via 203.0.113.1
sudo ip netns exec mid ip route add default via 203.0.113.1
sudo ip netns exec exit ip route add default via 203.0.113.1


# ---------------------------------------------------------------------
# 4. CARPETAS DE DATOS DE CADA NODO
#    Tor exige que sean privadas (permisos 700).
#    "vacio" es un torrc vacío para que Tor no lea el del sistema.
# ---------------------------------------------------------------------
sudo mkdir -p /tmp/lab/tor
sudo touch /tmp/lab/tor/vacio
sudo mkdir -m 700 /tmp/lab/tor/da
sudo mkdir -m 700 /tmp/lab/tor/da/keys
sudo mkdir -m 700 /tmp/lab/tor/mid
sudo mkdir -m 700 /tmp/lab/tor/exit
sudo mkdir -m 700 /tmp/lab/tor/cliente


# ---------------------------------------------------------------------
# 5. CLAVES DE LA AUTORIDAD DE DIRECTORIO
#    a) tor-gencert crea la identidad de autoridad (v3ident).
#       La contraseña de la clave se deja vacía (echo "").
#    b) tor --list-fingerprint crea las claves de relay de da y
#       nos dice su huella.
#    Guardamos los dos valores en variables para usarlos después.
# ---------------------------------------------------------------------
echo "" | sudo tor-gencert --create-identity-key --passphrase-fd 0 -m 12 \
    -a 203.0.113.201:9030 \
    -i /tmp/lab/tor/da/keys/authority_identity_key \
    -s /tmp/lab/tor/da/keys/authority_signing_key \
    -c /tmp/lab/tor/da/keys/authority_certificate

V3ID=$(sudo grep fingerprint /tmp/lab/tor/da/keys/authority_certificate | cut -d' ' -f2)

FPR=$(sudo tor --list-fingerprint --hush -f /tmp/lab/tor/vacio --defaults-torrc /tmp/lab/tor/vacio \
    --DataDirectory /tmp/lab/tor/da --ORPort 9001 --Nickname da | grep '^da ' | cut -d' ' -f2- | tr -d ' ')

echo "== Identidad de la autoridad (v3ident): $V3ID"
echo "== Huella del relay da:                 $FPR"


# ---------------------------------------------------------------------
# 6. CONFIGURACIÓN (torrc) DE LA AUTORIDAD: da
#    Las líneas comunes a TODOS los nodos son:
#      TestingTorNetwork 1
#      DirAuthority ...   <- dónde está la autoridad de NUESTRA red
#    Lo propio de la autoridad:
#      AuthoritativeDirectory / V3AuthoritativeDirectory
#      V3Auth*            votar el consenso cada 20 s (rápido)
#      TestingDirAuthVote* dar enseguida a todos los relays las
#                         banderas Guard/Exit/HSDir
# ---------------------------------------------------------------------
sudo tee /tmp/lab/tor/da/torrc > /dev/null <<EOF
TestingTorNetwork 1
DirAuthority da orport=9001 v3ident=$V3ID 203.0.113.201:9030 $FPR
DataDirectory /tmp/lab/tor/da
Log notice file /tmp/lab/tor/da/notice.log
RunAsDaemon 1
SafeLogging 0
Nickname da
Address 203.0.113.201
ORPort 9001
DirPort 9030
AssumeReachable 1
ExitPolicy reject *:*
ContactInfo da@melvin.lab
AuthoritativeDirectory 1
V3AuthoritativeDirectory 1
V3AuthVotingInterval 20
V3AuthVoteDelay 4
V3AuthDistDelay 4
TestingV3AuthInitialVotingInterval 20
TestingV3AuthInitialVoteDelay 4
TestingV3AuthInitialDistDelay 4
TestingDirAuthVoteGuard *
TestingDirAuthVoteExit *
TestingDirAuthVoteHSDir *
EOF


# ---------------------------------------------------------------------
# 7. CONFIGURACIÓN DEL RELAY INTERMEDIO: mid
#    ExitPolicy reject *:*  -> nunca hace de salida
# ---------------------------------------------------------------------
sudo tee /tmp/lab/tor/mid/torrc > /dev/null <<EOF
TestingTorNetwork 1
DirAuthority da orport=9001 v3ident=$V3ID 203.0.113.201:9030 $FPR
DataDirectory /tmp/lab/tor/mid
Log notice file /tmp/lab/tor/mid/notice.log
RunAsDaemon 1
SafeLogging 0
Nickname mid
ContactInfo mid@melvin.lab
Address 203.0.113.202
ORPort 9001
AssumeReachable 1
ExitPolicy reject *:*
EOF


# ---------------------------------------------------------------------
# 8. CONFIGURACIÓN DEL RELAY DE SALIDA: exit
#    ExitRelay 1 + ExitPolicy accept *:*  -> sale a cualquier sitio
#    ExitPolicyRejectPrivate 0             -> incluso a IPs del lab
# ---------------------------------------------------------------------
sudo tee /tmp/lab/tor/exit/torrc > /dev/null <<EOF
TestingTorNetwork 1
DirAuthority da orport=9001 v3ident=$V3ID 203.0.113.201:9030 $FPR
DataDirectory /tmp/lab/tor/exit
Log notice file /tmp/lab/tor/exit/notice.log
RunAsDaemon 1
SafeLogging 0
Nickname exit
ContactInfo exit@melvin.lab
Address 203.0.113.203
ORPort 9001
AssumeReachable 1
ExitRelay 1
ExitPolicyRejectPrivate 0
ExitPolicy accept *:*
EOF


# ---------------------------------------------------------------------
# 9. CONFIGURACIÓN DEL CLIENTE: pc1
#    No es relay (no tiene ORPort). Solo abre un proxy SOCKS en
#    127.0.0.1:9050: lo que se mande por ahí viaja por Tor.
# ---------------------------------------------------------------------
sudo tee /tmp/lab/tor/cliente/torrc > /dev/null <<EOF
TestingTorNetwork 1
DirAuthority da orport=9001 v3ident=$V3ID 203.0.113.201:9030 $FPR
DataDirectory /tmp/lab/tor/cliente
Log notice file /tmp/lab/tor/cliente/notice.log
RunAsDaemon 1
SafeLogging 0
SocksPort 127.0.0.1:9050
EOF


# ---------------------------------------------------------------------
# 10. ARRANCAR LA RED TOR
#     Primero la autoridad, luego los relays y por último el cliente.
#     Cada uno dentro de su namespace.
# ---------------------------------------------------------------------
sudo ip netns exec da tor -f /tmp/lab/tor/da/torrc --defaults-torrc /tmp/lab/tor/vacio
sleep 5
sudo ip netns exec mid tor -f /tmp/lab/tor/mid/torrc --defaults-torrc /tmp/lab/tor/vacio
sudo ip netns exec exit tor -f /tmp/lab/tor/exit/torrc --defaults-torrc /tmp/lab/tor/vacio

# La autoridad necesita unas cuantas votaciones para publicar el
# primer consenso con los 3 relays.
echo "Esperando 60 s a que se forme el consenso..."
sleep 60

sudo ip netns exec pc1 tor -f /tmp/lab/tor/cliente/torrc --defaults-torrc /tmp/lab/tor/vacio
echo "Esperando 30 s a que el cliente construya circuitos..."
sleep 30


# ---------------------------------------------------------------------
# 11. COMPROBACIONES
# ---------------------------------------------------------------------
echo "== Relays que conoce la autoridad (consenso) =="
sudo ip netns exec pc1 curl -s http://203.0.113.201:9030/tor/status-vote/current/consensus | grep '^r \|^s '

echo "== Arranque del cliente (debe llegar a Bootstrapped 100%) =="
sudo grep Bootstrapped /tmp/lab/tor/cliente/notice.log

echo "== pc1 visita la web SIN Tor =="
sudo ip netns exec pc1 curl -s http://203.0.113.80

echo "== pc1 visita la web CON Tor (a través del proxy SOCKS) =="
# Si falla, espera un poco más y repite este comando.
sudo ip netns exec pc1 curl -s --socks5-hostname 127.0.0.1:9050 http://203.0.113.80

echo "== Log de la web: compara las dos últimas visitas =="
# Sin Tor la web ve 198.51.100.2 (r1); con Tor ve 203.0.113.203 (exit).
tail -n 2 /tmp/lab/web.log


# =====================================================================
#  LIMPIEZA TOTAL DEL PROYECTO (cuando acabes)
#  Quita el '#' de delante de estas líneas o cópialas en la terminal.
# =====================================================================
# sudo pkill -f "/tmp/la[b]"
# sudo ip -all netns delete
# sudo ip link del sw1
# sudo ip link del sw2
# sudo ip link del inet
# sudo iptables -t nat -D POSTROUTING -s 198.51.100.0/24 ! -o veth_host_isp -j MASQUERADE
# sudo iptables -t nat -D POSTROUTING -s 203.0.113.0/24 ! -o veth_host_isp -j MASQUERADE
# sudo iptables -D FORWARD -i veth_host_isp -j ACCEPT
# sudo iptables -D FORWARD -o veth_host_isp -j ACCEPT
# sudo rm -rf /tmp/lab /etc/netns/pc1 /etc/netns/pc2 /etc/netns/pc3 /etc/netns/pc4
