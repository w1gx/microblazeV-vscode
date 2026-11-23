/*
 * Author: w1gx
 * Date:   2026-11-22
 */
/* Lost-interrupt work-around for AXI Ethernet Lite receive, see emaclite_rx.c. */
#ifndef EMACLITE_RX_H
#define EMACLITE_RX_H

#include "lwip/netif.h"

/* Hand frames that are waiting in the EmacLite's receive buffers to lwIP.
 * Call before every xemacif_input(). */
void emaclite_drain_rx(struct netif *netif);

#endif
