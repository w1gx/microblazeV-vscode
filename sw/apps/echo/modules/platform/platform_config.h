/*
 * Author: w1gx
 * Date:   2026-11-22
 */
/* Replaces platform_config.h.in of AMD's lwip_echo_server template (normally
 * filled in by its CMake build): the Ethernet MAC to use. */
#ifndef __PLATFORM_CONFIG_H_
#define __PLATFORM_CONFIG_H_

#include "xparameters.h"

#define PLATFORM_EMAC_BASEADDR XPAR_XEMACLITE_0_BASEADDR

#endif
