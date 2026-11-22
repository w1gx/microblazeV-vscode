/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Startup report of the Ethernet configuration (mb-test addition to AMD's
 * lwIP echo server template). Everything goes to the console via xil_printf.
 */
#include "netinfo.h"

#include "lwip/dhcp.h"
#include "lwip/ip4_addr.h"
#include "xemaclite.h"
#include "xil_printf.h"
#include "xstatus.h"

static void print_ip(const char *label, const ip4_addr_t *ip)
{
    xil_printf("  %-12s: %d.%d.%d.%d\r\n", label,
               ip4_addr1(ip), ip4_addr2(ip), ip4_addr3(ip), ip4_addr4(ip));
}

void netinfo_interface(struct netif *netif, UINTPTR emac_baseaddr)
{
    const u8 *m = netif->hwaddr;
    xil_printf("\r\nEthernet interface\r\n");
    xil_printf("  %-12s: AXI Ethernet Lite at 0x%08x, 10/100 Mbit/s MII\r\n", "controller",
               (unsigned)emac_baseaddr);
    xil_printf("  %-12s: %02x:%02x:%02x:%02x:%02x:%02x\r\n", "MAC address",
               m[0], m[1], m[2], m[3], m[4], m[5]);
}

void netinfo_dhcp_wait(void)
{
    xil_printf("\r\nRequesting an IP address by DHCP (falls back to 192.168.1.10 after ~12 s) ...\r\n");
}

/* PHY on the MDIO bus: DP83848 on the Arty, normally at address 1. Reads go
 * through a separate driver instance, so lwIP's instance is not touched. */
static void print_phy(UINTPTR emac_baseaddr)
{
    static XEmacLite emac;
    if (XEmacLite_Initialize(&emac, emac_baseaddr) != XST_SUCCESS) {
        xil_printf("  %-12s: cannot access MDIO\r\n", "PHY");
        return;
    }
    for (u32 addr = 0; addr < 32; addr++) {
        u16 id1, id2, bmsr, physts;
        if (XEmacLite_PhyRead(&emac, addr, 2, &id1) != XST_SUCCESS || id1 == 0xFFFF || id1 == 0)
            continue;
        XEmacLite_PhyRead(&emac, addr, 3, &id2);
        XEmacLite_PhyRead(&emac, addr, 1, &bmsr);           /* link bit is latched low: read twice */
        XEmacLite_PhyRead(&emac, addr, 1, &bmsr);
        XEmacLite_PhyRead(&emac, addr, 0x10, &physts);      /* DP83848 PHYSTS: speed/duplex */
        xil_printf("  %-12s: %s, MDIO address %d (ID %04x:%04x)\r\n", "PHY",
                   (id1 == 0x2000 && (id2 & 0xFFF0) == 0x5C90) ? "TI DP83848" : "unknown",
                   (int)addr, id1, id2);
        if (bmsr & 0x0004)
            xil_printf("  %-12s: up, %s Mbit/s, %s duplex\r\n", "link",
                       (physts & 0x0002) ? "10" : "100", (physts & 0x0004) ? "full" : "half");
        else
            xil_printf("  %-12s: DOWN - is the cable plugged in?\r\n", "link");
        return;
    }
    xil_printf("  %-12s: no PHY answers on MDIO\r\n", "PHY");
}

void netinfo_summary(struct netif *netif, UINTPTR emac_baseaddr)
{
    const ip4_addr_t *ip = netif_ip4_addr(netif);

    xil_printf("\r\nNetwork configuration\r\n");
    print_phy(emac_baseaddr);
#if LWIP_DHCP
    if (dhcp_supplied_address(netif)) {
        struct dhcp *d = netif_dhcp_data(netif);
        xil_printf("  %-12s: DHCP, server %d.%d.%d.%d, lease %d s\r\n", "address from",
                   ip4_addr1(ip_2_ip4(&d->server_ip_addr)), ip4_addr2(ip_2_ip4(&d->server_ip_addr)),
                   ip4_addr3(ip_2_ip4(&d->server_ip_addr)), ip4_addr4(ip_2_ip4(&d->server_ip_addr)),
                   (int)d->offered_t0_lease);
    } else {
        xil_printf("  %-12s: static fallback (no DHCP answer)\r\n", "address from");
    }
#else
    xil_printf("  %-12s: static (DHCP disabled in sw/bsp.conf)\r\n", "address from");
#endif
    print_ip("IP address", ip);
    print_ip("netmask", netif_ip4_netmask(netif));
    print_ip("gateway", netif_ip4_gw(netif));
    xil_printf("\r\nEcho server ready on TCP port %d. From your PC:  nc %d.%d.%d.%d %d\r\n\r\n",
               ECHO_PORT, ip4_addr1(ip), ip4_addr2(ip), ip4_addr3(ip), ip4_addr4(ip), ECHO_PORT);
}
