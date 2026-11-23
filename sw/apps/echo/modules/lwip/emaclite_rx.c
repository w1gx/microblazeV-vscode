/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Work-around for lost AXI Ethernet Lite receive interrupts (mb-test addition
 * to AMD's echo server template; called from main.c before xemacif_input()).
 *
 * The EmacLite has two receive buffers (ping-pong) and signals each received
 * frame with an edge interrupt. XEmacLite_InterruptHandler() hands exactly ONE
 * frame to lwIP per call (xemacliteif.c: "we do not actively poll the
 * emaclite"). When two frames arrive before the interrupt is serviced, the
 * INTC latches one edge, one frame is read and the other stays in its buffer
 * with no further interrupt - until some unrelated EmacLite interrupt comes.
 * Seen on the board as ~320 ms ping times and stalled TCP connections.
 *
 * Here the main loop checks both buffers and, if a frame is waiting, runs the
 * driver's handler itself with interrupts disabled, exactly as the ISR would.
 */
#include "emaclite_rx.h"

#include "lwip/sys.h"
#include "netif/xadapter.h"
#include "netif/xemacliteif.h"
#include "xemaclite.h"
#include "xemaclite_l.h"

static int rx_pending(UINTPTR base)
{
    return !XEmacLite_IsRxEmpty(base) || !XEmacLite_IsRxEmpty(base + XEL_BUFFER_OFFSET);
}

void emaclite_drain_rx(struct netif *netif)
{
    struct xemac_s *xemac = (struct xemac_s *)netif->state;
    xemacliteif_s *emacif = (xemacliteif_s *)xemac->state;
    XEmacLite *instance = emacif->instance;
    UINTPTR base = instance->EmacLiteConfig.BaseAddress;

    for (int i = 0; i < 2; i++) {               /* at most one frame per buffer */
        sys_prot_t lev = sys_arch_protect();
        int pending = rx_pending(base);
        if (pending)
            XEmacLite_InterruptHandler(instance);   /* reads one frame into lwIP's queue */
        sys_arch_unprotect(lev);
        if (!pending)
            break;
    }
}
