/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * RGB LED test and software PWM for LD0..LD3 (axi_gpio_2). See rgb.h.
 */
#include <stdio.h>
#include "xparameters.h"
#include "xgpio.h"
#include "xstatus.h"
#include "rgb.h"

#define RGB_CHANNEL     1
#define RGB_MASK        ((1u << (3 * RGB_NUM_LEDS)) - 1)
#define RGB_STEP_US     16      /* 64 steps x 16 us = 1.024 ms PWM period */
#define CYCLES_PER_US   (XPAR_CPU_CORE_CLOCK_FREQ_HZ / 1000000)

static XGpio rgb_gpio;
static uint8_t level[3 * RGB_NUM_LEDS];     /* index = GPIO bit */

static inline uint32_t rdcycle(void)
{
    uint32_t c;
    __asm__ volatile ("csrr %0, cycle" : "=r"(c));
    return c;
}

int rgb_init(void)
{
    int st = XGpio_Initialize(&rgb_gpio, XPAR_XGPIO_2_BASEADDR);
    if (st != XST_SUCCESS)
        return st;
    XGpio_SetDataDirection(&rgb_gpio, RGB_CHANNEL, 0x0);   /* all outputs */
    rgb_off();
    return XST_SUCCESS;
}

void rgb_set(unsigned led, unsigned r, unsigned g, unsigned b)
{
    if (led >= RGB_NUM_LEDS)
        return;
    level[3 * led + 0] = b > RGB_LEVELS ? RGB_LEVELS : b;
    level[3 * led + 1] = g > RGB_LEVELS ? RGB_LEVELS : g;
    level[3 * led + 2] = r > RGB_LEVELS ? RGB_LEVELS : r;
}

void rgb_off(void)
{
    for (unsigned i = 0; i < sizeof level; i++)
        level[i] = 0;
    XGpio_DiscreteWrite(&rgb_gpio, RGB_CHANNEL, 0);
}

/* Busy-waits on the cycle counter (32-bit wrap-safe; fine for runs < 50 s). */
void rgb_pwm_run(uint32_t us)
{
    const uint32_t start = rdcycle(), total = us * CYCLES_PER_US;
    uint32_t next = start, last = ~0u;
    unsigned phase = 0;

    while ((uint32_t)(rdcycle() - start) < total) {
        uint32_t mask = 0;
        for (unsigned i = 0; i < sizeof level; i++)
            if (phase < level[i])
                mask |= 1u << i;
        if (mask != last) {
            XGpio_DiscreteWrite(&rgb_gpio, RGB_CHANNEL, mask);
            last = mask;
        }
        phase = (phase + 1) % RGB_LEVELS;
        next += RGB_STEP_US * CYCLES_PER_US;
        while ((int32_t)(rdcycle() - next) < 0)
            ;
    }
    XGpio_DiscreteWrite(&rgb_gpio, RGB_CHANNEL, 0);
}

/* Write patterns to the data register and read them back (an all-output
 * axi_gpio returns the written value), then show every colour of every LED. */
int rgb_selftest(void)
{
    static const uint32_t pattern[] = { 0xA5A, 0x5A5, 0xFFF, 0x000 };
    static const struct { const char *name; uint8_t r, g, b; } colour[] = {
        { "red",   RGB_BRIGHT, 0, 0 },
        { "green", 0, RGB_BRIGHT, 0 },
        { "blue",  0, 0, RGB_BRIGHT },
    };
    int errors = 0;

    for (unsigned i = 0; i < sizeof pattern / sizeof pattern[0]; i++) {
        XGpio_DiscreteWrite(&rgb_gpio, RGB_CHANNEL, pattern[i]);
        uint32_t got = XGpio_DiscreteRead(&rgb_gpio, RGB_CHANNEL) & RGB_MASK;
        if (got != pattern[i]) {
            printf("                  readback error: wrote 0x%03lx, read 0x%03lx\n",
                   (unsigned long)pattern[i], (unsigned long)got);
            errors++;
        }
    }
    printf("  RGB LEDs      : 0x%08lx, %u bits, register readback %s\n",
           (unsigned long)XPAR_XGPIO_2_BASEADDR, (unsigned)XPAR_XGPIO_2_GPIO_WIDTH,
           errors ? "FAIL" : "pass");

    printf("                  look at LD0..LD3: each one red, green, blue in turn, then all white\n");
    for (unsigned led = 0; led < RGB_NUM_LEDS; led++)
        for (unsigned c = 0; c < sizeof colour / sizeof colour[0]; c++) {
            rgb_off();
            rgb_set(led, colour[c].r, colour[c].g, colour[c].b);
            rgb_pwm_run(250000);
        }
    for (unsigned led = 0; led < RGB_NUM_LEDS; led++)
        rgb_set(led, RGB_BRIGHT, RGB_BRIGHT, RGB_BRIGHT);
    rgb_pwm_run(600000);

    /* brightness ramp on all LEDs (white), checks that the PWM dims smoothly */
    for (unsigned l = 0; l <= RGB_BRIGHT; l++) {
        for (unsigned led = 0; led < RGB_NUM_LEDS; led++)
            rgb_set(led, l, l, l);
        rgb_pwm_run(40000);
    }
    rgb_off();
    return errors;
}

void rgb_rainbow(unsigned hue)
{
    for (unsigned led = 0; led < RGB_NUM_LEDS; led++) {
        unsigned h = (hue + 90 * led) % 360, f = (h % 60) * RGB_BRIGHT / 60;
        unsigned r = 0, g = 0, b = 0;
        switch (h / 60) {
        case 0: r = RGB_BRIGHT;     g = f;              break;
        case 1: r = RGB_BRIGHT - f; g = RGB_BRIGHT;     break;
        case 2: g = RGB_BRIGHT;     b = f;              break;
        case 3: g = RGB_BRIGHT - f; b = RGB_BRIGHT;     break;
        case 4: r = f;              b = RGB_BRIGHT;     break;
        default: r = RGB_BRIGHT;    b = RGB_BRIGHT - f; break;
        }
        rgb_set(led, r, g, b);
    }
}
