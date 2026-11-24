/*
 * Author: w1gx
 * Date:   2026-11-24
 *
 * Interrupt-driven access to the W1GX AXI CAN controller, see can_node.h.
 *
 * The controller's irq is level high: OR(EVENTS and IER). RX_VALID stays set
 * while a frame waits, so the handler first empties the RX FIFO into the ring,
 * then reads and clears the events. A frame that arrives in between keeps irq
 * high and the handler runs again. The main loop's accesses to the ring and the
 * pending events run with the controller's interrupts masked (IER), the
 * simplest critical section that doesn't touch the CPU's interrupt state.
 */
#include <stdio.h>
#include "xparameters.h"
#include "xinterrupt_wrap.h"
#include "xstatus.h"
#include "can_node.h"

#define CAN_BASE    XPAR_XAXI_CAN_CONTROLLER_0_BASEADDR
#define RING_SIZE   32u                         /* power of two */
#define IRQ_UNUSED  0xFFFFu                     /* IntrId of an unconnected irq */

XAxiCanController can_dev;

static XAxiCanController_Config *can_cfg;
static XAxiCanController_Frame ring[RING_SIZE];
static volatile uint32_t ring_head;             /* written by the handler */
static volatile uint32_t ring_tail;             /* written by the main loop */
static volatile uint32_t pending_events;
static volatile can_stats_t stats;

/* ------------------------------------------------------------------------- */
/* Interrupt handler                                                         */
/* ------------------------------------------------------------------------- */

static void drain_rx(XAxiCanController *dev)
{
    XAxiCanController_Frame f;

    while (XAxiCanController_Recv(dev, &f) == XST_SUCCESS) {
        uint32_t head = ring_head;
        if (head - ring_tail >= RING_SIZE) {
            stats.ring_overrun++;
            continue;
        }
        ring[head % RING_SIZE] = f;
        __asm__ volatile ("" ::: "memory");     /* frame stored before the index moves */
        ring_head = head + 1;
        stats.rx_frames++;
    }
}

static void can_isr(void *ref)
{
    XAxiCanController *dev = ref;
    uint32_t ev;

    stats.irqs++;
    drain_rx(dev);
    ev = XAxiCanController_GetAndClearEvents(dev);
    if (ev & XAXICANCONTROLLER_EVENT_TX_DONE)    stats.tx_done++;
    if (ev & XAXICANCONTROLLER_EVENT_ARB_LOST)   stats.arb_lost++;
    if (ev & XAXICANCONTROLLER_EVENT_TX_DROPPED) stats.tx_dropped++;
    if (ev & XAXICANCONTROLLER_EVENT_RX_OVERRUN) stats.rx_overrun++;
    if (ev & XAXICANCONTROLLER_EVENT_ERROR)      stats.errors++;
    if (ev & XAXICANCONTROLLER_EVENT_STATE)      stats.state_changes++;
    pending_events |= ev;
}

/* ------------------------------------------------------------------------- */
/* Main-loop side                                                            */
/* ------------------------------------------------------------------------- */

static uint32_t irq_mask(void)
{
    uint32_t enabled = XAxiCanController_InterruptGetEnabled(&can_dev);
    XAxiCanController_InterruptDisable(&can_dev, XAXICANCONTROLLER_EVENT_ALL);
    return enabled;
}

static void irq_restore(uint32_t enabled)
{
    XAxiCanController_InterruptEnable(&can_dev, enabled);
}

int can_node_init(void)
{
    int st;

    can_cfg = XAxiCanController_LookupConfig(CAN_BASE);
    if (can_cfg == NULL)
        return XST_DEVICE_NOT_FOUND;
    if ((can_cfg->IntrId & 0xFFFFu) == IRQ_UNUSED)
        return XST_NO_FEATURE;                  /* irq not connected in the block design */
    st = XAxiCanController_Initialize(&can_dev, CAN_BASE);
    if (st != XST_SUCCESS)
        return st;

    /* The controller keeps its state over a CPU reset: start from a clean one. */
    XAxiCanController_InterruptDisable(&can_dev, XAXICANCONTROLLER_EVENT_ALL);
    st = XAxiCanController_SetMode(&can_dev, XAXICANCONTROLLER_MODE_NORMAL);   /* includes a reset */
    if (st != XST_SUCCESS)
        return st;
    XAxiCanController_AcceptAll(&can_dev);
    XAxiCanController_AckEvents(&can_dev, XAXICANCONTROLLER_EVENT_ALL);

    /* INTC (normal mode) + this input + CPU interrupts, AMD's SDT wrapper */
    st = XSetupInterruptSystem(&can_dev, (void *)can_isr, can_cfg->IntrId, can_cfg->IntrParent,
                               XINTERRUPT_DEFAULT_PRIORITY);
    if (st != XST_SUCCESS)
        return st;
    return XAxiCanController_InterruptEnable(&can_dev, XAXICANCONTROLLER_EVENT_ALL);
}

uint32_t can_node_irq_number(void)
{
    return can_cfg ? (can_cfg->IntrId & 0xFFFu) : IRQ_UNUSED;
}

int can_node_set_mode(uint32_t mode)
{
    uint32_t en = irq_mask();
    int st = XAxiCanController_SetMode(&can_dev, mode);   /* resets: drops waiting TX and RX frames */
    XAxiCanController_AckEvents(&can_dev, XAXICANCONTROLLER_EVENT_ALL);
    ring_tail = ring_head;
    pending_events = 0;
    irq_restore(en);
    return st;
}

int can_node_send(const XAxiCanController_Frame *f)
{
    return XAxiCanController_Send(&can_dev, f);
}

int can_node_recv(XAxiCanController_Frame *f)
{
    uint32_t tail = ring_tail;

    if (tail == ring_head)
        return 0;
    __asm__ volatile ("" ::: "memory");         /* index read before the frame */
    *f = ring[tail % RING_SIZE];
    ring_tail = tail + 1;
    return 1;
}

uint32_t can_node_take_events(void)
{
    uint32_t en = irq_mask();
    uint32_t ev = pending_events;
    pending_events = 0;
    irq_restore(en);
    return ev;
}

void can_node_stats(can_stats_t *s)
{
    uint32_t en = irq_mask();
    s->irqs          = stats.irqs;
    s->tx_done       = stats.tx_done;
    s->arb_lost      = stats.arb_lost;
    s->tx_dropped    = stats.tx_dropped;
    s->rx_frames     = stats.rx_frames;
    s->rx_overrun    = stats.rx_overrun;
    s->ring_overrun  = stats.ring_overrun;
    s->errors        = stats.errors;
    s->state_changes = stats.state_changes;
    irq_restore(en);
}

/* ------------------------------------------------------------------------- */
/* Formatting                                                                */
/* ------------------------------------------------------------------------- */

const char *can_error_name(uint8_t type)
{
    switch (type) {
    case XAXICANCONTROLLER_ERR_BIT:   return "bit";
    case XAXICANCONTROLLER_ERR_STUFF: return "stuff";
    case XAXICANCONTROLLER_ERR_CRC:   return "CRC";
    case XAXICANCONTROLLER_ERR_FORM:  return "form";
    case XAXICANCONTROLLER_ERR_ACK:   return "ACK";
    default:                          return "none";
    }
}

void can_print_frame(const char *prefix, const XAxiCanController_Frame *f)
{
    uint32_t len = f->Remote ? 0 : XAxiCanController_DlcToLength(f->Dlc);

    if (f->Extended)
        printf("%s ext 0x%08lx", prefix, (unsigned long)f->Id);
    else
        printf("%s std 0x%03lx     ", prefix, (unsigned long)f->Id);
    printf(" [%u]%s", (unsigned)f->Dlc, f->Remote ? " remote" : "");
    for (uint32_t i = 0; i < len; i++)
        printf(" %02x", (unsigned)f->Data[i]);
    printf("\n");
}
