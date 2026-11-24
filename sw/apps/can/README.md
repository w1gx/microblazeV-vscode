# CAN demo

Demo for the W1GX AXI CAN controller (`axi_can_controller_0` at `0x44A10000`, IRQ 6), runs from the
local memory. Build and load with `make APP=can && make program APP=can` (or `make flash APP=can`),
console with `make console`.

Everything runs on the controller's interrupt: `modules/can/can_node.c` connects `irq` with
`XSetupInterruptSystem()` (the driver's config table has `IntrId` / `IntrParent`), the handler moves
received frames into a 32-frame ring buffer and counts the events, and the main loop prints them.

1. **Loopback self-test** (no bus, no transceiver): a standard 8-byte, an extended 3-byte, a remote and
   an empty frame are sent in loopback mode and must come back unchanged, with one TX-done and one
   RX interrupt each. Prints `PASS` or `FAIL`.
2. **Bus mode**, all frames accepted:

   | Frame | ID | Data |
   | ----- | -- | ---- |
   | heartbeat, every second | `0x100` | counter, switches SW0..3 |
   | BTN0..BTN3 pressed | `0x120`..`0x123` | switches, button number |

   Every received frame is printed, and byte 0 of data frames goes to LD4..LD7. Bus errors and error
   state changes (warning, passive, bus off) are printed with TEC and REC.

The demo starts in **one-shot** mode: each frame is tried once. A board alone on the bus gets no ACK, so it
reports one ACK error per frame ("no ACK: is another node on the bus?") instead of repeating the frame for
ever. Press `o` to switch to normal retransmission.

| Key | Action |
| --- | ------ |
| `s` | status: TEC / REC, error state, last error, counters |
| `l` | run the loopback test again, then back on the bus |
| `o` | one-shot on / off (resets the controller, waiting frames are dropped) |
| `a` | abort: drop waiting TX frames |
| `?` | help |

**Wiring.** `can_tx` is ChipKit IO32 (pin R15) → transceiver TXD, `can_rx` is IO33 (P15) ← RXD. Use a
3.3 V transceiver (e.g. SN65HVD230) and terminate the bus with 120 Ω at both ends. Bit rate 500 kbit/s
(IP parameter `C_BIT_RATE`, 18 time quanta per bit; 81.25 MHz gives 501.5 kbit/s, +0.3 %). On a Linux PC
with a SocketCAN adapter:

```sh
sudo ip link set can0 up type can bitrate 500000
candump can0              # heartbeat 0x100 and the button frames
cansend can0 200#05       # the board prints it and shows 5 on LD4..LD7
```

**Troubleshooting.**

- `TX ... skipped: all TX buffers busy` with TEC/REC 0: nothing was ever sent, because the controller never saw
  11 recessive bits on `can_rx`. Check transceiver RXD → IO33, its power and standby pin.
- Board shows TX lines and no ACK errors, but `candump` is silent and `ip -s link show can0` has RX/TX packets 0:
  the adapter's CAN core is ACKing but its USB side is stuck (seen with a gs_usb/candleLight adapter). Unplug and
  replug it, then bring `can0` up again. A quick cross-check: `ip link set can0 down` must give ACK errors on the
  board.
