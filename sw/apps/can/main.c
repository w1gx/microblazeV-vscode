/*
 * Author: w1gx
 * Date:   2026-11-24
 *
 * CAN demo for the W1GX AXI CAN controller (axi_can_controller_0, IRQ 6,
 * can_tx / can_rx on ChipKit IO32 / IO33, 500 kbit/s from the IP's C_BIT_RATE).
 * Everything runs on the controller's interrupt (modules/can/can_node.c).
 *
 * 1. Loopback self-test, no bus or transceiver needed: standard, extended,
 *    remote and empty frames go out and must come back unchanged through the
 *    acceptance filters, one TX-done and one RX interrupt each.
 * 2. Bus mode, all frames accepted:
 *    - heartbeat 0x100 every second: [counter, switches]
 *    - BTN0..BTN3 send 0x120..0x123: [switches, button number]
 *    - every received frame is printed, byte 0 goes to LD4..LD7
 *    - bus errors and error-state changes are printed with TEC / REC
 *    It starts in one-shot mode, so a board alone on the bus reports one ACK
 *    error per frame instead of retrying for ever.
 * Console keys: s status, l loopback test, o one-shot on/off, a abort TX, ? help.
 */
#include <stdint.h>
#include <stdio.h>
#include "xparameters.h"
#include "xgpio.h"
#include "xuartlite_l.h"
#include "xstatus.h"
#include "sleep.h"
#include "can_node.h"

#define LED_CHANNEL      1          /* axi_gpio_0: LD4..LD7 */
#define BTN_CHANNEL      1          /* axi_gpio_1 channel 1: BTN0..3 */
#define SW_CHANNEL       2          /* axi_gpio_1 channel 2: SW0..3 */
#define HEARTBEAT_ID     0x100u
#define BUTTON_ID        0x120u     /* + button number */
#define HEARTBEAT_MS     1000u
#define LOOP_MS          1u
#define BUTTON_MS        20u        /* button sampling: longer than the contact bounce */

static XGpio leds, inputs;
static uint32_t bus_mode = XAXICANCONTROLLER_MODE_ONE_SHOT;

static void print_help(void)
{
    printf("keys: s status, l loopback test, o one-shot on/off, a abort TX, ? help\n");
}

static void print_status(void)
{
    XAxiCanController_ErrorStatus e;
    can_stats_t s;

    XAxiCanController_GetErrorStatus(&can_dev, &e);
    can_node_stats(&s);
    printf("status: TEC %u REC %u, %s, last error %s, %s\n", (unsigned)e.Tec, (unsigned)e.Rec,
           e.BusOff ? "BUS OFF" : e.Passive ? "error passive" : e.Warning ? "error active (warning)"
                                                              : "error active",
           can_error_name(e.LastError), (bus_mode & XAXICANCONTROLLER_MODE_ONE_SHOT) ? "one-shot" : "retransmit");
    printf("        irqs %lu, sent %lu, received %lu, arbitration lost %lu, dropped %lu,\n"
           "        bus errors %lu, state changes %lu, RX overrun %lu (+%lu ring)\n",
           (unsigned long)s.irqs, (unsigned long)s.tx_done, (unsigned long)s.rx_frames,
           (unsigned long)s.arb_lost, (unsigned long)s.tx_dropped, (unsigned long)s.errors,
           (unsigned long)s.state_changes, (unsigned long)s.rx_overrun, (unsigned long)s.ring_overrun);
}

static int frames_equal(const XAxiCanController_Frame *a, const XAxiCanController_Frame *b)
{
    uint32_t len = a->Remote ? 0 : XAxiCanController_DlcToLength(a->Dlc);

    if (a->Id != b->Id || a->Extended != b->Extended || a->Remote != b->Remote || a->Dlc != b->Dlc)
        return 0;
    for (uint32_t i = 0; i < len; i++)
        if (a->Data[i] != b->Data[i])
            return 0;
    return 1;
}

/* Loopback: the controller is off the bus and receives what it sends. */
static int loopback_test(void)
{
    static const XAxiCanController_Frame tx[] = {
        { .Id = 0x5A5,      .Dlc = 8, .Data = { 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 } },
        { .Id = 0x18DAF110, .Extended = 1, .Dlc = 3, .Data = { 0xCA, 0xFE, 0x42 } },
        { .Id = 0x7FF,      .Remote = 1, .Dlc = 4 },
        { .Id = 0x001,      .Dlc = 0 },
    };
    const unsigned n = sizeof tx / sizeof tx[0];
    can_stats_t before, after;
    unsigned ok = 0;

    can_node_set_mode(XAXICANCONTROLLER_MODE_LOOPBACK);
    can_node_stats(&before);
    usleep(1000);                                       /* 11 recessive bits before it joins */
    for (unsigned i = 0; i < n; i++) {
        XAxiCanController_Frame rx;
        unsigned wait;

        if (can_node_send(&tx[i]) != XST_SUCCESS) {
            printf("  loopback: frame %u not accepted\n", i);
            break;
        }
        for (wait = 0; wait < 100 && !can_node_recv(&rx); wait++)
            usleep(100);                                /* a frame takes < 300 us at 500 kbit/s */
        if (wait == 100) {
            printf("  loopback: frame %u did not come back\n", i);
            continue;
        }
        if (frames_equal(&tx[i], &rx)) {
            ok++;
            can_print_frame("  loopback ok :", &rx);
        } else {
            can_print_frame("  loopback BAD:", &rx);
        }
    }
    can_node_stats(&after);
    unsigned done = (unsigned)(after.tx_done - before.tx_done);
    unsigned rxd  = (unsigned)(after.rx_frames - before.rx_frames);
    int pass = ok == n && done == n && rxd == n;
    printf("  loopback    : %u/%u frames back unchanged, %u TX-done and %u RX by interrupt -> %s\n",
           ok, n, done, rxd, pass ? "PASS" : "FAIL");
    can_node_set_mode(bus_mode);
    return pass;
}

static void send_frame(const XAxiCanController_Frame *f)
{
    int st = can_node_send(f);

    if (st == XST_SUCCESS)
        can_print_frame("TX", f);
    else if (st == XST_DEVICE_BUSY) {
        XAxiCanController_ErrorStatus e;

        XAxiCanController_GetErrorStatus(&can_dev, &e);
        printf("TX std 0x%03lx skipped: all TX buffers busy%s\n", (unsigned long)f->Id,
               e.Tec == 0 && e.Rec == 0
                   ? " and TEC/REC 0: nothing was ever sent, can_rx (P15) never\n"
                     "    reads recessive (high) for 11 bits. Check transceiver RXD -> IO33, its power,\n"
                     "    standby pin (SN65HVD230 Rs low), and CANH/CANL to the other node"
                   : "");
    }
    else
        printf("TX std 0x%03lx failed (status %d)\n", (unsigned long)f->Id, st);
}

static void report_events(uint32_t ev)
{
    XAxiCanController_ErrorStatus e;

    if (!(ev & (XAXICANCONTROLLER_EVENT_ERROR | XAXICANCONTROLLER_EVENT_STATE |
                XAXICANCONTROLLER_EVENT_TX_DROPPED | XAXICANCONTROLLER_EVENT_RX_OVERRUN)))
        return;
    XAxiCanController_GetErrorStatus(&can_dev, &e);
    if (ev & XAXICANCONTROLLER_EVENT_ERROR)
        printf("bus error: %s (TEC %u REC %u)%s\n", can_error_name(e.LastError), (unsigned)e.Tec,
               (unsigned)e.Rec,
               e.LastError == XAXICANCONTROLLER_ERR_ACK ? " - no ACK: is another node on the bus?" : "");
    if (ev & XAXICANCONTROLLER_EVENT_TX_DROPPED)
        printf("TX dropped (one-shot attempt failed, or aborted)\n");
    if (ev & XAXICANCONTROLLER_EVENT_RX_OVERRUN)
        printf("RX overrun: the controller's RX FIFO was full\n");
    if (ev & XAXICANCONTROLLER_EVENT_STATE)
        printf("state: %s%s%s (TEC %u REC %u)\n", e.BusOff ? "BUS OFF" : e.Passive ? "error passive" : "error active",
               e.Warning && !e.BusOff ? ", warning" : "", e.BusOff ? ", recovers after 128 x 11 recessive bits" : "",
               (unsigned)e.Tec, (unsigned)e.Rec);
}

static void handle_key(char c)
{
    switch (c) {
    case 's':
        print_status();
        break;
    case 'l':
        loopback_test();
        printf("back on the bus\n");
        break;
    case 'o':
        bus_mode ^= XAXICANCONTROLLER_MODE_ONE_SHOT;
        can_node_set_mode(bus_mode);
        printf("%s (controller reset, waiting frames dropped)\n",
               (bus_mode & XAXICANCONTROLLER_MODE_ONE_SHOT) ? "one-shot: every frame is tried once"
                                                            : "retransmit: frames are repeated until sent");
        break;
    case 'a':
        XAxiCanController_AbortTx(&can_dev);
        printf("abort: waiting frames dropped\n");
        break;
    case '?':
    case 'h':
        print_help();
        break;
    default:
        break;
    }
}

int main(void)
{
    uint32_t ms = 0, heartbeat = 0, last_btn = 0;
    int st;

    printf("\n=== CAN demo (W1GX AXI CAN controller) ===\n");
    if (XGpio_Initialize(&leds, XPAR_XGPIO_0_BASEADDR) != XST_SUCCESS ||
        XGpio_Initialize(&inputs, XPAR_XGPIO_1_BASEADDR) != XST_SUCCESS) {
        printf("GPIO init failed\n");
        return 1;
    }
    XGpio_SetDataDirection(&leds, LED_CHANNEL, 0x0);
    XGpio_SetDataDirection(&inputs, BTN_CHANNEL, 0xF);
    XGpio_SetDataDirection(&inputs, SW_CHANNEL, 0xF);
    XGpio_DiscreteWrite(&leds, LED_CHANNEL, 0);

    st = can_node_init();
    if (st != XST_SUCCESS) {
        printf("CAN init failed (status %d)%s\n", st,
               st == XST_NO_FEATURE ? ": irq not connected in the block design" : "");
        return 1;
    }
    printf("  controller  : 0x%08lx, version %u.%u, RX FIFO %u, %u TX buffers, %u filters, irq %lu\n",
           (unsigned long)XPAR_XAXI_CAN_CONTROLLER_0_BASEADDR, (unsigned)can_dev.VersionMajor,
           (unsigned)can_dev.VersionMinor, (unsigned)can_dev.RxFifoDepth, (unsigned)can_dev.TxBuffers,
           (unsigned)can_dev.NumFilters, (unsigned long)can_node_irq_number());
    loopback_test();

    printf("bus mode (%s): heartbeat 0x%03x every %u ms, BTN0..3 send 0x%03x..0x%03x, byte 0 of\n"
           "received frames on LD4..LD7. can_tx = ChipKit IO32 (R15), can_rx = IO33 (P15).\n",
           (bus_mode & XAXICANCONTROLLER_MODE_ONE_SHOT) ? "one-shot" : "retransmit", HEARTBEAT_ID,
           HEARTBEAT_MS, BUTTON_ID, BUTTON_ID + 3);
    print_help();

    for (;;) {
        XAxiCanController_Frame f;
        uint32_t sw = XGpio_DiscreteRead(&inputs, SW_CHANNEL) & 0xF;
        uint32_t pressed = 0;

        if (ms % BUTTON_MS == 0) {
            uint32_t btn = XGpio_DiscreteRead(&inputs, BTN_CHANNEL) & 0xF;
            pressed = btn & ~last_btn;
            last_btn = btn;
        }
        for (uint32_t b = 0; b < 4; b++) {
            if (pressed & (1u << b)) {
                XAxiCanController_Frame tx = { .Id = BUTTON_ID + b, .Dlc = 2, .Data = { (u8)sw, (u8)b } };
                send_frame(&tx);
            }
        }
        if (ms - heartbeat >= HEARTBEAT_MS) {
            static uint8_t count;
            XAxiCanController_Frame tx = { .Id = HEARTBEAT_ID, .Dlc = 2, .Data = { count++, (u8)sw } };
            heartbeat = ms;
            send_frame(&tx);
        }
        while (can_node_recv(&f)) {
            can_print_frame("RX", &f);
            if (!f.Remote && f.Dlc > 0)
                XGpio_DiscreteWrite(&leds, LED_CHANNEL, f.Data[0] & 0xF);
        }
        report_events(can_node_take_events());
        while (!XUartLite_IsReceiveEmpty(XPAR_XUARTLITE_0_BASEADDR))
            handle_key((char)XUartLite_RecvByte(XPAR_XUARTLITE_0_BASEADDR));

        usleep(LOOP_MS * 1000);
        ms += LOOP_MS;
    }
}
