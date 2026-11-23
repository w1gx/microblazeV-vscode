/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Timer-driven RGB sequence on LD0..LD3, using the second AXI Timer
 * (axi_timer_1, IRQ 5). See rgb.h.
 *
 * Counter 0 of axi_timer_1 counts down from RGB_SEQ_PERIOD_MS, reloads itself
 * and raises an interrupt every period. The interrupt starts one colour-wheel
 * rotation of RGB_SEQ_ROT_MS; the timer's own count (time since the last
 * reload) gives the position in it. After the rotation the LEDs stay off
 * until the next interrupt. The PWM itself still runs in rgb_pwm_run().
 */
#include <stdio.h>
#include "xparameters.h"
#include "xtmrctr.h"
#include "xinterrupt_wrap.h"
#include "xstatus.h"
#include "rgb.h"

#define SEQ_CTR         0       /* counter 0 of axi_timer_1 */
#define TMR_HZ          XPAR_XTMRCTR_1_CLOCK_FREQUENCY
/* Generate mode, down count: the period is TLR + 2 clock cycles. */
#define SEQ_TLR         ((uint32_t)((uint64_t)TMR_HZ * RGB_SEQ_PERIOD_MS / 1000) - 2)
#define SEQ_ROT_COUNTS  ((uint32_t)((uint64_t)TMR_HZ * RGB_SEQ_ROT_MS / 1000))

static XTmrCtr seq_tmr;
static volatile uint32_t seq_irqs;      /* incremented by the interrupt */

static void seq_isr(void *ref, u8 ctr)
{
    (void)ref;
    if (ctr == SEQ_CTR)
        seq_irqs++;
}

int rgb_seq_init(void)
{
    XTmrCtr_Config *cfg = XTmrCtr_LookupConfig(XPAR_XTMRCTR_1_BASEADDR);
    int st;

    if (cfg == NULL)
        return XST_DEVICE_NOT_FOUND;
    st = XTmrCtr_Initialize(&seq_tmr, XPAR_XTMRCTR_1_BASEADDR);
    if (st != XST_SUCCESS)
        return st;
    /* INTC (normal mode) + enable this input + CPU interrupts, AMD's SDT wrapper */
    st = XSetupInterruptSystem(&seq_tmr, (void *)XTmrCtr_InterruptHandler, cfg->IntrId,
                               cfg->IntrParent, XINTERRUPT_DEFAULT_PRIORITY);
    if (st != XST_SUCCESS)
        return st;
    XTmrCtr_SetHandler(&seq_tmr, seq_isr, NULL);
    XTmrCtr_SetOptions(&seq_tmr, SEQ_CTR,
                       XTC_INT_MODE_OPTION | XTC_AUTO_RELOAD_OPTION | XTC_DOWN_COUNT_OPTION);
    XTmrCtr_SetResetValue(&seq_tmr, SEQ_CTR, SEQ_TLR);
    XTmrCtr_Start(&seq_tmr, SEQ_CTR);

    printf("  RGB timer     : 0x%08lx, irq %u, %u ms rotation every %u ms\n",
           (unsigned long)XPAR_XTMRCTR_1_BASEADDR, (unsigned)(cfg->IntrId & 0xFFF),
           (unsigned)RGB_SEQ_ROT_MS, (unsigned)RGB_SEQ_PERIOD_MS);
    return XST_SUCCESS;
}

void rgb_seq_update(void)
{
    static uint32_t seen;
    static int active;
    uint32_t n = seq_irqs;

    if (n != seen) {                    /* a new period started: run one rotation */
        seen = n;
        active = 1;
    }
    if (!active)
        return;
    uint32_t elapsed = SEQ_TLR - XTmrCtr_GetValue(&seq_tmr, SEQ_CTR);   /* counts since reload */
    if (elapsed >= SEQ_ROT_COUNTS) {
        active = 0;
        rgb_off();
        return;
    }
    rgb_rainbow(elapsed / (SEQ_ROT_COUNTS / 360));
}
