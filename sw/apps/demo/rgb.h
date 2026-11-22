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

#endif
