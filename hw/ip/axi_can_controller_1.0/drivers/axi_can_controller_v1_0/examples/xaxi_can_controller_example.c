/******************************************************************************
 * xaxi_can_controller_example.c - example for AXI CAN Controller
 *
 * 1. Self-test in loopback mode (no bus needed): sends a frame and checks
 *    that it comes back unchanged.
 * 2. Normal mode with two acceptance filters (standard IDs 0x100..0x1FF and
 *    one extended ID): sends a counter frame on 0x321 every 100 ms and prints
 *    every frame received and the error state, for 10 s.
 *
 * Builds unchanged in the classic and SDT flows: both put
 * XPAR_AXI_CAN_CONTROLLER_0_BASEADDR into xparameters.h for an instance named
 * axi_can_controller_0.
 ******************************************************************************/
#include "xparameters.h"
#include "xil_printf.h"
#include "sleep.h"
#include "xaxi_can_controller.h"

#ifndef DEV_BASEADDR
#define DEV_BASEADDR XPAR_AXI_CAN_CONTROLLER_0_BASEADDR
#endif

static void PrintFrame(const XAxiCanController_Frame *F)
{
    u32 i;
    u32 Len = F->Remote ? 0U : XAxiCanController_DlcToLength(F->Dlc);

    xil_printf("  %s 0x%08x DLC %d%s filter %d:", F->Extended ? "ext" : "std", (unsigned int)F->Id,
               F->Dlc, F->Remote ? " RTR" : "", F->Filter);
    for (i = 0U; i < Len; i++) {
        xil_printf(" %02x", F->Data[i]);
    }
    xil_printf("\r\n");
}

/* Loopback self-test: the frame goes through the filters back into the RX FIFO */
static int LoopbackTest(const XAxiCanController *Dev)
{
    XAxiCanController_Frame Tx = { .Id = 0x5A5U, .Dlc = 8U,
                                   .Data = { 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88 } };
    XAxiCanController_Frame Rx;
    u32 i;
    u32 Wait;

    XAxiCanController_SetMode(Dev, XAXICANCONTROLLER_MODE_LOOPBACK);
    XAxiCanController_AcceptAll(Dev);
    usleep(1000);                                    /* bus integration: 11 bits */
    if (XAxiCanController_Send(Dev, &Tx) != XST_SUCCESS) {
        return XST_FAILURE;
    }
    for (Wait = 0U; Wait < 100U && !XAxiCanController_IsRxValid(Dev); Wait++) {
        usleep(100);
    }
    if (XAxiCanController_Recv(Dev, &Rx) != XST_SUCCESS || Rx.Id != Tx.Id || Rx.Dlc != Tx.Dlc ||
        Rx.Extended != 0U) {
        return XST_FAILURE;
    }
    for (i = 0U; i < 8U; i++) {
        if (Rx.Data[i] != Tx.Data[i]) {
            return XST_FAILURE;
        }
    }
    XAxiCanController_AckEvents(Dev, XAXICANCONTROLLER_EVENT_ALL);
    return XST_SUCCESS;
}

int main(void)
{
    XAxiCanController Dev;
    XAxiCanController_Frame Frame;
    XAxiCanController_ErrorStatus Err;
    const u32 Ids[2]   = { 0x100U, 0x18DAF110U };
    const u32 Masks[2] = { 0x1FFFFF00U, 0x1FFFFFFFU };   /* 0x100..0x1FF, one extended ID */
    u32 Events;
    u32 Tick;
    u8 Counter = 0U;
    int Status;

    xil_printf("\r\nAXI CAN Controller example\r\n");

    Status = XAxiCanController_Initialize(&Dev, DEV_BASEADDR);
    if (Status != XST_SUCCESS) {
        xil_printf("not found at 0x%08x (status %d)\r\n", (unsigned int)DEV_BASEADDR, Status);
        return XST_FAILURE;
    }
    xil_printf("found version %d.%d: RX FIFO %d, %d TX buffers, %d filters\r\n", Dev.VersionMajor,
               Dev.VersionMinor, Dev.RxFifoDepth, Dev.TxBuffers, Dev.NumFilters);

    if (LoopbackTest(&Dev) != XST_SUCCESS) {
        xil_printf("loopback self-test FAILED\r\n");
        return XST_FAILURE;
    }
    xil_printf("loopback self-test passed\r\n");

    /* normal mode on the bus */
    XAxiCanController_SetMode(&Dev, XAXICANCONTROLLER_MODE_NORMAL);
    if (XAxiCanController_SetFilters(&Dev, Ids, Masks, Dev.NumFilters >= 2U ? 2U : 1U) != XST_SUCCESS) {
        return XST_FAILURE;
    }

    for (Tick = 0U; Tick < 1000U; Tick++) {           /* 10 s in 10 ms steps */
        if (Tick % 10U == 0U) {
            XAxiCanController_Frame Tx = { .Id = 0x321U, .Dlc = 1U, .Data = { Counter } };
            if (XAxiCanController_Send(&Dev, &Tx) == XST_SUCCESS) {
                Counter++;
            }
        }
        while (XAxiCanController_Recv(&Dev, &Frame) == XST_SUCCESS) {
            PrintFrame(&Frame);
        }
        Events = XAxiCanController_GetAndClearEvents(&Dev);
        if (Events & (XAXICANCONTROLLER_EVENT_ERROR | XAXICANCONTROLLER_EVENT_STATE | XAXICANCONTROLLER_EVENT_RX_OVERRUN)) {
            XAxiCanController_GetErrorStatus(&Dev, &Err);
            xil_printf("events 0x%02x: TEC %d REC %d last error %d%s%s%s\r\n", (unsigned int)Events, Err.Tec,
                       Err.Rec, Err.LastError, Err.Warning ? " warning" : "", Err.Passive ? " passive" : "",
                       Err.BusOff ? " bus off" : "");
        }
        usleep(10000);
    }
    xil_printf("%d frames sent\r\n", Counter);
    return XST_SUCCESS;
}
