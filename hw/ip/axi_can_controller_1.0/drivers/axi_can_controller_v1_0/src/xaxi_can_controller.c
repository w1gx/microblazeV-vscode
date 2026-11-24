/******************************************************************************
 * xaxi_can_controller.c - driver implementation for AXI CAN Controller
 ******************************************************************************/
#include "xaxi_can_controller.h"

#define DATA_WORDS (XAXICANCONTROLLER_MAX_DATA / 4U)

#define IS_READY(p) ((p) != NULL && (p)->IsReady == XAXICANCONTROLLER_COMPONENT_IS_READY)

/* NULL or not initialised: XST_FAILURE (bad arguments give XST_INVALID_PARAM) */
#define CHECK_READY(p) \
    do { if (!IS_READY(p)) { return XST_FAILURE; } } while (0)

int XAxiCanController_CfgInitialize(XAxiCanController *InstancePtr, const XAxiCanController_Config *ConfigPtr, UINTPTR EffectiveAddr)
{
    (void)ConfigPtr;
    return XAxiCanController_Initialize(InstancePtr, EffectiveAddr);
}

/* Checks the ID register, so a wrong base address or a missing bitstream is
 * caught, and reads the configuration. The controller keeps its mode. */
int XAxiCanController_Initialize(XAxiCanController *InstancePtr, UINTPTR BaseAddress)
{
    u32 Id;
    u32 Cfg;

    if (InstancePtr == NULL) {
        return XST_INVALID_PARAM;
    }
    InstancePtr->IsReady     = 0U;
    InstancePtr->BaseAddress = BaseAddress;

    Id = XAxiCanController_ReadId(BaseAddress);
    if ((Id >> XAXICANCONTROLLER_ID_MAGIC_SHIFT) != XAXICANCONTROLLER_ID_MAGIC) {
        return XST_DEVICE_NOT_FOUND;
    }
    InstancePtr->VersionMajor = (u8)((Id & XAXICANCONTROLLER_ID_MAJOR_MASK) >> XAXICANCONTROLLER_ID_MAJOR_SHIFT);
    InstancePtr->VersionMinor = (u8)(Id & XAXICANCONTROLLER_ID_MINOR_MASK);

    Cfg = XAxiCanController_ReadConfig(BaseAddress);
    InstancePtr->RxFifoDepth = (u8)((Cfg & XAXICANCONTROLLER_CONFIG_RX_FIFO_DEPTH_MASK) >> XAXICANCONTROLLER_CONFIG_RX_FIFO_DEPTH_SHIFT);
    InstancePtr->TxBuffers   = (u8)((Cfg & XAXICANCONTROLLER_CONFIG_TX_BUFFERS_MASK) >> XAXICANCONTROLLER_CONFIG_TX_BUFFERS_SHIFT);
    InstancePtr->NumFilters  = (u8)((Cfg & XAXICANCONTROLLER_CONFIG_FILTERS_MASK) >> XAXICANCONTROLLER_CONFIG_FILTERS_SHIFT);

    InstancePtr->IsReady = XAXICANCONTROLLER_COMPONENT_IS_READY;
    return XST_SUCCESS;
}

/* Changes the mode in reset (the controller must not switch modes during a
 * frame): drops waiting frames and the RX buffer, clears the error counters;
 * the controller rejoins the bus after 11 recessive bits. */
int XAxiCanController_SetMode(const XAxiCanController *InstancePtr, u32 Mode)
{
    const u32 Modes = XAXICANCONTROLLER_MODE_LISTEN_ONLY | XAXICANCONTROLLER_MODE_LOOPBACK |
                      XAXICANCONTROLLER_MODE_ONE_SHOT;

    CHECK_READY(InstancePtr);
    if ((Mode & ~Modes) != 0U) {
        return XST_INVALID_PARAM;
    }
    XAxiCanController_WriteCtrl(InstancePtr->BaseAddress, Mode | XAXICANCONTROLLER_CTRL_RESET_MASK);
    XAxiCanController_WriteCtrl(InstancePtr->BaseAddress, Mode);
    return XST_SUCCESS;
}

u32 XAxiCanController_GetMode(const XAxiCanController *InstancePtr)
{
    if (!IS_READY(InstancePtr)) {
        return 0U;
    }
    return XAxiCanController_ReadCtrl(InstancePtr->BaseAddress) & ~XAXICANCONTROLLER_CTRL_RESET_MASK;
}

/* Software reset, mode kept */
void XAxiCanController_Reset(const XAxiCanController *InstancePtr)
{
    u32 Ctrl;

    if (!IS_READY(InstancePtr)) {
        return;
    }
    Ctrl = XAxiCanController_ReadCtrl(InstancePtr->BaseAddress) & ~XAXICANCONTROLLER_CTRL_RESET_MASK;
    XAxiCanController_WriteCtrl(InstancePtr->BaseAddress, Ctrl | XAXICANCONTROLLER_CTRL_RESET_MASK);
    XAxiCanController_WriteCtrl(InstancePtr->BaseAddress, Ctrl);
}

int XAxiCanController_IsTxReady(const XAxiCanController *InstancePtr)
{
    if (!IS_READY(InstancePtr)) {
        return 0;
    }
    return (XAxiCanController_ReadStatus(InstancePtr->BaseAddress) & XAXICANCONTROLLER_STATUS_TX_READY_MASK) != 0U;
}

/* Queues one frame. XST_DEVICE_BUSY: all TX buffers are taken (retry later or
 * wait for EVENT_TX_DONE). The frame is sent by bus priority and repeated after
 * errors / lost arbitration unless MODE_ONE_SHOT. */
int XAxiCanController_Send(const XAxiCanController *InstancePtr, const XAxiCanController_Frame *FramePtr)
{
    u32 Words[DATA_WORDS] = { 0U };
    u32 Dlc;
    u32 Len;
    u32 i;

    CHECK_READY(InstancePtr);
    if (FramePtr == NULL || FramePtr->Dlc > 15U ||
        FramePtr->Id > (FramePtr->Extended ? XAXICANCONTROLLER_EXT_ID_MAX : XAXICANCONTROLLER_STD_ID_MAX)) {
        return XST_INVALID_PARAM;
    }
    if (!XAxiCanController_IsTxReady(InstancePtr)) {
        return XST_DEVICE_BUSY;
    }
    Len = FramePtr->Remote ? 0U : XAxiCanController_DlcToLength(FramePtr->Dlc);
    for (i = 0U; i < Len; i++) {
        Words[i / 4U] |= (u32)FramePtr->Data[i] << (8U * (i % 4U));
    }
    Dlc = ((u32)FramePtr->Dlc << XAXICANCONTROLLER_TX_DLC_DLC_SHIFT) |
          (FramePtr->Extended ? XAXICANCONTROLLER_TX_DLC_EXT_MASK : 0U) |
          (FramePtr->Remote ? XAXICANCONTROLLER_TX_DLC_RTR_MASK : 0U);

    XAxiCanController_WriteTxId(InstancePtr->BaseAddress, FramePtr->Id);
    XAxiCanController_WriteTxDlc(InstancePtr->BaseAddress, Dlc);
    for (i = 0U; i < DATA_WORDS; i++) {
        XAxiCanController_WriteTxData(InstancePtr->BaseAddress, i, Words[i]);
    }
    XAxiCanController_WriteCmd(InstancePtr->BaseAddress, XAXICANCONTROLLER_CMD_TX_SEND_MASK);
    return XST_SUCCESS;
}

/* Drops all waiting frames (EVENT_TX_DROPPED); a frame on the bus is finished */
void XAxiCanController_AbortTx(const XAxiCanController *InstancePtr)
{
    if (IS_READY(InstancePtr)) {
        XAxiCanController_WriteCmd(InstancePtr->BaseAddress, XAXICANCONTROLLER_CMD_TX_ABORT_MASK);
    }
}

u32 XAxiCanController_GetTxDoneId(const XAxiCanController *InstancePtr)
{
    if (!IS_READY(InstancePtr)) {
        return 0U;
    }
    return XAxiCanController_ReadTxDoneId(InstancePtr->BaseAddress);
}

int XAxiCanController_IsRxValid(const XAxiCanController *InstancePtr)
{
    if (!IS_READY(InstancePtr)) {
        return 0;
    }
    return (XAxiCanController_ReadStatus(InstancePtr->BaseAddress) & XAXICANCONTROLLER_STATUS_RX_VALID_MASK) != 0U;
}

/* Takes the oldest received frame. XST_NO_DATA: nothing received. */
int XAxiCanController_Recv(const XAxiCanController *InstancePtr, XAxiCanController_Frame *FramePtr)
{
    u32 Dlc;
    u32 Word = 0U;
    u32 i;

    CHECK_READY(InstancePtr);
    if (FramePtr == NULL) {
        return XST_INVALID_PARAM;
    }
    if (!XAxiCanController_IsRxValid(InstancePtr)) {
        return XST_NO_DATA;
    }
    FramePtr->Id   = XAxiCanController_ReadRxId(InstancePtr->BaseAddress);
    Dlc            = XAxiCanController_ReadRxDlc(InstancePtr->BaseAddress);
    FramePtr->Dlc      = (u8)((Dlc & XAXICANCONTROLLER_RX_DLC_DLC_MASK) >> XAXICANCONTROLLER_RX_DLC_DLC_SHIFT);
    FramePtr->Extended = (u8)((Dlc & XAXICANCONTROLLER_RX_DLC_EXT_MASK) != 0U);
    FramePtr->Remote   = (u8)((Dlc & XAXICANCONTROLLER_RX_DLC_RTR_MASK) != 0U);
    FramePtr->Filter   = (u8)((Dlc & XAXICANCONTROLLER_RX_DLC_FILTER_MASK) >> XAXICANCONTROLLER_RX_DLC_FILTER_SHIFT);
    for (i = 0U; i < XAXICANCONTROLLER_MAX_DATA; i++) {
        if (i % 4U == 0U) {
            Word = XAxiCanController_ReadRxData(InstancePtr->BaseAddress, i / 4U);
        }
        FramePtr->Data[i] = (u8)(Word >> (8U * (i % 4U)));
    }
    XAxiCanController_WriteCmd(InstancePtr->BaseAddress, XAXICANCONTROLLER_CMD_RX_POP_MASK);
    return XST_SUCCESS;
}

int XAxiCanController_SetFilter(const XAxiCanController *InstancePtr, u32 Index, u32 Id, u32 Mask)
{
    CHECK_READY(InstancePtr);
    if (Index >= InstancePtr->NumFilters ||
        Id > XAXICANCONTROLLER_EXT_ID_MAX || Mask > XAXICANCONTROLLER_EXT_ID_MAX) {
        return XST_INVALID_PARAM;
    }
    XAxiCanController_WriteAccId(InstancePtr->BaseAddress, Index, Id);
    XAxiCanController_WriteAccMask(InstancePtr->BaseAddress, Index, Mask);
    return XST_SUCCESS;
}

/* Sets filters 0..Count-1; the remaining filters get filter 0, so they pass
 * nothing extra (a filter with mask 0 would pass every frame). */
int XAxiCanController_SetFilters(const XAxiCanController *InstancePtr, const u32 *Ids, const u32 *Masks, u32 Count)
{
    u32 i;
    int Status;

    CHECK_READY(InstancePtr);
    if (Ids == NULL || Masks == NULL || Count == 0U ||
        Count > InstancePtr->NumFilters) {
        return XST_INVALID_PARAM;
    }
    for (i = 0U; i < InstancePtr->NumFilters; i++) {
        u32 k = (i < Count) ? i : 0U;
        Status = XAxiCanController_SetFilter(InstancePtr, i, Ids[k], Masks[k]);
        if (Status != XST_SUCCESS) {
            return Status;
        }
    }
    return XST_SUCCESS;
}

void XAxiCanController_AcceptAll(const XAxiCanController *InstancePtr)
{
    const u32 Zero = 0U;

    (void)XAxiCanController_SetFilters(InstancePtr, &Zero, &Zero, 1U);
}

void XAxiCanController_GetErrorStatus(const XAxiCanController *InstancePtr, XAxiCanController_ErrorStatus *StatusPtr)
{
    u32 S;

    if (!IS_READY(InstancePtr) || StatusPtr == NULL) {
        return;
    }
    S = XAxiCanController_ReadStatus(InstancePtr->BaseAddress);
    StatusPtr->Tec       = (u8)((S & XAXICANCONTROLLER_STATUS_TEC_MASK) >> XAXICANCONTROLLER_STATUS_TEC_SHIFT);
    StatusPtr->Rec       = (u8)((S & XAXICANCONTROLLER_STATUS_REC_MASK) >> XAXICANCONTROLLER_STATUS_REC_SHIFT);
    StatusPtr->LastError = (u8)((S & XAXICANCONTROLLER_STATUS_ERROR_TYPE_MASK) >> XAXICANCONTROLLER_STATUS_ERROR_TYPE_SHIFT);
    StatusPtr->Warning   = (u8)((S & XAXICANCONTROLLER_STATUS_ERROR_WARNING_MASK) != 0U);
    StatusPtr->Passive   = (u8)((S & XAXICANCONTROLLER_STATUS_ERROR_PASSIVE_MASK) != 0U);
    StatusPtr->BusOff    = (u8)((S & XAXICANCONTROLLER_STATUS_BUS_OFF_MASK) != 0U);
}

u32 XAxiCanController_GetEvents(const XAxiCanController *InstancePtr)
{
    if (!IS_READY(InstancePtr)) {
        return 0U;
    }
    return XAxiCanController_ReadEvents(InstancePtr->BaseAddress);
}

/* Clears only the bits it returns: an event that arrives in between stays
 * pending. EVENT_RX_VALID is a level: it is set again at once while frames wait. */
u32 XAxiCanController_GetAndClearEvents(const XAxiCanController *InstancePtr)
{
    u32 Events;

    if (!IS_READY(InstancePtr)) {
        return 0U;
    }
    Events = XAxiCanController_ReadEvents(InstancePtr->BaseAddress);
    if (Events != 0U) {
        XAxiCanController_ClearEvents(InstancePtr->BaseAddress, Events);
    }
    return Events;
}

/* Clears events (write 1 to clear). EVENT_RX_VALID stays set while frames wait:
 * clear it after Recv() returned XST_NO_DATA. */
int XAxiCanController_AckEvents(const XAxiCanController *InstancePtr, u32 Mask)
{
    CHECK_READY(InstancePtr);
    if ((Mask & ~XAXICANCONTROLLER_EVENT_ALL) != 0U) {
        return XST_INVALID_PARAM;
    }
    XAxiCanController_ClearEvents(InstancePtr->BaseAddress, Mask);
    return XST_SUCCESS;
}

int XAxiCanController_InterruptEnable(const XAxiCanController *InstancePtr, u32 Mask)
{
    CHECK_READY(InstancePtr);
    if ((Mask & ~XAXICANCONTROLLER_EVENT_ALL) != 0U) {
        return XST_INVALID_PARAM;
    }
    XAxiCanController_WriteIer(InstancePtr->BaseAddress, XAxiCanController_ReadIer(InstancePtr->BaseAddress) | Mask);
    return XST_SUCCESS;
}

int XAxiCanController_InterruptDisable(const XAxiCanController *InstancePtr, u32 Mask)
{
    CHECK_READY(InstancePtr);
    if ((Mask & ~XAXICANCONTROLLER_EVENT_ALL) != 0U) {
        return XST_INVALID_PARAM;
    }
    XAxiCanController_WriteIer(InstancePtr->BaseAddress, XAxiCanController_ReadIer(InstancePtr->BaseAddress) & ~Mask);
    return XST_SUCCESS;
}

u32 XAxiCanController_InterruptGetEnabled(const XAxiCanController *InstancePtr)
{
    if (!IS_READY(InstancePtr)) {
        return 0U;
    }
    return XAxiCanController_ReadIer(InstancePtr->BaseAddress);
}

u32 XAxiCanController_DlcToLength(u8 Dlc)
{
    return (Dlc > 8U) ? 8U : (u32)Dlc;
}
