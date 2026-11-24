/*
 * Author: w1gx
 * Date:   2026-11-24
 *
 * Interrupt-driven access to the W1GX AXI CAN controller (axi_can_controller_0).
 *
 * can_node_init() resets the controller and connects its irq to the AXI INTC
 * (XSetupInterruptSystem with IntrId / IntrParent from the driver's config
 * table). The interrupt handler moves received frames into a ring buffer and
 * counts the events; the main loop takes frames with can_node_recv() and
 * events with can_node_take_events(), so nothing is printed in interrupt context.
 */
#ifndef CAN_NODE_H
#define CAN_NODE_H

#include <stdint.h>
#include "xaxi_can_controller.h"

/* Event counters, filled by the interrupt handler */
typedef struct {
    uint32_t irqs;          /* interrupts taken */
    uint32_t tx_done;       /* frames sent */
    uint32_t arb_lost;      /* lost arbitrations */
    uint32_t tx_dropped;    /* one-shot failures and aborts */
    uint32_t rx_frames;     /* frames received into the ring */
    uint32_t rx_overrun;    /* frames the controller dropped (its RX FIFO was full) */
    uint32_t ring_overrun;  /* frames dropped because the ring was full */
    uint32_t errors;        /* bus errors seen (error frames) */
    uint32_t state_changes; /* warning / passive / bus off changed */
} can_stats_t;

extern XAxiCanController can_dev;

int  can_node_init(void);                         /* XST_SUCCESS or the failing step's status */
uint32_t can_node_irq_number(void);               /* INTC input the irq is connected to */
int  can_node_set_mode(uint32_t mode);            /* XAXICANCONTROLLER_MODE_*, empties the ring */
int  can_node_send(const XAxiCanController_Frame *f);
int  can_node_recv(XAxiCanController_Frame *f);   /* 1 = a frame was taken from the ring */
uint32_t can_node_take_events(void);              /* XAXICANCONTROLLER_EVENT_* bits since the last call */
void can_node_stats(can_stats_t *s);              /* copy of the counters */
void can_print_frame(const char *prefix, const XAxiCanController_Frame *f);
const char *can_error_name(uint8_t type);

#endif /* CAN_NODE_H */
