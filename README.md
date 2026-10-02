# Laboratorio de Redes con Network Namespaces

Laboratorio de redes paso a paso construido con `ip netns`, sin máquinas virtuales.
Desde dos ordenadores unidos por un cable hasta una red completa con Internet, DHCP,
DNS, web, VPN, Tor y detección de ataques.

📖 **Web explicativa:** https://melvinfranco99.github.io/laboratorio-redes-netns/
📄 **Documentación en PDF:** [`documentacion.pdf`](documentacion.pdf)

## Las 13 fases

| # | Archivo | Contenido |
|---|---------|-----------|
| 01 | `01_pc_pc.sh` | Dos PCs unidos por un cable veth |
| 02 | `02_pc_sw_pc.sh` | Dos PCs conectados a un switch (bridge) |
| 03 | `03_pc_sw_r_sw_pc.sh` | Dos redes unidas por un router |
| 04 | `04_cadena_routers.sh` | 4 routers en cadena con rutas estáticas |
| 05 | `05_red_routers.sh` | Red de routers con camino de respaldo (métricas) |
| 06 | `06_internet.sh` | Internet, IPs públicas y NAT |
| 07 | `07_dhcp.sh` | Servidor DHCP (dnsmasq) |
| 08 | `08_dns.sh` | Servidor DNS con zona propia |
| 09 | `09_web.sh` | Servidores web público e intranet |
| 10 | `10_vpn.sh` | VPN con WireGuard |
| 11 | `11_iptables.sh` | Firewall con iptables |
| 12 | `12_tor.sh` | Red Tor privada |
| 13 | `13_deteccion_ataques.sh` | Detección de SQL injection y fuerza bruta |

## Cómo se usa

Las fases 01–05 son independientes. A partir de la 06 se construye una sola red que
va creciendo, así que se ejecutan en orden:

```sh
sh 01_pc_pc.sh          # fases 01-05: pruébalas sueltas
sh 06_internet.sh       # base de las siguientes
sh 07_dhcp.sh
sh 08_dns.sh
sh 09_web.sh
sh 10_vpn.sh
sh 11_iptables.sh
sh 12_tor.sh            # tarda ~2 min
sh 13_deteccion_ataques.sh
```

Todos los comandos usan `sudo`. La limpieza total está comentada al final de las
fases 12 y 13, o puedes usar `limpiar_redes.sh`.

## Requisitos

```sh
sudo pacman -S iproute2 dnsmasq dhcpcd bind wireguard-tools tor tcpdump
```
