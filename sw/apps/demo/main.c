/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * Bring-up test using AMD's standalone BSP and drivers:
 * prints the hardware configuration, checks the DDR3, runs a light chaser on
 * the four LEDs (axi_gpio_0) whose speed is set by the DIP switches, shows
 * the push buttons on the LEDs while pressed (axi_gpio_1, polled) and echoes
 * whatever is typed on the console (115200 8N1 on the Arty's USB-UART).
 * At startup it also checks the Ethernet PHY (MDIO) and the QSPI flash (JEDEC ID)
 * and tests the RGB LEDs (axi_gpio_2, rgb.c), which then show a slow rainbow.
 */
#include <stdint.h>
#include <stdio.h>
#include "xparameters.h"
#include "xgpio.h"
#include "xemaclite.h"
#include "xspi.h"
#include "xuartlite_l.h"
#include "xstatus.h"
#include "rgb.h"

#define LED_CHANNEL     1               /* axi_gpio_0: 4 LEDs */
#define BTN_CHANNEL     1               /* axi_gpio_1 channel 1: BTN0..3 */
#define SW_CHANNEL      2               /* axi_gpio_1 channel 2: SW0..3 */
#define DDR_TEST_BYTES  (1u << 20)      /* 1 MB: much larger than the 16 KB D-cache */

static uint32_t ddr_buf[DDR_TEST_BYTES / 4] __attribute__((section(".ddr")));

static unsigned ddr_test(void)
{
    unsigned errors = 0;
    const unsigned n = DDR_TEST_BYTES / 4;
    for (unsigned i = 0; i < n; i++)
        ddr_buf[i] = i * 0x9E3779B9u;           /* address-dependent pattern */
    for (unsigned i = 0; i < n; i++)
        if (ddr_buf[i] != i * 0x9E3779B9u)
            errors++;
    return errors;
}

/* Ethernet: find the PHY on the MDIO bus (DP83848 on the Arty, normally at
 * address 1), print its ID and link state. Needs the 25 MHz eth_ref_clk. */
static void eth_check(void)
{
    static XEmacLite emac;
    if (XEmacLite_Initialize(&emac, XPAR_XEMACLITE_0_BASEADDR) != XST_SUCCESS) {
        printf("  Ethernet      : EmacLite init failed\n");
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
        printf("  Ethernet      : 0x%08lx, PHY at MDIO address %lu, ID %04x:%04x%s\n",
               (unsigned long)XPAR_XEMACLITE_0_BASEADDR, (unsigned long)addr, id1, id2,
               (id1 == 0x2000 && (id2 & 0xFFF0) == 0x5C90) ? " (TI DP83848)" : "");
        if (bmsr & 0x0004)
            printf("                  link up, %s Mbit/s, %s duplex\n",
                   (physts & 0x0002) ? "10" : "100", (physts & 0x0004) ? "full" : "half");
        else
            printf("                  no link (cable not plugged in?)\n");
        return;
    }
    printf("  Ethernet      : no PHY answers on MDIO\n");
}

/* QSPI flash: JEDEC ID and whether a bitstream is stored at address 0. */
static void flash_check(void)
{
    static XSpi spi;
    if (XSpi_Initialize(&spi, XPAR_XSPI_0_BASEADDR) != XST_SUCCESS ||
        XSpi_SetOptions(&spi, XSP_MASTER_OPTION | XSP_MANUAL_SSELECT_OPTION) != XST_SUCCESS ||
        XSpi_Start(&spi) != XST_SUCCESS) {
        printf("  QSPI flash    : SPI init failed\n");
        return;
    }
    XSpi_IntrGlobalDisable(&spi);                           /* polled mode */
    XSpi_SetSlaveSelect(&spi, 0x01);

    u8 tx[4 + 64] = { 0x9F }, rx[sizeof tx];                /* 0x9F: read JEDEC ID */
    XSpi_Transfer(&spi, tx, rx, 4);
    const char *part = "unknown";
    if (rx[1] == 0x01 && rx[2] == 0x20 && rx[3] == 0x18) part = "Spansion S25FL128S, FLASH_PART=s25fl128sxxxxxx0-spi-x1_x2_x4";
    if (rx[1] == 0x20 && rx[2] == 0xBA && rx[3] == 0x18) part = "Micron N25Q128, FLASH_PART=mt25ql128-spi-x1_x2_x4";
    printf("  QSPI flash    : 0x%08lx, JEDEC ID %02x %02x %02x (%s)\n",
           (unsigned long)XPAR_XSPI_0_BASEADDR, rx[1], rx[2], rx[3], part);

    tx[0] = 0x03; tx[1] = tx[2] = tx[3] = 0;                /* 0x03: read from address 0 */
    for (unsigned i = 4; i < sizeof tx; i++) tx[i] = 0;
    XSpi_Transfer(&spi, tx, rx, sizeof tx);
    int sync = -1;
    for (unsigned i = 4; i + 3 < sizeof rx; i++)
        if (rx[i] == 0xAA && rx[i + 1] == 0x99 && rx[i + 2] == 0x55 && rx[i + 3] == 0x66) { sync = i - 4; break; }
    if (sync >= 0)
        printf("                  bitstream found at address 0 (sync word at offset %d)\n", sync);
    else
        printf("                  no bitstream at address 0 (not flashed yet?)\n");
}

static uint64_t cycles(void)
{
    uint32_t hi, lo, hi2;
    do {
        __asm__ volatile ("csrr %0, cycleh" : "=r"(hi));
        __asm__ volatile ("csrr %0, cycle"  : "=r"(lo));
        __asm__ volatile ("csrr %0, cycleh" : "=r"(hi2));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

int main(void)
{
    static XGpio leds, inputs;
    extern char _heap_start[], _heap_end[];

    setvbuf(stdout, NULL, _IONBF, 0);
    printf("\n\nHello from MicroBlaze V (built %s %s)\n", __DATE__, __TIME__);
    printf("  CPU clock     : %lu Hz\n", (unsigned long)XPAR_CPU_CORE_CLOCK_FREQ_HZ);
    printf("  local memory  : %lu KB at 0x%08lx, heap %lu KB free\n",
           (unsigned long)(XPAR_LMB_BRAM_0_HIGHADDRESS - XPAR_LMB_BRAM_0_BASEADDRESS + 1) / 1024,
           (unsigned long)XPAR_LMB_BRAM_0_BASEADDRESS,
           (unsigned long)(_heap_end - _heap_start) / 1024);
    printf("  DDR3          : %lu MB at 0x%08lx\n",
           (unsigned long)(XPAR_MIG_0_HIGHADDRESS - XPAR_MIG_0_BASEADDRESS + 1) >> 20,
           (unsigned long)XPAR_MIG_0_BASEADDRESS);
    printf("  UART          : 0x%08lx, %lu baud\n",
           (unsigned long)XPAR_XUARTLITE_0_BASEADDR, (unsigned long)XPAR_XUARTLITE_0_BAUDRATE);
    printf("  LED GPIO      : 0x%08lx, %u bits\n",
           (unsigned long)XPAR_XGPIO_0_BASEADDR, (unsigned)XPAR_XGPIO_0_GPIO_WIDTH);
    printf("  button/switch : 0x%08lx, irq %u\n",
           (unsigned long)XPAR_XGPIO_1_BASEADDR, (unsigned)(XPAR_XGPIO_1_INTERRUPTS & 0xFFF));

    uint64_t t0 = cycles();
    unsigned errors = ddr_test();
    uint64_t t1 = cycles();
    printf("  DDR test      : %s (%u errors, 1 MB write+read in %lu us)\n",
           errors ? "FAIL" : "pass", errors,
           (unsigned long)((t1 - t0) / (XPAR_CPU_CORE_CLOCK_FREQ_HZ / 1000000)));
    eth_check();
    flash_check();
    if (rgb_init() != XST_SUCCESS)
        printf("  RGB LEDs      : GPIO init failed\n");
    else
        rgb_selftest();

    if (XGpio_Initialize(&leds, XPAR_XGPIO_0_BASEADDR) != XST_SUCCESS ||
        XGpio_Initialize(&inputs, XPAR_XGPIO_1_BASEADDR) != XST_SUCCESS) {
        printf("GPIO init failed\n");
        return 1;
    }
    XGpio_SetDataDirection(&leds, LED_CHANNEL, 0x0);       /* all outputs */
    XGpio_SetDataDirection(&inputs, BTN_CHANNEL, 0xF);     /* all inputs */
    XGpio_SetDataDirection(&inputs, SW_CHANNEL, 0xF);

    printf("\nLEDs running: switches set the speed, buttons light their LED, RGB LEDs cycle colours.\n"
           "Type something, it will be echoed back.\n");
    unsigned pos = 0, dir = 1, hue = 0;
    uint32_t last_btn = ~0u, last_sw = ~0u;
    for (;;) {
        uint32_t btn = XGpio_DiscreteRead(&inputs, BTN_CHANNEL) & 0xF;
        uint32_t sw  = XGpio_DiscreteRead(&inputs, SW_CHANNEL) & 0xF;
        if (btn != last_btn || sw != last_sw) {
            printf("buttons %u%u%u%u  switches %u%u%u%u\n",
                   (unsigned)(btn >> 3) & 1, (unsigned)(btn >> 2) & 1, (unsigned)(btn >> 1) & 1, (unsigned)btn & 1,
                   (unsigned)(sw >> 3) & 1, (unsigned)(sw >> 2) & 1, (unsigned)(sw >> 1) & 1, (unsigned)sw & 1);
            last_btn = btn;
            last_sw = sw;
        }

        if (btn) {
            XGpio_DiscreteWrite(&leds, LED_CHANNEL, btn);   /* buttons override the chaser */
        } else {
            XGpio_DiscreteWrite(&leds, LED_CHANNEL, 1u << pos);
            if (pos == 0)                           dir = 1;
            if (pos == XPAR_XGPIO_0_GPIO_WIDTH - 1) dir = 0;
            pos = dir ? pos + 1 : pos - 1;
        }

        /* step time: 25 ms (all switches on) .. 400 ms (all off), polling the UART;
         * the waiting is done by the RGB PWM, the rainbow turns 1 degree per 5 ms */
        int steps = 25 * (16 - (int)sw);
        for (int t = 0; t < steps / 5; t++) {
            while (!XUartLite_IsReceiveEmpty(XPAR_XUARTLITE_0_BASEADDR)) {
                char c = XUartLite_RecvByte(XPAR_XUARTLITE_0_BASEADDR);
                if (c == '\r')
                    XUartLite_SendByte(XPAR_XUARTLITE_0_BASEADDR, '\n');
                XUartLite_SendByte(XPAR_XUARTLITE_0_BASEADDR, c);
            }
            rgb_rainbow(hue);
            hue = (hue + 1) % 360;
            rgb_pwm_run(5000);
        }
    }
}
