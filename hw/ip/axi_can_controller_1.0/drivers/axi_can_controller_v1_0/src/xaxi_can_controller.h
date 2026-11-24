/******************************************************************************
 * xaxi_can_controller.h - driver API for AXI CAN Controller
 *
 * Classical CAN (CAN 2.0A/B) controller: frames are queued into TX buffers and
 * sent by bus priority, received frames pass the acceptance filters into an RX
 * FIFO. Bit timing is fixed by the IP parameters (C_BIT_RATE, C_TQ_PER_BIT,
 * ...), the parameters software needs are read from the CONFIG register.
 *
 * Works in both Vitis flows:
 *   - classic (XSCT/HSI, .mdd + .tcl): config table indexed by DeviceId
 *   - SDT     (Vitis Unified, .yaml + CMake): config table keyed by BaseAddress
 *     (the SDT build defines the SDT macro)
 *
 * Register offsets and raw accessors are in xaxi_can_controller_hw.h, which is
 * regenerated from ip_spec.json.
 *
 * Typical use:
 *     XAxiCanController Dev;
 *     XAxiCanController_Frame F = { .Id = 0x123, .Dlc = 2, .Data = { 0xAA, 0x55 } };
 *     XAxiCanController_Initialize(&Dev, XPAR_AXI_CAN_CONTROLLER_0_BASEADDR);
 *     XAxiCanController_AcceptAll(&Dev);
 *     XAxiCanController_Send(&Dev, &F);
 *     if (XAxiCanController_Recv(&Dev, &F) == XST_SUCCESS) { ... }
 ******************************************************************************/
#ifndef XAXI_CAN_CONTROLLER_H
#define XAXI_CAN_CONTROLLER_H

#ifdef __cplusplus
extern "C" {
#endif

#include "xil_types.h"
#include "xstatus.h"
#include "xaxi_can_controller_hw.h"

/* Configuration table entry (generated into xaxi_can_controller_g.c by the tools) */
typedef struct {
#ifndef SDT
    u16     DeviceId;
#else
    char   *Name;            /* compatible string from the device tree */
#endif
    UINTPTR BaseAddress;
#ifdef SDT
    u32     IntrId;          /* interrupts: encoded ID for XSetupInterruptSystem(), 0xFFFF if irq is unconnected */
    UINTPTR IntrParent;      /* interrupt-parent: controller base address, bit 0 = type */
#endif
} XAxiCanController_Config;

/* Driver instance */
typedef struct {
    UINTPTR BaseAddress;
    u32     IsReady;
    u8      VersionMajor;    /* from the ID register */
    u8      VersionMinor;
    u8      RxFifoDepth;     /* from CONFIG: frames in the RX FIFO (+1 output register) */
    u8      TxBuffers;       /* from CONFIG: frames that can wait to be sent */
    u8      NumFilters;      /* from CONFIG: acceptance filters */
} XAxiCanController;

#define XAXICANCONTROLLER_COMPONENT_IS_READY 0x11111111U

/* Status codes of xstatus.h used here (values as in the Xilinx standalone BSP) */
#ifndef XST_NO_DATA
#define XST_NO_DATA 13L
#endif
#ifndef XST_DEVICE_BUSY
#define XST_DEVICE_BUSY 21L
#endif

#define XAXICANCONTROLLER_MAX_DATA   8U            /* data bytes per frame */
#define XAXICANCONTROLLER_STD_ID_MAX 0x7FFU        /* 11-bit identifier */
#define XAXICANCONTROLLER_EXT_ID_MAX 0x1FFFFFFFU   /* 29-bit identifier */

/* One CAN frame (TX and RX) */
typedef struct {
    u32 Id;          /* 11-bit (standard) or 29-bit (Extended = 1) identifier */
    u8  Extended;    /* 1 = extended (29-bit) identifier */
    u8  Remote;      /* 1 = remote frame (no data, Dlc is still sent) */
    u8  Dlc;         /* data length code 0..15 (9..15 = 8 bytes) */
    u8  Filter;      /* RX only: lowest acceptance filter the frame passed */
    u8  Data[XAXICANCONTROLLER_MAX_DATA];
} XAxiCanController_Frame;

/* Modes for XAxiCanController_SetMode (or-able, CTRL bits) */
#define XAXICANCONTROLLER_MODE_NORMAL      0U
#define XAXICANCONTROLLER_MODE_LISTEN_ONLY XAXICANCONTROLLER_CTRL_LISTEN_ONLY_MASK  /* never drive the bus */
#define XAXICANCONTROLLER_MODE_LOOPBACK    XAXICANCONTROLLER_CTRL_LOOPBACK_MASK     /* receive own frames, off the bus */
#define XAXICANCONTROLLER_MODE_ONE_SHOT    XAXICANCONTROLLER_CTRL_ONE_SHOT_MASK     /* no automatic retransmission */

/* Events / interrupt sources (EVENTS and IER bits) */
#define XAXICANCONTROLLER_EVENT_TX_DONE    XAXICANCONTROLLER_EVENTS_TX_DONE_MASK
#define XAXICANCONTROLLER_EVENT_ARB_LOST   XAXICANCONTROLLER_EVENTS_ARB_LOST_MASK
#define XAXICANCONTROLLER_EVENT_TX_DROPPED XAXICANCONTROLLER_EVENTS_TX_DROPPED_MASK
#define XAXICANCONTROLLER_EVENT_RX_OVERRUN XAXICANCONTROLLER_EVENTS_RX_OVERRUN_MASK
#define XAXICANCONTROLLER_EVENT_ERROR      XAXICANCONTROLLER_EVENTS_ERROR_MASK
#define XAXICANCONTROLLER_EVENT_RX_VALID   XAXICANCONTROLLER_EVENTS_RX_VALID_MASK   /* level: set while a frame waits */
#define XAXICANCONTROLLER_EVENT_STATE      XAXICANCONTROLLER_EVENTS_STATE_MASK      /* warning / passive / bus off changed */
#define XAXICANCONTROLLER_EVENT_ALL        (XAXICANCONTROLLER_EVENT_TX_DONE | XAXICANCONTROLLER_EVENT_ARB_LOST | \
                                            XAXICANCONTROLLER_EVENT_TX_DROPPED | XAXICANCONTROLLER_EVENT_RX_OVERRUN | \
                                            XAXICANCONTROLLER_EVENT_ERROR | XAXICANCONTROLLER_EVENT_RX_VALID | XAXICANCONTROLLER_EVENT_STATE)

/* Last error (STATUS.ERROR_TYPE) */
#define XAXICANCONTROLLER_ERR_NONE  0U
#define XAXICANCONTROLLER_ERR_BIT   1U
#define XAXICANCONTROLLER_ERR_STUFF 2U
#define XAXICANCONTROLLER_ERR_CRC   3U
#define XAXICANCONTROLLER_ERR_FORM  4U
#define XAXICANCONTROLLER_ERR_ACK   5U

/* Fault confinement state */
typedef struct {
    u8 Tec;          /* transmit error counter (255 = 255 or more) */
    u8 Rec;          /* receive error counter */
    u8 LastError;    /* XAXICANCONTROLLER_ERR_* */
    u8 Warning;      /* a counter is 96 or more */
    u8 Passive;      /* a counter is above 127 */
    u8 BusOff;       /* TEC above 255: off the bus, recovers after 128 x 11 recessive bits */
} XAxiCanController_ErrorStatus;

/* Initialization */
#ifndef SDT
XAxiCanController_Config *XAxiCanController_LookupConfig(u16 DeviceId);
#else
XAxiCanController_Config *XAxiCanController_LookupConfig(UINTPTR BaseAddress);
#endif
int XAxiCanController_CfgInitialize(XAxiCanController *InstancePtr, const XAxiCanController_Config *ConfigPtr, UINTPTR EffectiveAddr);
int XAxiCanController_Initialize(XAxiCanController *InstancePtr, UINTPTR BaseAddress);

/* Mode and reset */
int  XAxiCanController_SetMode(const XAxiCanController *InstancePtr, u32 Mode);
u32  XAxiCanController_GetMode(const XAxiCanController *InstancePtr);
void XAxiCanController_Reset(const XAxiCanController *InstancePtr);

/* Transmit */
int  XAxiCanController_IsTxReady(const XAxiCanController *InstancePtr);
int  XAxiCanController_Send(const XAxiCanController *InstancePtr, const XAxiCanController_Frame *FramePtr);
void XAxiCanController_AbortTx(const XAxiCanController *InstancePtr);
u32  XAxiCanController_GetTxDoneId(const XAxiCanController *InstancePtr);

/* Receive */
int  XAxiCanController_IsRxValid(const XAxiCanController *InstancePtr);
int  XAxiCanController_Recv(const XAxiCanController *InstancePtr, XAxiCanController_Frame *FramePtr);

/* Acceptance filters: a frame passes filter f when ((id ^ Id[f]) & Mask[f]) == 0
 * (29-bit compare; standard IDs have bits 28..11 = 0) */
int  XAxiCanController_SetFilter(const XAxiCanController *InstancePtr, u32 Index, u32 Id, u32 Mask);
int  XAxiCanController_SetFilters(const XAxiCanController *InstancePtr, const u32 *Ids, const u32 *Masks, u32 Count);
void XAxiCanController_AcceptAll(const XAxiCanController *InstancePtr);

/* Status, errors, events and interrupts */
void XAxiCanController_GetErrorStatus(const XAxiCanController *InstancePtr, XAxiCanController_ErrorStatus *StatusPtr);
u32  XAxiCanController_GetEvents(const XAxiCanController *InstancePtr);           /* pending XAXICANCONTROLLER_EVENT_* bits */
u32  XAxiCanController_GetAndClearEvents(const XAxiCanController *InstancePtr);   /* returns and clears exactly those */
int  XAxiCanController_AckEvents(const XAxiCanController *InstancePtr, u32 Mask);
int  XAxiCanController_InterruptEnable(const XAxiCanController *InstancePtr, u32 Mask);
int  XAxiCanController_InterruptDisable(const XAxiCanController *InstancePtr, u32 Mask);
u32  XAxiCanController_InterruptGetEnabled(const XAxiCanController *InstancePtr);

/* Data bytes of a DLC (0..15 -> 0..8) */
u32  XAxiCanController_DlcToLength(u8 Dlc);

#ifdef __cplusplus
}
#endif

#endif /* XAXI_CAN_CONTROLLER_H */
