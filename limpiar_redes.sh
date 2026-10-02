# Limpiar todo lo anterior
for ns in $(ip netns list | awk '{print $1}'); do
        echo "Eliminando namespace: $ns"
        ip netns del "$ns"
done

for br in $(ip -o link show type bridge | awk -F': ' '{print $2}' | cut -d'@' -f1); do
        echo "Eliminando bridge: $br"
        ip link set "$br" down 2>/dev/null
        ip link del "$br" type bridge
done
