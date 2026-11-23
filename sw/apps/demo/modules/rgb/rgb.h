/*
 * Author: w1gx
 * Date:   2026-11-22
 *
 * The four RGB LEDs LD0..LD3 on axi_gpio_2 (board interface rgb_led, 12 outputs).
 * Bit 3n is blue, 3n+1 green, 3n+2 red of LED n. Brightness comes from software
 * PWM (RGB_LEVELS steps, about 1 kHz), which runs only inside rgb_pwm_run().
 */
#ifndef RGB_H
#define RGB_H

#include <stdint.h>

#define RGB_NUM_LEDS    4
#define RGB_LEVELS      64      /* PWM steps per period: level 0 = off, 64 = always on */
#define RGB_BRIGHT      16      /* level used by the test and the rainbow (25 %, full is glaring) */

int  rgb_init(void);                                            /* XST_SUCCESS or failure */
void rgb_set(unsigned led, unsigned r, unsigned g, unsigned b);  /* levels 0..RGB_LEVELS */
void rgb_off(void);
void rgb_pwm_run(uint32_t us);      /* drive the PWM for us microseconds, LEDs off afterwards */
int  rgb_selftest(void);            /* register readback + visual colour sequence; 0 = pass */
void rgb_rainbow(unsigned hue);     /* colour wheel, LEDs 90 degrees apart; hue in degrees */

/* Timer-driven sequence (rgb_seq.c, axi_timer_1 + IRQ): every RGB_SEQ_PERIOD_MS one
 * colour-wheel rotation of RGB_SEQ_ROT_MS, LEDs off in between. Call rgb_seq_update()
 * often (every few ms) next to rgb_pwm_run(), which does the actual PWM. */
#define RGB_SEQ_PERIOD_MS   2000
#define RGB_SEQ_ROT_MS      1000

int  rgb_seq_init(void);        /* starts the timer + interrupt; XST_SUCCESS or failure */
void rgb_seq_update(void);      /* sets the LED levels for the current point in time */

#endif
