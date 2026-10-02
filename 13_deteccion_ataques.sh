#!/bin/sh
# =====================================================================
#  FASE 13:  DETECTAR Y BLOQUEAR ATAQUES (lab defensivo)
# =====================================================================
#  OBJETIVO (TFG): montar un pequeño escenario AISLADO con un servidor
#  web "víctima" y una máquina "atacante", lanzar dos ataques clásicos
#  contra NUESTRO propio servidor del laboratorio y aprender a:
#     1) verlos    (tcpdump / Wireshark + logs del servidor)
#     2) detectarlos y bloquearlos (iptables)
#
#      [atacante] 10.13.13.20 ----[ sw13 ]---- 10.13.13.10 [victima]
#                                                  servidor web:
#                                                   /login  (usuario/clave)
#                                                   /buscar (consulta BD)
#
#  Todo ocurre en un segmento privado 10.13.13.0/24 que creamos aquí
#  mismo: esta fase es INDEPENDIENTE, no necesita las fases anteriores.
#
#  ATAQUES QUE PROBAMOS (los dos, contra nuestro propio servidor):
#   A) SQL injection: meter trozos de SQL en el buscador para intentar
#      saltarse la consulta (p. ej.  ' OR '1'='1  o  UNION SELECT).
#   B) Fuerza bruta: probar muchas contraseñas seguidas en el login.
#
#  CÓMO LOS DETECTAMOS (todo con herramientas que ya tienes):
#   - tcpdump: graba el tráfico a un archivo .pcap (se abre con Wireshark).
#   - iptables -m string: mira DENTRO del paquete y caza las palabras
#     típicas de una inyección SQL (HTTP va en texto plano).
#   - iptables -m recent: cuenta conexiones por IP; si una IP abre
#     demasiadas en poco tiempo (fuerza bruta), la bloquea sola.
#   - El log del propio servidor: deja constancia de cada intento.
#
#  NOTA sobre USUARIOS/PERMISOS en namespaces:
#   Un netns aísla la RED, pero comparte los usuarios del sistema con
#   el host (no tiene su propio /etc/passwd). Por eso, en vez de una
#   base de datos real con usuarios, simulamos el login y la BD con un
#   pequeño servidor en Python: es más sencillo y se ve igual de bien.
#
#  REQUISITOS: tcpdump, python3, iptables (todo ya instalado).
#  EJECUCIÓN:  sh 13_deteccion_ataques.sh
# =====================================================================


# ---------------------------------------------------------------------
# 0. LIMPIEZA DE UNA EJECUCIÓN ANTERIOR DE ESTA FASE
# ---------------------------------------------------------------------
sudo pkill -f "/tmp/lab/victim[a]"     # el servidor web víctima
sudo pkill -f "captura_fase1[3]"       # el tcpdump de esta fase
sudo ip netns del victima 2>/dev/null
sudo ip netns del atacante 2>/dev/null
sudo ip link del sw13 2>/dev/null
sudo mkdir -p /tmp/lab
sudo chmod 777 /tmp/lab
sudo rm -f /tmp/lab/victima.log /tmp/lab/captura_fase13.pcap


# ---------------------------------------------------------------------
# 1. CREACIÓN DE DISPOSITIVOS
#    Dos equipos (víctima y atacante) y un switch que los une.
# ---------------------------------------------------------------------
sudo ip netns add victima
sudo ip netns add atacante
sudo ip link add sw13 type bridge


# ---------------------------------------------------------------------
# 2. CABLEADO, CONEXIÓN Y ALTA
# ---------------------------------------------------------------------
sudo ip link add veth_victima_sw13 type veth peer name veth_sw13_victima
sudo ip link add veth_atacante_sw13 type veth peer name veth_sw13_atacante

sudo ip link set veth_victima_sw13 netns victima
sudo ip link set veth_atacante_sw13 netns atacante
sudo ip link set veth_sw13_victima master sw13
sudo ip link set veth_sw13_atacante master sw13

sudo ip link set up dev sw13
sudo ip link set up dev veth_sw13_victima
sudo ip link set up dev veth_sw13_atacante
sudo ip netns exec victima ip link set up dev lo
sudo ip netns exec atacante ip link set up dev lo
sudo ip netns exec victima ip link set up dev veth_victima_sw13
sudo ip netns exec atacante ip link set up dev veth_atacante_sw13


# ---------------------------------------------------------------------
# 3. PONER IPs (misma red, se ven directamente, no hace falta router)
# ---------------------------------------------------------------------
sudo ip netns exec victima ip addr add 10.13.13.10/24 dev veth_victima_sw13
sudo ip netns exec atacante ip addr add 10.13.13.20/24 dev veth_atacante_sw13


# ---------------------------------------------------------------------
# 4. CREAR EL SERVIDOR WEB VÍCTIMA (un pequeño programa en Python)
#    Simula una web con:
#      /login?user=...&pass=...   el usuario correcto es admin/s3cr3t
#      /buscar?q=...              busca en una "base de datos" de mentira
#    Cada petición se apunta en /tmp/lab/victima.log con hora e IP.
#    (Lo escribimos con 'cat' a un archivo; es Python puro, sin trucos.)
# ---------------------------------------------------------------------
cat > /tmp/lab/victima.py <<'PYEOF'
# Servidor web de practicas (lab TFG). Simula login y buscador.
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import urlparse, parse_qs
from datetime import datetime

# "Base de datos" de mentira: una lista de productos.
PRODUCTOS = ["teclado", "raton", "monitor"]
USUARIO_OK = "admin"
CLAVE_OK   = "s3cr3t"
LOG = "/tmp/lab/victima.log"

def apunta(linea):
    # Escribe una linea en el log del servidor con la fecha delante.
    with open(LOG, "a") as f:
        f.write(datetime.now().strftime("%H:%M:%S") + " " + linea + "\n")

class Web(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass  # silenciamos el log por pantalla; usamos el nuestro

    def responde(self, codigo, texto):
        self.send_response(codigo)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        self.wfile.write((texto + "\n").encode())

    def do_GET(self):
        ip = self.client_address[0]
        url = urlparse(self.path)
        args = parse_qs(url.query)

        if url.path == "/login":
            user = args.get("user", [""])[0]
            clave = args.get("pass", [""])[0]
            if user == USUARIO_OK and clave == CLAVE_OK:
                apunta("LOGIN OK   desde %s user=%s" % (ip, user))
                self.responde(200, "Bienvenido, " + user)
            else:
                apunta("LOGIN FALLO desde %s user=%s pass=%s" % (ip, user, clave))
                self.responde(401, "Usuario o clave incorrectos")

        elif url.path == "/buscar":
            q = args.get("q", [""])[0]
            apunta("BUSCAR     desde %s q=%s" % (ip, q))
            # Simulamos la consulta SQL que haria una web mal hecha:
            #   SELECT * FROM productos WHERE nombre = '<q>'
            resultado = [p for p in PRODUCTOS if q.lower() in p]
            self.responde(200, "Resultados: " + ", ".join(resultado))

        else:
            self.responde(200, "Servidor victima OK. Usa /login o /buscar")

HTTPServer(("10.13.13.10", 80), Web).serve_forever()
PYEOF

# Arrancamos el servidor en segundo plano (&) dentro de la victima.
sudo ip netns exec victima python3 /tmp/lab/victima.py &
sleep 2

echo "== El servidor responde a una peticion normal =="
sudo ip netns exec atacante curl -s "http://10.13.13.10/buscar?q=raton"


# ---------------------------------------------------------------------
# 5. EMPEZAR A VIGILAR CON tcpdump
#    Grabamos TODO el trafico del puerto 80 a un archivo .pcap.
#    Ese archivo se puede abrir luego con Wireshark para analizarlo.
#     -i  interfaz,  -w  archivo,  -U  escribir sin esperar (en vivo)
# ---------------------------------------------------------------------
sudo ip netns exec victima tcpdump -i veth_victima_sw13 -w /tmp/lab/captura_fase13.pcap -U port 80 2>/dev/null &
sleep 2


# =====================================================================
#  PARTE A:  SQL INJECTION
# =====================================================================
#  Una web mal programada construye la consulta pegando lo que escribe
#  el usuario:   SELECT * FROM productos WHERE nombre = 'LO_QUE_SEA'
#  Si el atacante escribe   ' OR '1'='1   la condicion siempre es
#  verdadera y la consulta devolveria TODA la tabla. Con  UNION SELECT
#  podria sacar datos de otras tablas (usuarios, claves...).
#
#  Aqui NO explotamos nada real: solo MANDAMOS esos textos y los
#  detectamos mirando el contenido del paquete.
# ---------------------------------------------------------------------

echo
echo "#### A.1  ATAQUE SQLi SIN DEFENSAS (el texto malicioso llega) ####"
# --data-urlencode hace que curl codifique los espacios y comillas.
sudo ip netns exec atacante curl -s -G "http://10.13.13.10/buscar" --data-urlencode "q=' OR '1'='1"
sudo ip netns exec atacante curl -s -G "http://10.13.13.10/buscar" --data-urlencode "q=raton' UNION SELECT clave FROM usuarios -- "

echo
echo "== En el log del servidor se ven las consultas sospechosas =="
sudo grep BUSCAR /tmp/lab/victima.log


# ---------------------------------------------------------------------
#  A.2  ACTIVAR LA DETECCIÓN DE SQLi EN LA VÍCTIMA (iptables -m string)
#    Miramos dentro de cada paquete que entra al puerto 80. Si contiene
#    una palabra típica de inyección, lo REGISTRAMOS (LOG) y lo tiramos
#    (DROP) para que no llegue al servidor.
#     -m string --algo bm --string "..."   busca ese texto en el paquete
#     --icase                               sin distinguir may/minus
#     LOG --log-prefix                      escribe una alerta en dmesg
# ---------------------------------------------------------------------
echo
echo "#### A.2  ACTIVANDO DETECCIÓN DE SQLi ####"
# Regla 1: registrar (dejar aviso en el log del kernel)
sudo ip netns exec victima iptables -A INPUT -p tcp --dport 80 -m string --algo bm --icase --string "union select" -j LOG --log-prefix "ALERTA-SQLI "
sudo ip netns exec victima iptables -A INPUT -p tcp --dport 80 -m string --algo bm --icase --string "' or '" -j LOG --log-prefix "ALERTA-SQLI "
# Regla 2: bloquear (descartar el paquete)
sudo ip netns exec victima iptables -A INPUT -p tcp --dport 80 -m string --algo bm --icase --string "union select" -j DROP
sudo ip netns exec victima iptables -A INPUT -p tcp --dport 80 -m string --algo bm --icase --string "' or '" -j DROP


echo
echo "#### A.3  REPETIMOS EL ATAQUE SQLi (ahora se bloquea) ####"
echo "== Petición normal: sigue funcionando =="
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/buscar?q=raton"
echo "== Petición con inyección: se queda sin respuesta (bloqueada) =="
sudo ip netns exec atacante curl -s --max-time 3 -G "http://10.13.13.10/buscar" --data-urlencode "q=' OR '1'='1"
echo "(timeout: el paquete malicioso fue descartado por iptables)"


# =====================================================================
#  PARTE B:  FUERZA BRUTA EN EL LOGIN
# =====================================================================
#  El atacante prueba muchas contraseñas seguidas. Lo detectamos
#  contando cuántas conexiones NUEVAS abre una misma IP en poco tiempo.
# ---------------------------------------------------------------------

echo
echo "#### B.1  FUERZA BRUTA SIN DEFENSAS (6 intentos seguidos) ####"
# Sin bucles: escribimos los intentos uno a uno (como los harías a mano).
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=1234"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=admin"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=password"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=qwerty"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=12345678"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=s3cr3t"

echo
echo "== El log del servidor muestra la ráfaga de intentos fallidos =="
sudo grep LOGIN /tmp/lab/victima.log


# ---------------------------------------------------------------------
#  B.2  ACTIVAR LA DETECCIÓN DE FUERZA BRUTA (iptables -m recent)
#    'recent' lleva una lista de IPs con la hora de sus conexiones.
#     --set     apunta la IP en la lista "BF" en cada conexión nueva
#     --update --seconds 60 --hitcount 4   ¿esta IP ha hecho 4+ conexiones
#                                          en los últimos 60 s?  -> sí: actúa
#    Si es así: registramos (LOG) y bloqueamos (DROP) las siguientes.
# ---------------------------------------------------------------------
echo
echo "#### B.2  ACTIVANDO DETECCIÓN DE FUERZA BRUTA ####"
# Apuntar cada conexión nueva al puerto 80 en la lista "BF"
sudo ip netns exec victima iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --set --name BF
# A partir de la 4ª conexión en 60 s: avisar
sudo ip netns exec victima iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --name BF -j LOG --log-prefix "ALERTA-FUERZA-BRUTA "
# ...y bloquear
sudo ip netns exec victima iptables -A INPUT -p tcp --dport 80 -m conntrack --ctstate NEW -m recent --update --seconds 60 --hitcount 4 --name BF -j DROP


echo
echo "#### B.3  REPETIMOS LA FUERZA BRUTA (se bloquea tras unos intentos) ####"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=aaa1"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=aaa2"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=aaa3"
echo "(los 3 primeros pasan; a partir del 4º, timeout: IP bloqueada)"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=aaa4"
sudo ip netns exec atacante curl -s --max-time 3 "http://10.13.13.10/login?user=admin&pass=aaa5"


# =====================================================================
#  5. REVISAR LAS EVIDENCIAS
# =====================================================================
echo
echo "================  INFORME DE DETECCIÓN  ================"

echo "== 1) Alertas que ha generado iptables (en el log del kernel) =="
# El target LOG escribe en el log del kernel; lo leemos con dmesg.
sudo dmesg | grep -E "ALERTA-SQLI|ALERTA-FUERZA-BRUTA" | tail -n 15

echo
echo "== 2) Contadores de las reglas de iptables (pkts = veces que saltó) =="
sudo ip netns exec victima iptables -L INPUT -n -v --line-numbers

echo
echo "== 3) IPs marcadas como atacantes en la lista 'recent' =="
sudo ip netns exec victima cat /proc/net/xt_recent/BF 2>/dev/null

echo
echo "== 4) Log del servidor víctima (todos los intentos) =="
sudo cat /tmp/lab/victima.log

echo
echo "== 5) Captura de tráfico para Wireshark =="
echo "Archivo: /tmp/lab/captura_fase13.pcap"
echo "Resumen de los paquetes con texto de inyección SQL:"
sudo tcpdump -r /tmp/lab/captura_fase13.pcap -A 2>/dev/null | grep -iE "union select|OR '1'" | head
echo
echo "Para analizarlo gráficamente:  wireshark /tmp/lab/captura_fase13.pcap"
echo "(en Wireshark, filtro útil:  http.request  )"


# =====================================================================
#  LIMPIEZA DE ESTA FASE (cuando acabes, quita el '#'):
# =====================================================================
# sudo pkill -f "/tmp/lab/victim[a]"
# sudo pkill -f "captura_fase1[3]"
# sudo ip netns del victima
# sudo ip netns del atacante
# sudo ip link del sw13
# sudo rm -f /tmp/lab/victima.py /tmp/lab/victima.log /tmp/lab/captura_fase13.pcap
