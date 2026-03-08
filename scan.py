"""Network scanner that discovers devices on the local subnet via ARP."""

import ipaddress
import os
import socket

from scapy.all import ARP, Ether, conf, get_if_addr, srp


def get_local_subnet() -> str:
    """Auto-detect the local subnet based on the default interface."""
    ip = get_if_addr(conf.iface)
    # /24 covers virtually all home networks
    network = ipaddress.IPv4Network(f"{ip}/24", strict=False)
    return str(network)


# Override auto-detection with NETWORK_PC_MANAGER_SUBNET if set
DEFAULT_SUBNET = os.environ.get("NETWORK_PC_MANAGER_SUBNET") or get_local_subnet()


def scan_network(subnet: str = DEFAULT_SUBNET, timeout: int = 2) -> list[dict]:
    """Return a list of dicts with keys: ip, mac, name."""
    packet = Ether(dst="ff:ff:ff:ff:ff:ff") / ARP(pdst=subnet)
    result = srp(packet, timeout=timeout, verbose=0)[0]

    devices = []
    for _sent, received in result:
        try:
            hostname = socket.gethostbyaddr(received.psrc)[0]
        except (socket.herror, socket.gaierror):
            hostname = "Unknown"
        devices.append(
            {
                "ip": received.psrc,
                "mac": received.hwsrc.upper(),
                "name": hostname,
            }
        )

    devices.sort(key=lambda d: d["name"])
    return devices


if __name__ == "__main__":
    print(f"Scanning {DEFAULT_SUBNET} ...")
    for dev in scan_network():
        print(f"{dev['ip']:15s}  {dev['mac']:17s}  {dev['name']}")
