/*
 * Author: w1gx
 * Date:   2026-11-22
 */
/* Startup report of the Ethernet configuration on the console (mb-test addition
 * to AMD's echo server template; called from main.c). */
#ifndef NETINFO_H
#define NETINFO_H

#include "lwip/netif.h"

#define ECHO_PORT 7     /* must match echo.c */

/* After xemac_add(): controller, base address, MAC address. */
void netinfo_interface(struct netif *netif, UINTPTR emac_baseaddr);

/* Before the DHCP wait loop. */
void netinfo_dhcp_wait(void);

/* Once the address is known (DHCP or fallback): PHY/link, address source,
 * IP/netmask/gateway and how to connect. */
void netinfo_summary(struct netif *netif, UINTPTR emac_baseaddr);

#endif
