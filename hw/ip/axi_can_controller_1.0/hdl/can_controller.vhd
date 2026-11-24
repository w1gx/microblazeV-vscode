--------------------------------------------------------------------------------
-- CAN 2.0B controller with AXI-stream style transmit and receive streams
-- w1gx
-- Created 2026-11-19
--------------------------------------------------------------------------------
-- Classical CAN (ISO 11898-1, CAN 2.0A and 2.0B): standard (11-bit) and
-- extended (29-bit) identifiers, data and remote frames, 0 to 8 data bytes.
-- Connects to a CAN transceiver: o_can_tx -> TXD, RXD -> i_can_rx
-- ('1' = recessive, '0' = dominant).
--
-- TX (slave):  one frame (i_tx_id, i_tx_ext, i_tx_rtr, i_tx_dlc,
--              i_tx_data) is accepted on a rising clk edge with
--              i_tx_tvalid = '1' and o_tx_tready = '1'. It waits in one of
--              g_TX_BUFFERS buffers; o_tx_tready is high while a buffer is
--              free. Of the waiting frames the one with the highest bus
--              priority (lowest identifier) is sent at the next bus idle; it
--              is repeated after a lost arbitration or an error until it went
--              through: then o_tx_done pulses with its identifier on
--              o_tx_done_id and its buffer is free again. o_tx_arb_lost pulses
--              when another node won the arbitration (the frame is retried).
--              With i_one_shot = '1' a frame is tried once only: after a lost
--              arbitration or an error it is dropped with an o_tx_dropped
--              pulse. i_tx_abort = '1' drops all waiting frames at the next
--              bit boundary at which the controller is not transmitting (a
--              frame on the bus is finished; on error it is not repeated),
--              also with an o_tx_dropped pulse.
--
-- RX (master): every valid frame of another node whose identifier passes
--              one of the g_FILTERS acceptance filters, filter f:
--              ((id xor i_acc_id(f)) and i_acc_mask(f)) = 0 (29 bits each,
--              filter 0 in bits 28..0), goes onto the RX stream (o_rx_*,
--              o_rx_filter = the lowest matching filter), held until
--              i_rx_tready = '1'. Frames are ACKed whether they pass a filter
--              or not. Own frames are not received. o_rx_overrun pulses when a
--              frame arrives while the buffer (g_RX_FIFO_DEPTH frames in a
--              w1gxlib.fifo plus one output register) is full; the new frame
--              is dropped.
--
-- Modes: i_listen_only = '1': o_can_tx stays recessive; no ACK, no error
--              or overload flags, no transmission (frames wait), error
--              counters unchanged; valid frames are received, errors still
--              pulse o_error. i_loopback = '1': o_can_tx stays recessive and
--              i_can_rx is ignored; the controller receives what it sends
--              (own frames on the RX stream, no ACK needed). Change the modes
--              only while the bus is idle (or in reset).
--
-- Data byte 0 (the first on the bus) is i_tx_data / o_rx_data (7 downto 0),
-- byte 7 is (63 downto 56); every byte goes out MSB first. Standard frames
-- use id (10 downto 0). Remote frames carry no data; DLC 9 to 15 is sent as
-- is and means 8 data bytes.
--
-- Errors: bit, stuff, CRC, form and ACK errors start an error frame (the CRC
-- error after the ACK delimiter) and give a 1-cycle o_error pulse with the
-- error in o_error_type (held until the next error). Overload frames are
-- answered as required (dominant bit in the intermission, the last bit of EOF
-- of a receiver or the last bit of a delimiter); the controller never asks for
-- one itself. Fault confinement as in the standard: transmit / receive error
-- counters, error passive (passive error flag, suspend transmission) when one
-- of them is above 127, bus off when the transmit error counter is above 255.
-- o_error_warning is '1' while a counter is 96 or more.
-- Bus off ends automatically after 128 times 11 recessive bits, with both
-- counters cleared. After reset the controller waits for 11 recessive bits
-- (bus integration) before it takes part in bus traffic.
--
-- Bit timing: one bit is g_TQ_PER_BIT time quanta (tq) of
-- round(g_CLOCK_FREQUENCY / (g_BIT_RATE * g_TQ_PER_BIT)) clk cycles:
-- sync segment (1 tq), phase segment 1 (g_TQ_PER_BIT - 1 - g_PHASE_SEG2 tq),
-- sample point, phase segment 2 (g_PHASE_SEG2 tq). Hard synchronisation on
-- the start of frame edge, resynchronisation on every other recessive to
-- dominant edge by up to g_SJW tq (none on positive phase errors while the
-- controller drives a dominant bit itself). i_can_rx goes through a 2-FF
-- synchroniser; o_can_tx changes at the start of the sync segment.
--
-- Pipeline (for a fast clock, 100 MHz and more): each bit is processed in three
-- steps after its sample point (P1a: stuff bit / bit error / arbitration, P1b:
-- the fields of the frame, P2: error counters, bus off, TX buffers and the
-- next bit to send). If phase segment 2 is at least 4 clk they run one clk
-- apart (RX stream 3 clk, o_tx_done and o_error 4 clk after the sample point),
-- else all in the clk of the sample point (outputs 1 clk after it). The TX
-- buffers are scanned for the highest priority one buffer per 2 clk; the
-- acceptance filters and data bytes are registered before EOF.
--
-- Reset is synchronous: the bus is released (recessive) at once, the pending
-- TX frame and the RX buffer are dropped and the error counters cleared.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity can_controller is
  generic (
    g_CLOCK_FREQUENCY : positive              := 12_000_000;  -- Hz
    g_BIT_RATE        : positive              := 500_000;     -- bit/s
    g_TQ_PER_BIT      : positive range 8 to 25 := 12;         -- time quanta per bit
    g_PHASE_SEG2      : positive range 1 to 8  := 2;          -- tq after the sample point
    g_SJW             : positive range 1 to 4  := 2;          -- resynchronisation jump width, tq
    g_RX_FIFO_DEPTH   : natural                := 4;          -- frames, 0 = no FIFO
    g_TX_BUFFERS      : positive range 1 to 8  := 1;          -- frames waiting to be sent
    g_FILTERS         : positive range 1 to 32 := 1           -- acceptance filters
  );
  port (
    clk             : in  std_logic;
    rst             : in  std_logic;   -- synchronous, active high
    -- TX stream in
    i_tx_id         : in  std_logic_vector(28 downto 0);
    i_tx_ext        : in  std_logic;   -- '1' = extended (29-bit) identifier
    i_tx_rtr        : in  std_logic;   -- '1' = remote frame
    i_tx_dlc        : in  std_logic_vector(3 downto 0);
    i_tx_data       : in  std_logic_vector(63 downto 0);
    i_tx_tvalid     : in  std_logic;
    o_tx_tready     : out std_logic;
    i_tx_abort      : in  std_logic;
    o_tx_done       : out std_logic;   -- 1-cycle pulse: frame sent
    o_tx_arb_lost   : out std_logic;   -- 1-cycle pulse: arbitration lost, frame retried
    i_one_shot      : in  std_logic := '0';   -- '1' = try each frame once
    o_tx_dropped    : out std_logic;   -- 1-cycle pulse: frame(s) dropped (one shot failed, abort)
    o_tx_done_id    : out std_logic_vector(28 downto 0);   -- identifier of the frame of the last o_tx_done
    -- RX stream out
    o_rx_id         : out std_logic_vector(28 downto 0);
    o_rx_ext        : out std_logic;
    o_rx_rtr        : out std_logic;
    o_rx_dlc        : out std_logic_vector(3 downto 0);
    o_rx_data       : out std_logic_vector(63 downto 0);
    o_rx_tvalid     : out std_logic;
    i_rx_tready     : in  std_logic;
    o_rx_overrun    : out std_logic;   -- 1-cycle pulse: RX buffer full, frame dropped
    o_rx_filter     : out std_logic_vector(4 downto 0);    -- filter the frame passed
    -- acceptance filters, filter f in bits 29 * f + 28 .. 29 * f
    i_acc_id        : in  std_logic_vector(29 * g_FILTERS - 1 downto 0);
    i_acc_mask      : in  std_logic_vector(29 * g_FILTERS - 1 downto 0);   -- '1' = bit compared
    -- errors and fault confinement
    o_error         : out std_logic;   -- 1-cycle pulse: error detected, error frame follows
    o_error_type    : out std_logic_vector(2 downto 0);    -- 1 bit, 2 stuff, 3 CRC, 4 form, 5 ACK
    o_error_passive : out std_logic;
    o_bus_off       : out std_logic;
    o_error_warning : out std_logic;   -- an error counter is 96 or more
    o_tec           : out std_logic_vector(7 downto 0);    -- transmit error counter (255 = 255 or more)
    o_rec           : out std_logic_vector(7 downto 0);    -- receive error counter
    -- modes
    i_listen_only   : in  std_logic := '0';
    i_loopback      : in  std_logic := '0';
    -- bus (transceiver)
    o_can_tx        : out std_logic;   -- '0' = dominant
    i_can_rx        : in  std_logic    -- asynchronous
  );
end can_controller;

architecture rtl of can_controller is

  -- integer maximum / minimum: VHDL-2008 has them predefined, but Quartus Prime
  -- Lite / Standard does not
  function maximum(a, b : integer) return integer is
  begin
    if a > b then return a; else return b; end if;
  end function;

  function minimum(a, b : integer) return integer is
  begin
    if a < b then return a; else return b; end if;
  end function;

  -- clock cycles per time quantum; checked here, during elaboration, so a
  -- clock that does not fit the bit rate stops with a clear message
  function presc_calc return positive is
    constant c_div  : positive := g_BIT_RATE * g_TQ_PER_BIT;
    constant c      : natural  := (g_CLOCK_FREQUENCY + c_div / 2) / c_div;
    constant c_real : natural  := g_CLOCK_FREQUENCY / maximum(c, 1) / g_TQ_PER_BIT;   -- bit/s
  begin
    assert c >= 1
      report "can_controller: g_CLOCK_FREQUENCY (" & integer'image(g_CLOCK_FREQUENCY) & " Hz) must be at least g_TQ_PER_BIT * g_BIT_RATE ("
             & integer'image(g_TQ_PER_BIT) & " * " & integer'image(g_BIT_RATE) & " bit/s)"
      severity failure;
    assert abs (c_real - g_BIT_RATE) * 200 <= g_BIT_RATE
      report "can_controller: bit rate " & integer'image(c_real) & " bit/s is more than 0.5 % off g_BIT_RATE ("
             & integer'image(g_BIT_RATE) & " bit/s); choose g_TQ_PER_BIT so that g_CLOCK_FREQUENCY / (g_BIT_RATE * g_TQ_PER_BIT) is an integer"
      severity failure;
    assert g_SJW <= g_PHASE_SEG2 and g_SJW <= g_TQ_PER_BIT - 1 - g_PHASE_SEG2
      report "can_controller: g_SJW must not be larger than either phase segment" severity failure;
    return maximum(c, 1);
  end function;

  constant c_PRESC     : positive := presc_calc;
  constant c_NTQ       : positive := g_TQ_PER_BIT;
  constant c_SAMPLE_TQ : natural  := c_NTQ - 1 - g_PHASE_SEG2;   -- last tq before the sample point

  -- Bit processing after the sample point (see CAN_PROC): pipelined over 4 clk
  -- (P1a, P1b, P2 one clk each, for a fast clock) if phase segment 2 is at
  -- least that long, else all in the clk of the sample point. c_IPT: clk from
  -- the sample point until the next bit to send is known.
  constant c_PIPE : boolean  := c_PRESC * g_PHASE_SEG2 >= 4;
  function ipt_calc return positive is
  begin
    if c_PIPE then return 4; end if;
    return 1;
  end function;
  constant c_IPT  : positive := ipt_calc;

  -- bit timing, per tq_cnt value, for the next clk (pl: last clk of the tq);
  -- tables instead of arithmetic keep the bit timing to a few LUT levels
  type t_tq_info is record
    rs_ok       : std_logic;   -- an edge here resynchronises (not in the sync segment)
    late        : std_logic;   -- edge before the sample point (phase segment 1)
    late_rst    : std_logic;   -- late edge within g_SJW: restart the sync segment
    early_start : std_logic;   -- early edge within g_SJW: the next bit starts now
    at_end      : std_logic;   -- end of the bit
    at_sample   : std_logic;   -- sample point
    late_tq     : natural range 0 to c_NTQ - 1;   -- tq after a late edge
    early_tq    : natural range 0 to c_NTQ - 1;   -- tq after an early edge
    nxt         : natural range 0 to c_NTQ - 1;   -- tq without an edge
  end record;
  type t_tq_tab is array (0 to c_NTQ - 1) of t_tq_info;

  function tq_tab(pl : boolean) return t_tq_tab is
    variable r  : t_tq_tab;
    variable vn : natural;
    function sl(c : boolean) return std_logic is
    begin
      if c then return '1'; end if;
      return '0';
    end function;
  begin
    for t in 0 to c_NTQ - 1 loop
      if pl then vn := t + 1; else vn := t; end if;   -- tq in the next clk
      r(t).rs_ok       := sl(vn /= 0 and vn /= c_NTQ);
      r(t).late        := sl(t <= c_SAMPLE_TQ);
      r(t).late_rst    := sl(vn <= g_SJW);
      r(t).early_start := sl(c_NTQ - vn <= g_SJW);
      r(t).at_end      := sl(vn = c_NTQ);
      r(t).at_sample   := sl(pl and t = c_SAMPLE_TQ);
      r(t).late_tq     := 0;
      r(t).early_tq    := 0;
      if vn > g_SJW and vn - g_SJW < c_NTQ then r(t).late_tq := vn - g_SJW; end if;
      if vn + g_SJW < c_NTQ then r(t).early_tq := vn + g_SJW; end if;
      r(t).nxt := vn mod c_NTQ;
    end loop;
    return r;
  end function;

  constant c_TQ_TAB0 : t_tq_tab := tq_tab(false);
  constant c_TQ_TAB1 : t_tq_tab := tq_tab(true);

  constant c_CRC_POLY : std_logic_vector(14 downto 0) := "100010110011001";   -- x^15 + x^14 + x^10 + x^8 + x^7 + x^4 + x^3 + 1

  constant c_ERR_BIT   : std_logic_vector(2 downto 0) := "001";
  constant c_ERR_STUFF : std_logic_vector(2 downto 0) := "010";
  constant c_ERR_CRC   : std_logic_vector(2 downto 0) := "011";
  constant c_ERR_FORM  : std_logic_vector(2 downto 0) := "100";
  constant c_ERR_ACK   : std_logic_vector(2 downto 0) := "101";

  -- field of the bit that is sampled next
  type t_field is (
    F_INTEGRATE,     -- after reset: wait for 11 recessive bits
    F_IDLE,          -- bus idle, a dominant bit is a start of frame (SOF)
    F_ID_A,          -- identifier (11 bits; base identifier of an extended frame)
    F_SRR_RTR,       -- RTR of a standard frame, SRR of an extended frame
    F_IDE,           -- '0' standard, '1' extended
    F_ID_B,          -- identifier extension (18 bits)
    F_RTR,           -- RTR of an extended frame
    F_R1,            -- reserved bit of an extended frame
    F_R0,            -- reserved bit
    F_DLC,           -- data length code (4 bits)
    F_DATA,          -- 0 to 64 data bits
    F_CRC,           -- CRC sequence (15 bits)
    F_CRC_DELIM,     -- CRC delimiter (recessive), last bit with bit stuffing
    F_ACK_SLOT,      -- receivers send dominant
    F_ACK_DELIM,     -- recessive
    F_EOF,           -- end of frame (7 recessive bits)
    F_INTERMISSION,  -- 3 recessive bits
    F_SUSPEND,       -- error passive transmitter: 8 more bits before it may send
    F_FLAG,          -- error or overload flag (6 bits)
    F_FLAG_WAIT,     -- after the flag: recessive sent, wait for a recessive bit
    F_DELIM,         -- error / overload delimiter (8 recessive bits)
    F_BUS_OFF        -- bus off: wait for 128 x 11 recessive bits
  );

  -- bits of a frame after SOF up to the end of the data field, MSB first
  -- (left aligned; the controller shifts out only as many bits as the frame has)
  function frame_bits(id  : std_logic_vector(28 downto 0); ext, rtr : std_logic;
                      dlc : std_logic_vector(3 downto 0); data : std_logic_vector(63 downto 0))
    return std_logic_vector is
    variable v   : std_logic_vector(101 downto 0) := (others => '1');
    variable seq : std_logic_vector(63 downto 0);
  begin
    for i in 0 to 7 loop
      seq(63 - 8 * i downto 56 - 8 * i) := data(8 * i + 7 downto 8 * i);
    end loop;
    if ext = '0' then
      v(101 downto 91) := id(10 downto 0);
      v(90)            := rtr;
      v(89)            := '0';   -- IDE
      v(88)            := '0';   -- r0
      v(87 downto 84)  := dlc;
      v(83 downto 20)  := seq;
    else
      v(101 downto 91) := id(28 downto 18);
      v(90)            := '1';   -- SRR
      v(89)            := '1';   -- IDE
      v(88 downto 71)  := id(17 downto 0);
      v(70)            := rtr;
      v(69)            := '0';   -- r1
      v(68)            := '0';   -- r0
      v(67 downto 64)  := dlc;
      v(63 downto 0)   := seq;
    end if;
    return v;
  end function;

  function crc_step(crc : std_logic_vector(14 downto 0); b : std_logic) return std_logic_vector is
  begin
    if (b xor crc(14)) = '1' then
      return (crc(13 downto 0) & '0') xor c_CRC_POLY;
    end if;
    return crc(13 downto 0) & '0';
  end function;

  -- bus priority of a frame: the arbitration field as an unsigned number (lower wins)
  function priority(id : std_logic_vector(28 downto 0); ext, rtr : std_logic) return unsigned is
  begin
    if ext = '0' then
      return unsigned(id(10 downto 0) & rtr & '0' & (17 downto 0 => '0') & '0');
    end if;
    return unsigned(id(28 downto 18) & '1' & '1' & id(17 downto 0) & rtr);
  end function;

  function to_sl(c : boolean) return std_logic is
  begin
    if c then return '1'; end if;
    return '0';
  end function;

  function any(v : std_logic_vector) return std_logic is
  begin
    if v = (v'range => '0') then return '0'; end if;
    return '1';
  end function;

  -- RX stream word: filter & id & ext & rtr & dlc & data
  constant c_RX_WIDTH : positive := 5 + 29 + 1 + 1 + 4 + 64;

  type t_id_arr   is array (0 to g_TX_BUFFERS - 1) of std_logic_vector(28 downto 0);
  type t_dlc_arr  is array (0 to g_TX_BUFFERS - 1) of std_logic_vector(3 downto 0);
  type t_data_arr is array (0 to g_TX_BUFFERS - 1) of std_logic_vector(63 downto 0);

  -- error counter changes found by P1, applied by P2
  type t_tec_op is (TEC_NONE, TEC_ADD8, TEC_DEC, TEC_CLR);
  type t_rec_op is (REC_NONE, REC_ADD1, REC_ADD8, REC_DEC, REC_CLR);
  -- the sampled bit as classified by P1a
  type t_cls is (CLS_NORMAL, CLS_STUFF_OK, CLS_ARB_LOST, CLS_BIT_ERR, CLS_STUFF_ERR, CLS_STUFF_ERR_ARB);

  -- bus input and bit timing
  signal rx_sync     : std_logic_vector(1 downto 0) := (others => '1');
  signal rx_s        : std_logic;
  signal rx_prev     : std_logic := '1';
  signal presc_cnt   : natural range 0 to c_PRESC - 1 := 0;
  signal presc_last  : std_logic := to_sl(c_PRESC = 1);   -- presc_cnt = c_PRESC - 1
  signal tq_cnt      : natural range 0 to c_NTQ - 1 := 0;
  signal synced      : std_logic := '0';   -- (re)synchronised in this bit already
  signal tq_info     : t_tq_info;          -- bit timing of this clk
  signal edge        : std_logic;          -- recessive to dominant edge to synchronise on
  signal smp_now     : std_logic;          -- this clk is the sample point
  signal sample      : std_logic := '0';   -- 1-cycle pulse after every sample point (c_PIPE: starts P1a)
  signal smp_bit     : std_logic := '1';   -- bus level at the last sample point
  signal prev_sample : std_logic := '1';   -- bus level at the last sample point (for the edge detection)
  signal ipt_cnt     : natural range 0 to c_IPT - 1 := 0;   -- clk until tx_next is valid
  signal tx_late     : std_logic := '0';   -- the bit started before tx_next was valid
  signal hs_en       : std_logic := '0';   -- hard synchronisation allowed (bus idle, from P2)
  signal can_tx      : std_logic := '1';
  signal rx_in       : std_logic;
  signal tx_next     : std_logic := '1';   -- driven at the next sync segment (from P2)

  -- bit processing: P1a -> P1b (registered if c_PIPE)
  type t_field_set is array (t_field) of std_logic;
  type t_p1a is record
    b         : std_logic;   -- the bit
    cls       : t_cls;       -- what it is
    stuff_bit : std_logic;   -- it is a stuff bit
    err       : std_logic;   -- it is a stuff or bit error
    c2, c3, c5, c6, c7, c10, c14, c17, clast : std_logic;   -- cnt = n, cnt = data_last
    fs_nz, fs5, dom7, bor10, bos127 : std_logic;   -- flag_same /= 0, = 5, dom_cnt = 7, bo_rcnt = 10, bo_seq = 127
    shift_f   : std_logic;   -- field from ID_A to DATA (TX shift register)
    crc_f     : std_logic;   -- field from ID_A to CRC (CRC register)
    go        : t_field_set; -- P1b of a normal bit (no stuff bit, no error) in field f
    rx        : std_logic;   -- P1b of the last but one EOF bit of a frame to receive
    join      : std_logic;   -- a frame is selected and may be sent (join the arbitration)
    join_int  : std_logic;   -- ... also in the 3rd intermission bit (not suspended)
  end record;
  constant c_P1A_NONE : t_p1a := (
    b => '1', cls => CLS_NORMAL, stuff_bit => '0', err => '0',
    c2 => '0', c3 => '0', c5 => '0', c6 => '0', c7 => '0', c10 => '0', c14 => '0', c17 => '0', clast => '0',
    fs_nz => '0', fs5 => '0', dom7 => '0', bor10 => '0', bos127 => '0', shift_f => '0', crc_f => '0',
    go => (others => '0'), rx => '0', join => '0', join_int => '0');

  -- P1b -> P2 (registered if c_PIPE)
  type t_p1 is record
    field     : t_field;
    cnt       : natural range 0 to 63;
    tx_active : std_logic;
    attempt   : std_logic;
    done      : std_logic;   -- frame sent
    tec_op    : t_tec_op;
    rec_op    : t_rec_op;
    flag      : std_logic;   -- error or overload flag requested
    flag_ovl  : std_logic;   -- ... and it is an overload flag
    error     : std_logic;   -- error detected
    err_type  : std_logic_vector(2 downto 0);
    ack_set   : std_logic;   -- passive ACK error: ack_defer <= '1'
    ack_clr   : std_logic;   -- ack_defer <= '0'
    stuff     : std_logic;   -- stuff_en, same_cnt = 5, last_bit, crc(14), tx_shift(101) after the bit
    same5     : std_logic;
    last      : std_logic;
    crc14     : std_logic;
    shift101  : std_logic;
  end record;
  constant c_P1_NONE : t_p1 := (
    field => F_INTEGRATE, cnt => 0, tx_active => '0', attempt => '0', done => '0', tec_op => TEC_NONE,
    rec_op => REC_NONE, flag => '0', flag_ovl => '0', error => '0', err_type => "000", ack_set => '0',
    ack_clr => '0', stuff => '0', same5 => '0', last => '1', crc14 => '0', shift101 => '1');

  signal smp_d1 : std_logic := '0';   -- (c_PIPE) P1b: one clk after P1a
  signal smp_d2 : std_logic := '0';   -- (c_PIPE) P2: two clk after P1a
  signal a      : t_p1a := c_P1A_NONE;
  signal p1     : t_p1  := c_P1_NONE;

  -- frame
  signal field     : t_field := F_INTEGRATE;
  signal cnt       : natural range 0 to 63 := 0;   -- bit within the field
  signal stuff_en  : std_logic := '0';
  signal same_cnt  : natural range 0 to 5 := 0;    -- equal bits in a row (bit stuffing)
  signal last_bit  : std_logic := '1';
  signal crc       : std_logic_vector(14 downto 0) := (others => '0');
  signal crc_err   : std_logic := '0';   -- CRC remainder not 0 (valid after the CRC sequence)
  signal data_last : natural range 0 to 63 := 0;   -- number of the last data bit
  signal id_a      : std_logic_vector(10 downto 0) := (others => '0');
  signal id_b      : std_logic_vector(17 downto 0) := (others => '0');
  signal ext       : std_logic := '0';
  signal rtr       : std_logic := '0';
  signal dlc       : std_logic_vector(3 downto 0) := (others => '0');
  signal dshift    : std_logic_vector(63 downto 0) := (others => '0');   -- data bits as received
  signal data      : std_logic_vector(63 downto 0) := (others => '0');   -- ... in byte order

  -- transmitter
  signal buf_valid    : std_logic_vector(g_TX_BUFFERS - 1 downto 0) := (others => '0');
  signal buf_chg      : std_logic := '0';   -- buf_valid changed at the last clk edge
  signal buf_id       : t_id_arr   := (others => (others => '0'));
  signal buf_ext      : std_logic_vector(g_TX_BUFFERS - 1 downto 0) := (others => '0');
  signal buf_rtr      : std_logic_vector(g_TX_BUFFERS - 1 downto 0) := (others => '0');
  signal buf_dlc      : t_dlc_arr  := (others => (others => '0'));
  signal buf_data     : t_data_arr := (others => (others => '0'));
  signal tx_cur       : natural range 0 to g_TX_BUFFERS - 1 := 0;   -- frame of the current attempt
  signal tx_attempt   : std_logic := '0';   -- an attempt of tx_cur is in progress
  signal tx_abort_req : std_logic := '0';
  signal tx_active    : std_logic := '0';   -- transmitter of the current frame
  signal was_tx       : std_logic := '0';   -- transmitter of the frame that just ended
  signal tx_shift     : std_logic_vector(101 downto 0) := (others => '1');

  -- TX selection: scan over the buffers for the waiting frame with the highest bus priority
  signal sc_idx      : natural range 0 to g_TX_BUFFERS - 1 := 0;
  signal sc_ph       : std_logic := '0';   -- stage a reads in the clk with sc_ph = '0'
  signal sa_tok      : std_logic := '0';   -- stage a holds a new buffer
  signal sc_tok      : std_logic := '0';   -- stage b1 holds a new buffer
  signal sc_key      : unsigned(31 downto 0) := (others => '1');
  signal sc_vld      : std_logic := '0';
  signal sc_i        : natural range 0 to g_TX_BUFFERS - 1 := 0;
  signal sc_first    : std_logic := '0';
  signal sc_last     : std_logic := '0';
  signal sc_hi_lt    : std_logic := '0';   -- key halves compared with sb_key
  signal sc_hi_eq    : std_logic := '0';
  signal sc_lo_lt    : std_logic := '0';
  signal sa_key      : unsigned(31 downto 0) := (others => '1');
  signal sa_vld      : std_logic := '0';
  signal sa_idx      : natural range 0 to g_TX_BUFFERS - 1 := 0;
  signal sa_first    : std_logic := '0';
  signal sa_last     : std_logic := '0';
  signal sb_key      : unsigned(31 downto 0) := (others => '1');
  signal sb_idx      : natural range 0 to g_TX_BUFFERS - 1 := 0;
  signal sb_seen     : std_logic := '0';
  signal sb_done     : std_logic := '0';   -- pass complete, sb_* hold its result
  signal sb_dirty    : std_logic := '0';   -- buf_valid changed during the pass
  signal tx_best     : natural range 0 to g_TX_BUFFERS - 1 := 0;   -- selected frame
  signal best_shift  : std_logic_vector(101 downto 0) := (others => '1');   -- its bits
  signal sel_valid   : std_logic := '0';   -- tx_best / best_shift are the selection of the current buffers
  signal tx_pending  : std_logic;          -- a frame waits and is selected

  -- acceptance filters: id of the frame, filters it passes, lowest of them
  signal flt_id    : std_logic_vector(28 downto 0) := (others => '0');
  signal flt_hit   : std_logic_vector(g_FILTERS - 1 downto 0) := (others => '0');
  signal flt_match : std_logic := '0';
  signal flt_num   : natural range 0 to 31 := 0;

  -- errors
  signal flag_dom    : std_logic := '0';   -- dominant flag (active error flag, overload flag)
  signal flag_ovl    : std_logic := '0';   -- overload flag
  signal flag_same   : natural range 0 to 6 := 0;   -- equal bits in a passive error flag
  signal flag_last   : std_logic := '1';
  signal ack_defer   : std_logic := '0';   -- passive ACK error: +8 only if a dominant bit comes in the flag
  signal dom_cnt     : natural range 0 to 7 := 0;   -- dominant bits after the flag
  signal first_wait  : std_logic := '0';
  signal tec         : natural range 0 to 263 := 0;
  signal rec         : natural range 0 to 255 := 0;
  signal passive_r   : std_logic := '0';   -- tec or rec above 127
  -- error counters after each change P2 can make, and their thresholds
  signal tec_p8      : natural range 0 to 263 := 0;
  signal tec_m1      : natural range 0 to 263 := 0;
  signal rec_p1      : natural range 0 to 255 := 0;
  signal rec_p8      : natural range 0 to 255 := 0;
  signal rec_dn      : natural range 0 to 255 := 0;
  signal tec_bo      : std_logic := '0';   -- tec > 255
  signal tec_p8_bo   : std_logic := '0';   -- tec + 8 > 255
  signal tec_pas     : std_logic := '0';   -- tec >= 128
  signal tec_p8_pas  : std_logic := '0';
  signal tec_m1_pas  : std_logic := '0';
  signal rec_pas     : std_logic := '0';   -- rec >= 128
  signal rec_p1_pas  : std_logic := '0';
  signal rec_p8_pas  : std_logic := '0';
  signal bo_rcnt     : natural range 0 to 10 := 0;  -- bus off: recessive bits in a row
  signal bo_seq      : natural range 0 to 127 := 0; -- bus off: sequences of 11 recessive bits
  signal error_type  : std_logic_vector(2 downto 0) := (others => '0');

  -- receiver output (rx_word / rx_valid / rx_ready: stream between receiver and RX FIFO)
  signal rx_word  : std_logic_vector(c_RX_WIDTH - 1 downto 0) := (others => '0');
  signal rx_valid : std_logic := '0';
  signal rx_ready : std_logic;
  signal rx_out   : std_logic_vector(c_RX_WIDTH - 1 downto 0);

begin

  ------------------------------------------------------------------------------
  -- Concurrent statements
  ------------------------------------------------------------------------------

  rx_s <= rx_sync(1);

  o_can_tx        <= '1' when i_listen_only = '1' or i_loopback = '1' else can_tx;
  rx_in           <= can_tx when i_loopback = '1' else i_can_rx;
  o_tx_tready     <= '0' when buf_valid = (buf_valid'range => '1') else '1';
  o_error_warning <= '1' when tec >= 96 or rec >= 96 else '0';
  o_error_type    <= error_type;
  o_error_passive <= '1' when (tec >= 128 or rec >= 128) and field /= F_BUS_OFF else '0';
  o_bus_off       <= '1' when field = F_BUS_OFF else '0';
  o_tec           <= std_logic_vector(to_unsigned(minimum(tec, 255), 8));
  o_rec           <= std_logic_vector(to_unsigned(rec, 8));

  -- the selection is void from the edge on at which buf_valid changes
  tx_pending <= sel_valid and not buf_chg;

  -- bit timing ----------------------------------------------------------------
  -- time quanta, sample point, (re)synchronisation

  -- The bit processing (P1a to P2) needs c_IPT clk after the sample point. A
  -- bit that starts earlier (phase segment 2 shortened by a resynchronisation,
  -- or shorter than c_IPT clk) goes onto the bus as soon as tx_next is valid.
  tq_info <= c_TQ_TAB1(tq_cnt) when presc_last = '1' else c_TQ_TAB0(tq_cnt);
  -- recessive to dominant edge, bus was recessive at the last sample point
  edge    <= rx_prev and not rx_s and prev_sample and not synced;
  -- the sample point (unless an edge moves the bit timing in this clk)
  smp_now <= tq_info.at_sample and not (edge and (hs_en or (tq_info.rs_ok and not (tq_info.late and not can_tx))));

  -- RX buffer -----------------------------------------------------------------

  RX_FIFO_GEN : if g_RX_FIFO_DEPTH > 0 generate
    RX_FIFO : entity work.fifo(rtl)
      generic map (g_WIDTH => c_RX_WIDTH, g_DEPTH => g_RX_FIFO_DEPTH)
      port map (
        clk        => clk,
        rst        => rst,
        i_s_tdata  => rx_word,
        i_s_tvalid => rx_valid,
        o_s_tready => rx_ready,
        o_m_tdata  => rx_out,
        o_m_tvalid => o_rx_tvalid,
        i_m_tready => i_rx_tready,
        o_count    => open
      );
  else generate
    rx_out      <= rx_word;
    o_rx_tvalid <= rx_valid;
    rx_ready    <= i_rx_tready;
  end generate;

  o_rx_filter <= rx_out(103 downto 99);
  o_rx_id     <= rx_out(98 downto 70);
  o_rx_ext    <= rx_out(69);
  o_rx_rtr    <= rx_out(68);
  o_rx_dlc    <= rx_out(67 downto 64);
  o_rx_data   <= rx_out(63 downto 0);

  ------------------------------------------------------------------------------
  -- Processes
  ------------------------------------------------------------------------------

  SYNC_PROC : process(clk)
  begin
    if rising_edge(clk) then
      rx_sync <= rx_sync(0) & rx_in;
    end if;
  end process;

  -- bit timing ----------------------------------------------------------------

  BTU_PROC : process(clk)
    variable v_sample    : boolean;
    variable v_bit_start : boolean;
    variable v_edge      : boolean;
    variable v_restart   : boolean;   -- prescaler starts a new tq
    variable v_tq        : natural range 0 to c_NTQ - 1;
    variable v_info      : t_tq_info;
  begin
    if rising_edge(clk) then
      sample <= '0';
      if rst = '1' then
        rx_prev     <= '1';
        presc_cnt   <= 0;
        presc_last  <= to_sl(c_PRESC = 1);
        tq_cnt      <= 0;
        synced      <= '0';
        prev_sample <= '1';
        ipt_cnt     <= 0;
        tx_late     <= '0';
        can_tx      <= '1';
      else
        rx_prev     <= rx_s;
        v_sample    := false;
        v_bit_start := false;
        v_restart   := false;
        v_edge      := edge = '1';
        v_info      := tq_info;

        if v_edge and hs_en = '1' then
          -- start of frame: this cycle starts the sync segment
          synced    <= '1';
          v_tq      := 0;
          v_restart := true;
        elsif v_edge and v_info.rs_ok = '1' and not (v_info.late = '1' and can_tx = '0') then
          -- edge outside the sync segment; a node that drives a dominant bit
          -- ignores late edges (its own, delayed by the transceiver loop)
          synced <= '1';
          if v_info.late = '1' then
            -- late edge: lengthen phase segment 1 by up to g_SJW
            if v_info.late_rst = '1' then
              v_tq      := 0;
              v_restart := true;
            else
              v_tq := v_info.late_tq;
            end if;
          else
            -- early edge: shorten phase segment 2 by up to g_SJW
            if v_info.early_start = '1' then
              v_tq        := 0;   -- the next bit starts now
              v_restart   := true;
              v_bit_start := true;
            else
              v_tq := v_info.early_tq;
            end if;
          end if;
        else
          -- normal progress
          v_sample    := smp_now = '1';   -- end of phase segment 1
          v_bit_start := v_info.at_end = '1';
          v_tq        := v_info.nxt;
        end if;
        tq_cnt <= v_tq;

        if v_restart or presc_last = '1' then
          presc_cnt  <= 0;
          presc_last <= to_sl(c_PRESC = 1);
        else
          presc_cnt  <= presc_cnt + 1;
          presc_last <= to_sl(presc_cnt = c_PRESC - 2);
        end if;

        if v_sample then
          sample      <= '1';
          smp_bit     <= rx_s;
          prev_sample <= rx_s;
          synced      <= '0';
          ipt_cnt     <= c_IPT - 1;
        elsif ipt_cnt /= 0 then
          ipt_cnt <= ipt_cnt - 1;
        end if;

        if v_bit_start and ipt_cnt /= 0 then
          tx_late <= '1';
        elsif v_bit_start or (tx_late = '1' and ipt_cnt = 0) then
          can_tx  <= tx_next;
          tx_late <= '0';
        end if;
      end if;
    end if;
  end process;

  -- TX selection --------------------------------------------------------------
  -- one buffer every 2 clk, then the bits of the best one

  -- A pass reads every buffer once (stage a), compares its priority key with
  -- the best one so far in two halves (stage b1) and keeps the waiting frame
  -- with the lowest key (stage b2, ties: lowest buffer), then loads its bits
  -- (stage c). It only counts if buf_valid did not change meanwhile. A frame
  -- is selected 2 * g_TX_BUFFERS + 4 clk after it was accepted at the latest
  -- after the next pass.
  SEL_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        sc_idx    <= 0;
        sc_ph     <= '0';
        sa_tok    <= '0';
        sc_tok    <= '0';
        sb_done   <= '0';
        sel_valid <= '0';
      else
        -- stage a: read one buffer (every other clk)
        sc_ph  <= not sc_ph;
        sa_tok <= not sc_ph;
        if sc_ph = '0' then
          sa_key   <= priority(buf_id(sc_idx), buf_ext(sc_idx), buf_rtr(sc_idx));
          sa_vld   <= buf_valid(sc_idx);
          sa_idx   <= sc_idx;
          sa_first <= to_sl(sc_idx = 0);
          sa_last  <= to_sl(sc_idx = g_TX_BUFFERS - 1);
          if sc_idx = g_TX_BUFFERS - 1 then
            sc_idx <= 0;
          else
            sc_idx <= sc_idx + 1;
          end if;
        end if;
        if sc_ph = '0' and sc_idx = 0 then
          sb_dirty <= buf_chg;   -- a new pass
        else
          sb_dirty <= sb_dirty or buf_chg;
        end if;

        -- stage b1: compare with the best one so far
        sc_tok   <= sa_tok;
        sc_key   <= sa_key;
        sc_vld   <= sa_vld;
        sc_i     <= sa_idx;
        sc_first <= sa_first;
        sc_last  <= sa_last;
        sc_hi_lt <= to_sl(sa_key(31 downto 16) < sb_key(31 downto 16));
        sc_hi_eq <= to_sl(sa_key(31 downto 16) = sb_key(31 downto 16));
        sc_lo_lt <= to_sl(sa_key(15 downto 0) < sb_key(15 downto 0));

        -- stage b2: keep the better one
        sb_done <= '0';
        if sc_tok = '1' then
          if sc_first = '1' then
            sb_key  <= sc_key;
            sb_idx  <= sc_i;
            sb_seen <= sc_vld;
          elsif sc_vld = '1' and (sb_seen = '0' or sc_hi_lt = '1' or (sc_hi_eq = '1' and sc_lo_lt = '1')) then
            sb_key  <= sc_key;
            sb_idx  <= sc_i;
            sb_seen <= '1';
          end if;
          sb_done <= sc_last;
        end if;

        -- stage c: load the result
        if sb_done = '1' then
          if sb_dirty = '0' and buf_chg = '0' then
            tx_best    <= sb_idx;
            best_shift <= frame_bits(buf_id(sb_idx), buf_ext(sb_idx), buf_rtr(sb_idx),
                                     buf_dlc(sb_idx), buf_data(sb_idx));
            sel_valid  <= sb_seen;
          else
            sel_valid <= '0';
          end if;
        elsif buf_chg = '1' then
          sel_valid <= '0';
        end if;
      end if;
    end if;
  end process;

  -- acceptance filters --------------------------------------------------------
  -- the identifier is complete long before EOF

  FLT_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if ext = '1' then
        flt_id <= id_a & id_b;
      else
        flt_id <= (28 downto 11 => '0') & id_a;
      end if;
      for f in 0 to g_FILTERS - 1 loop
        if ((flt_id xor i_acc_id(29 * f + 28 downto 29 * f))
            and i_acc_mask(29 * f + 28 downto 29 * f)) = (28 downto 0 => '0') then
          flt_hit(f) <= '1';
        else
          flt_hit(f) <= '0';
        end if;
      end loop;
      flt_match <= any(flt_hit);
      flt_num   <= 0;
      for f in g_FILTERS - 1 downto 0 loop
        if flt_hit(f) = '1' then
          flt_num <= f;
        end if;
      end loop;
    end if;
  end process;

  CRC_PROC : process(clk)
  begin
    if rising_edge(clk) then
      crc_err <= to_sl(crc /= (crc'range => '0'));
    end if;
  end process;

  -- data bytes ----------------------------------------------------------------
  -- the last received byte is in dshift(7 downto 0); byte 0 goes to data(7
  -- downto 0), bytes beyond the DLC are '0' (complete before CRC)

  DATA_PROC : process(clk)
    variable n : natural range 0 to 8;
  begin
    if rising_edge(clk) then
      if rtr = '1' then
        n := 0;
      elsif unsigned(dlc) >= 8 then
        n := 8;
      else
        n := to_integer(unsigned(dlc));
      end if;
      data <= (others => '0');
      for nn in 1 to 8 loop
        if n = nn then
          for k in 0 to nn - 1 loop
            data(8 * k + 7 downto 8 * k) <= dshift(8 * (nn - 1 - k) + 7 downto 8 * (nn - 1 - k));
          end loop;
        end if;
      end loop;
    end if;
  end process;

  -- error counters ------------------------------------------------------------
  -- the values P2 may load next, computed once per clk from tec / rec (they
  -- change once per bit, in P2)

  CNT_PROC : process(clk)
  begin
    if rising_edge(clk) then
      tec_p8     <= minimum(tec + 8, 263);
      tec_m1     <= maximum(tec - 1, 0);
      rec_p1     <= minimum(rec + 1, 255);
      rec_p8     <= minimum(rec + 8, 255);
      if rec > 127 then
        rec_dn <= 120;
      else
        rec_dn <= maximum(rec - 1, 0);
      end if;
      if tec > 255 then
        tec_bo <= '1';
      else
        tec_bo <= '0';
      end if;
      if tec + 8 > 255 then
        tec_p8_bo <= '1';
      else
        tec_p8_bo <= '0';
      end if;
      if tec >= 128 then
        tec_pas <= '1';
      else
        tec_pas <= '0';
      end if;
      if tec + 8 >= 128 then
        tec_p8_pas <= '1';
      else
        tec_p8_pas <= '0';
      end if;
      if tec > 128 then
        tec_m1_pas <= '1';
      else
        tec_m1_pas <= '0';
      end if;
      if rec >= 128 then
        rec_pas <= '1';
      else
        rec_pas <= '0';
      end if;
      if rec >= 127 then
        rec_p1_pas <= '1';
      else
        rec_p1_pas <= '0';
      end if;
      if rec >= 120 then
        rec_p8_pas <= '1';
      else
        rec_p8_pas <= '0';
      end if;
    end if;
  end process;

  -- bit processing, TX and RX streams -----------------------------------------

  -- Per bit, in three stages: one clk apart if c_PIPE (P1a in the clk after
  -- the sample point: sample = '1', P1b: smp_d1, P2: smp_d2), else all three
  -- in the clk of the sample point (smp_now), the results passed on directly.
  --   P1a: stuff bit, arbitration, bit error: what the bit is (va -> a)
  --   P1b: bit stuffing, form / CRC / ACK errors, the fields of the frame,
  --        error and overload frames; error counter changes and error flags
  --        are only requested (vp1 -> p1)
  --   P2:  error counters, error passive, bus off, error flag level, o_error,
  --        sent / dropped frames, next bit to send
  CAN_PROC : process(clk)
    variable b           : std_logic;
    variable v_field     : t_field;
    variable v_cnt       : natural range 0 to 63;
    variable v_stuff     : std_logic;
    variable v_same      : natural range 0 to 5;
    variable v_last      : std_logic;
    variable v_crc       : std_logic_vector(14 downto 0);
    variable v_tx_active : std_logic;
    variable v_shift     : std_logic_vector(101 downto 0);
    variable v_tec       : natural range 0 to 263;
    variable v_rec       : natural range 0 to 255;
    variable v_dlc       : std_logic_vector(3 downto 0);
    variable v_next      : std_logic;
    variable v_err       : boolean;   -- error or overload flag started in this bit
    variable v_valid     : std_logic_vector(g_TX_BUFFERS - 1 downto 0);
    variable v_acc       : std_logic_vector(g_TX_BUFFERS - 1 downto 0);
    variable v_attempt   : std_logic;
    variable v_done      : std_logic;
    variable v_tec_op    : t_tec_op;
    variable v_rec_op    : t_rec_op;
    variable v_flag      : std_logic;
    variable v_flag_ovl  : std_logic;
    variable v_passive   : boolean;
    variable v_flag_dom  : std_logic;
    variable v_bus_off   : std_logic;
    variable v_tec_pas   : std_logic;
    variable v_rec_pas   : std_logic;
    variable v_error     : std_logic;
    variable v_err_type  : std_logic_vector(2 downto 0);
    variable v_ack_set   : std_logic;   -- passive ACK error: ack_defer <= '1'
    variable v_ack_clr   : std_logic;   -- ack_defer <= '0'
    variable v_ok        : boolean;
    variable va, ia      : t_p1a;   -- P1a result; as P1b sees it
    variable vp1, ip1    : t_p1;    -- P1b result; as P2 sees it
    variable p1a_en, p1b_en, p2_en : boolean;

    procedure rec_add(n : natural) is
    begin
      if i_listen_only = '0' then
        if n = 8 then v_rec_op := REC_ADD8; else v_rec_op := REC_ADD1; end if;
      end if;
    end procedure;

    procedure tec_add8 is
    begin
      if i_listen_only = '0' then
        v_tec_op := TEC_ADD8;
      end if;
    end procedure;

    -- error or overload flag from the next bit on (P2: or bus off)
    procedure start_flag(ovl : boolean) is
    begin
      v_err   := true;
      v_stuff := '0';
      v_cnt   := 0;
      v_field := F_FLAG;
      v_flag  := '1';
      if ovl then v_flag_ovl := '1'; else v_flag_ovl := '0'; end if;
    end procedure;

    -- error detected in this bit: error counters (rules 1 and 3 of the
    -- standard; inc8: rules 4 / 5, bit error in an active error or overload flag)
    procedure error(typ : std_logic_vector(2 downto 0); no_tec : boolean; inc8 : boolean) is
    begin
      v_error    := '1';
      v_err_type := typ;
      v_ack_clr  := '1';
      if v_tx_active = '1' then
        if inc8 then
          tec_add8;
        elsif no_tec then
          null;
        elsif typ = c_ERR_ACK and passive_r = '1' then
          v_ack_set := '1';
        else
          tec_add8;
        end if;
      else
        if inc8 then rec_add(8); else rec_add(1); end if;
      end if;
      start_flag(false);
    end procedure;

    -- dominant bit seen while the bus was idle (or in the 3rd intermission bit):
    -- start of frame. A node with a frame pending takes part in the arbitration.
    procedure sof(join : std_logic) is
    begin
      v_field := F_ID_A;
      v_cnt   := 0;
      v_crc   := (others => '0');
      v_stuff := '1';
      v_same  := 1;
      v_last  := '0';
      -- can_tx = '0': this node sent the SOF, tx_best is a waiting frame
      -- (tx_cur <= tx_best below)
      if can_tx = '0' or join = '1' then
        v_tx_active := '1';
        v_attempt   := '1';
        v_shift     := best_shift;
      else
        v_tx_active := '0';
      end if;
    end procedure;

    -- end of a frame, error frame or overload frame: intermission follows
    procedure end_frame is
    begin
      v_tx_active := '0';   -- (was_tx <= tx_active below)
      v_field     := F_INTERMISSION;
      v_cnt       := 0;
    end procedure;

  begin
    if rising_edge(clk) then
      o_tx_done     <= '0';
      o_tx_arb_lost <= '0';
      o_rx_overrun  <= '0';
      o_error       <= '0';
      o_tx_dropped  <= '0';
      smp_d1        <= sample;
      smp_d2        <= smp_d1;
      -- the stages: one clk apart (c_PIPE) or all in the clk of the sample point
      p1a_en := (c_PIPE and sample = '1') or (not c_PIPE and smp_now = '1');
      p1b_en := (c_PIPE and smp_d1 = '1') or (not c_PIPE and smp_now = '1');
      p2_en  := (c_PIPE and smp_d2 = '1') or (not c_PIPE and smp_now = '1');
      va     := c_P1A_NONE;
      vp1    := c_P1_NONE;

      if rst = '1' then
        hs_en        <= '0';
        tx_next      <= '1';
        field        <= F_INTEGRATE;
        cnt          <= 0;
        stuff_en     <= '0';
        same_cnt     <= 0;
        buf_valid    <= (others => '0');
        buf_chg      <= '1';
        tx_attempt   <= '0';
        o_tx_done_id <= (others => '0');
        tx_abort_req <= '0';
        tx_active    <= '0';
        was_tx       <= '0';
        ack_defer    <= '0';
        tec          <= 0;
        rec          <= 0;
        passive_r    <= '0';
        error_type   <= (others => '0');
        rx_valid     <= '0';
        smp_d1       <= '0';
        smp_d2       <= '0';
        a            <= c_P1A_NONE;
      else

        ------------------------------------------------------------------------
        -- TX stream and abort
        ------------------------------------------------------------------------
        -- a new frame goes into the lowest free buffer
        v_acc   := (others => '0');
        v_valid := buf_valid;
        if i_tx_tvalid = '1' then
          for i in 0 to g_TX_BUFFERS - 1 loop
            if buf_valid(i) = '0' then
              v_acc(i)    := '1';
              buf_id(i)   <= i_tx_id;
              buf_ext(i)  <= i_tx_ext;
              buf_rtr(i)  <= i_tx_rtr;
              buf_dlc(i)  <= i_tx_dlc;
              buf_data(i) <= i_tx_data;
              exit;
            end if;
          end loop;
        end if;
        if i_tx_abort = '1' and any(buf_valid) = '1' then
          tx_abort_req <= '1';
        end if;

        -- RX stream handshake (a new frame below may refill in the same cycle)
        if rx_valid = '1' and rx_ready = '1' then
          rx_valid <= '0';
        end if;

        ------------------------------------------------------------------------
        -- P1a: bit stuffing, arbitration and bit error
        ------------------------------------------------------------------------
        if p1a_en then
          if c_PIPE then b := smp_bit; else b := rx_s; end if;
          va.b := b;
          -- neither a stuff bit nor a bit error (the classes below)
          v_ok := not (stuff_en = '1' and same_cnt = 5)
                  and not (tx_active = '1' and b /= can_tx and stuff_en = '1' and field /= F_CRC_DELIM
                           and not (can_tx = '1' and (field = F_ID_A or field = F_SRR_RTR or field = F_IDE
                                                      or field = F_ID_B or field = F_RTR)));
          for f in t_field loop
            va.go(f) := to_sl(v_ok and field = f);
          end loop;
          va.rx := to_sl(v_ok and field = F_EOF and cnt = 5 and b = '1') and flt_match
                  and (not tx_active or i_loopback);
          -- the selection only becomes void in P2, so it holds until P1b
          va.join     := tx_pending and not tx_abort_req and not i_listen_only;
          va.join_int := tx_pending and not tx_abort_req and not i_listen_only and not (passive_r and was_tx);
          va.stuff_bit := stuff_en and to_sl(same_cnt = 5);
          va.err       := '0';
          va.c2     := to_sl(cnt = 2);
          va.c3     := to_sl(cnt = 3);
          va.c5     := to_sl(cnt = 5);
          va.c6     := to_sl(cnt = 6);
          va.c7     := to_sl(cnt = 7);
          va.c10    := to_sl(cnt = 10);
          va.c14    := to_sl(cnt = 14);
          va.c17    := to_sl(cnt = 17);
          va.clast  := to_sl(cnt = data_last);
          va.fs_nz  := to_sl(flag_same /= 0);
          va.fs5    := to_sl(flag_same = 5);
          va.dom7   := to_sl(dom_cnt = 7);
          va.bor10  := to_sl(bo_rcnt = 10);
          va.bos127 := to_sl(bo_seq = 127);
          case field is
            when F_ID_A | F_SRR_RTR | F_IDE | F_ID_B | F_RTR | F_R1 | F_R0 | F_DLC | F_DATA =>
              va.shift_f := '1';
              va.crc_f   := '1';
            when F_CRC =>
              va.shift_f := '0';
              va.crc_f   := '1';
            when others =>
              va.shift_f := '0';
              va.crc_f   := '0';
          end case;
          if stuff_en = '1' and same_cnt = 5 then
            -- stuff bit: must differ from the 5 bits before it
            if tx_active = '1' and b /= can_tx then
              if can_tx = '1' and (field = F_ID_A or field = F_SRR_RTR or field = F_IDE
                                   or field = F_ID_B or field = F_RTR) then
                va.cls := CLS_STUFF_ERR_ARB;   -- recessive stuff bit overwritten in the arbitration
              else
                va.cls := CLS_BIT_ERR;
              end if;
              va.err := '1';
            elsif b = last_bit then
              va.cls := CLS_STUFF_ERR;
              va.err := '1';
            else
              va.cls := CLS_STUFF_OK;
            end if;
          elsif tx_active = '1' and b /= can_tx and stuff_en = '1' and field /= F_CRC_DELIM then
            -- fields with bit stuffing
            if can_tx = '1' and (field = F_ID_A or field = F_SRR_RTR or field = F_IDE
                                 or field = F_ID_B or field = F_RTR) then
              va.cls := CLS_ARB_LOST;
            else
              va.cls := CLS_BIT_ERR;
              va.err := '1';
            end if;
          else
            va.cls := CLS_NORMAL;
          end if;
        end if;
        if c_PIPE then ia := a; else ia := va; end if;

        ------------------------------------------------------------------------
        -- P1b: the fields of the frame, error and overload frames
        ------------------------------------------------------------------------
        if p1b_en then
          b := ia.b;

          v_field     := field;
          v_cnt       := cnt;
          v_stuff     := stuff_en;
          v_same      := same_cnt;
          v_last      := last_bit;
          v_crc       := crc;
          v_tx_active := tx_active;
          v_attempt   := tx_attempt;
          v_done      := '0';
          v_shift     := tx_shift;
          v_err       := false;
          v_tec_op    := TEC_NONE;
          v_rec_op    := REC_NONE;
          v_flag      := '0';
          v_flag_ovl  := '0';
          v_error     := '0';
          v_err_type  := error_type;
          v_ack_set   := '0';
          v_ack_clr   := '0';

          if ia.stuff_bit = '1' then
            -- stuff bit
            case ia.cls is
              when CLS_STUFF_ERR_ARB => error(c_ERR_STUFF, true, false);
              when CLS_STUFF_ERR     => error(c_ERR_STUFF, false, false);
              when CLS_BIT_ERR       => error(c_ERR_BIT, false, false);
              when others =>
                v_last := b;
                v_same := 1;
            end case;

          else
            if ia.cls = CLS_ARB_LOST then
              v_tx_active := '0';   -- lost the arbitration, receive the rest
            elsif ia.cls = CLS_BIT_ERR then
              error(c_ERR_BIT, false, false);
            end if;

            if ia.err = '0' then
              if v_stuff = '1' then
                if b = v_last then
                  v_same := v_same + 1;
                else
                  v_same := 1;
                  v_last := b;
                end if;
              end if;
              if ia.crc_f = '1' then
                v_crc := crc_step(v_crc, b);
              end if;
              if ia.shift_f = '1' then
                v_shift := v_shift(100 downto 0) & '1';
              end if;

              case field is

                when F_INTEGRATE =>
                  if b = '0' then
                    v_cnt := 0;
                  elsif ia.c10 = '1' then
                    v_field := F_IDLE;
                    v_cnt   := 0;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_IDLE =>
                  if b = '0' then
                    sof(ia.join);
                  end if;

                when F_ID_A =>
                  if ia.c10 = '1' then
                    v_field := F_SRR_RTR;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_SRR_RTR =>
                  v_field := F_IDE;

                when F_IDE =>
                  v_cnt := 0;
                  if b = '1' then
                    v_field := F_ID_B;
                  else
                    v_field := F_R0;
                  end if;

                when F_ID_B =>
                  if ia.c17 = '1' then
                    v_field := F_RTR;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_RTR =>
                  v_field := F_R1;

                when F_R1 =>
                  v_field := F_R0;   -- reserved bits: either level is accepted

                when F_R0 =>
                  v_field := F_DLC;
                  v_cnt   := 0;

                when F_DLC =>
                  v_dlc := dlc(2 downto 0) & b;
                  v_cnt := v_cnt + 1;
                  if ia.c3 = '1' then
                    v_cnt := 0;
                    if rtr = '1' or v_dlc = "0000" then
                      v_field := F_CRC;
                    else
                      v_field := F_DATA;
                    end if;
                  end if;

                when F_DATA =>
                  if ia.clast = '1' then
                    v_field := F_CRC;
                    v_cnt   := 0;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_CRC =>
                  -- the CRC runs on over the CRC sequence: crc = 0 if it was right
                  if ia.c14 = '1' then
                    v_field := F_CRC_DELIM;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_CRC_DELIM =>
                  v_stuff := '0';
                  if b = '0' then
                    error(c_ERR_FORM, false, false);
                  else
                    v_field := F_ACK_SLOT;
                  end if;

                when F_ACK_SLOT =>
                  if v_tx_active = '1' and b = '1' and i_loopback = '0' then
                    error(c_ERR_ACK, false, false);
                  else
                    v_field := F_ACK_DELIM;
                  end if;

                when F_ACK_DELIM =>
                  if b = '0' then
                    error(c_ERR_FORM, false, false);
                  elsif v_tx_active = '0' and crc_err = '1' then
                    error(c_ERR_CRC, false, false);
                  else
                    v_field := F_EOF;
                    v_cnt   := 0;
                  end if;

                when F_EOF =>
                  if b = '0' then
                    if ia.c6 = '1' and v_tx_active = '0' then
                      start_flag(true);   -- receiver: overload frame
                    else
                      error(c_ERR_FORM, false, false);
                    end if;
                  elsif ia.c5 = '1' and (v_tx_active = '0' or i_loopback = '1') then
                    -- receiver (or loopback): the frame is valid after the last but one EOF bit
                    -- (RX stream below)
                    if v_tx_active = '0' then
                      v_rec_op := REC_DEC;
                    end if;
                    v_cnt := v_cnt + 1;
                  elsif ia.c6 = '1' then
                    if v_tx_active = '1' then
                      -- transmitter: the frame is valid after the last EOF bit
                      v_tec_op  := TEC_DEC;
                      v_attempt := '0';
                      v_done    := '1';
                    end if;
                    end_frame;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_INTERMISSION =>
                  if b = '0' then
                    if ia.c2 = '1' then
                      sof(ia.join_int);
                    else
                      start_flag(true);   -- overload frame
                    end if;
                  elsif ia.c2 = '1' then
                    v_cnt := 0;
                    if passive_r = '1' and was_tx = '1' then
                      v_field := F_SUSPEND;
                    else
                      v_field := F_IDLE;
                    end if;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_SUSPEND =>
                  if b = '0' then
                    sof('0');
                  elsif ia.c7 = '1' then
                    v_field := F_IDLE;
                    v_cnt   := 0;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                ----------------------------------------------------------------
                -- error and overload frames, bus off (P2 goes bus off when the
                -- transmit error counter passes 255); without bit stuffing,
                -- so P1a finds no error here
                ----------------------------------------------------------------
                when F_FLAG =>
                  if flag_dom = '1' then
                    if b = '1' then
                      -- bit error in an active error flag or overload flag (rules 4 and 5)
                      error(c_ERR_BIT, false, true);
                    elsif ia.c5 = '1' then
                      v_field := F_FLAG_WAIT;
                    else
                      v_cnt := v_cnt + 1;
                    end if;
                  else
                    -- passive error flag: complete after 6 equal bits in a row
                    if b = '0' and ack_defer = '1' then
                      tec_add8;
                      v_ack_clr := '1';
                    end if;
                    if ia.fs_nz = '1' and b = flag_last and ia.fs5 = '1' then
                      v_field := F_FLAG_WAIT;
                    end if;
                  end if;

                when F_FLAG_WAIT =>
                  if b = '1' then
                    v_field := F_DELIM;
                    v_cnt   := 1;   -- the first recessive bit is the first delimiter bit
                  else
                    if first_wait = '1' and flag_ovl = '0' and v_tx_active = '0' then
                      rec_add(8);    -- rule 2: dominant bit right after the error flag
                    end if;
                    if ia.dom7 = '1' then
                      -- rule 6: 8 more dominant bits after the flag
                      if v_tx_active = '1' then tec_add8; else rec_add(8); end if;
                    end if;
                  end if;

                when F_DELIM =>
                  if b = '0' then
                    if ia.c7 = '1' then
                      start_flag(true);   -- overload frame
                    else
                      error(c_ERR_FORM, false, false);
                    end if;
                  elsif ia.c7 = '1' then
                    end_frame;
                  else
                    v_cnt := v_cnt + 1;
                  end if;

                when F_BUS_OFF =>
                  -- 128 x 11 recessive bits (counted below)
                  if b = '1' and ia.bor10 = '1' and ia.bos127 = '1' then
                    v_tec_op := TEC_CLR;
                    v_rec_op := REC_CLR;
                    v_field  := F_IDLE;
                  end if;

              end case;
            end if;
          end if;

          stuff_en     <= v_stuff;
          same_cnt     <= v_same;
          last_bit     <= v_last;
          crc          <= v_crc;
          tx_shift     <= v_shift;
          vp1.field     := v_field;
          vp1.cnt       := v_cnt;
          vp1.tx_active := v_tx_active;
          vp1.attempt   := v_attempt;
          vp1.done      := v_done;
          vp1.tec_op    := v_tec_op;
          vp1.rec_op    := v_rec_op;
          vp1.flag      := v_flag;
          vp1.flag_ovl  := v_flag_ovl;
          vp1.error     := v_error;
          vp1.err_type  := v_err_type;
          vp1.ack_set   := v_ack_set;
          vp1.ack_clr   := v_ack_clr;
          vp1.stuff     := v_stuff;
          vp1.same5     := to_sl(v_same = 5);
          vp1.last      := v_last;
          vp1.crc14     := v_crc(14);
          vp1.shift101  := v_shift(101);
        end if;
        if c_PIPE then ip1 := p1; else ip1 := vp1; end if;

        ------------------------------------------------------------------------
        -- P1b: the registers of the fields, enabled by ia.go (one-hot) so that
        -- they do not depend on the decoding of field above
        ------------------------------------------------------------------------
        b := ia.b;
        if ia.go(F_ID_A) = '1' then
          id_a <= id_a(9 downto 0) & b;
        end if;
        if ia.go(F_SRR_RTR) = '1' or ia.go(F_RTR) = '1' then
          rtr <= b;
        end if;
        if ia.go(F_IDE) = '1' then
          ext <= b;
        end if;
        if ia.go(F_ID_B) = '1' then
          id_b <= id_b(16 downto 0) & b;
        end if;
        if ia.go(F_DLC) = '1' then
          v_dlc := dlc(2 downto 0) & b;
          dlc   <= v_dlc;
          if ia.c3 = '1' then
            dshift <= (others => '0');
            if v_dlc(3) = '1' then
              data_last <= 63;
            elsif v_dlc /= "0000" then
              data_last <= 8 * to_integer(unsigned(v_dlc)) - 1;
            end if;
          end if;
        end if;
        if ia.go(F_DATA) = '1' then
          dshift <= dshift(62 downto 0) & b;
        end if;
        -- receiver (or loopback): the frame is valid after the last but one EOF bit
        if ia.rx = '1' then
          if rx_valid = '1' and rx_ready = '0' then
            o_rx_overrun <= '1';
          else
            rx_word  <= std_logic_vector(to_unsigned(flt_num, 5)) & flt_id & ext & rtr & dlc & data;
            rx_valid <= '1';
          end if;
        end if;
        -- start of frame: the frame to send, if this node takes part
        if (ia.go(F_IDLE) = '1' or ia.go(F_SUSPEND) = '1' or (ia.go(F_INTERMISSION) = '1' and ia.c2 = '1'))
           and b = '0' then
          tx_cur <= tx_best;
        end if;
        -- end of a frame, error frame or overload frame
        if ((ia.go(F_EOF) = '1' and ia.c6 = '1') or (ia.go(F_DELIM) = '1' and ia.c7 = '1')) and b = '1' then
          was_tx <= tx_active;
        end if;
        -- error and overload flags
        if ia.go(F_FLAG) = '1' then
          if flag_dom = '1' then
            if b = '0' and ia.c5 = '1' then
              dom_cnt    <= 0;
              first_wait <= '1';
            end if;
          else
            if ia.fs_nz = '1' and b = flag_last then
              flag_same <= flag_same + 1;
              if ia.fs5 = '1' then
                dom_cnt    <= 0;
                first_wait <= '1';
              end if;
            else
              flag_same <= 1;
            end if;
            flag_last <= b;
          end if;
        end if;
        if ia.go(F_FLAG_WAIT) = '1' then
          first_wait <= '0';
          if b = '0' then
            if ia.dom7 = '1' then
              dom_cnt <= 0;
            else
              dom_cnt <= dom_cnt + 1;
            end if;
          end if;
        end if;
        if ia.go(F_BUS_OFF) = '1' then
          if b = '0' then
            bo_rcnt <= 0;
          elsif ia.bor10 = '1' then
            bo_rcnt <= 0;
            if ia.bos127 = '1' then
              bo_seq <= 0;
            else
              bo_seq <= bo_seq + 1;
            end if;
          else
            bo_rcnt <= bo_rcnt + 1;
          end if;
        end if;
        if p1b_en and ia.stuff_bit = '0' and ia.cls = CLS_ARB_LOST then
          o_tx_arb_lost <= '1';
        end if;

        ------------------------------------------------------------------------
        -- P2: error counters, fault confinement, TX buffers
        ------------------------------------------------------------------------
        if p2_en then
          v_field     := ip1.field;
          v_cnt       := ip1.cnt;
          v_tx_active := ip1.tx_active;
          v_attempt   := ip1.attempt;
          o_error     <= ip1.error;
          error_type  <= ip1.err_type;

          case ip1.tec_op is
            when TEC_ADD8 => v_tec := tec_p8; v_bus_off := tec_p8_bo; v_tec_pas := tec_p8_pas;
            when TEC_DEC  => v_tec := tec_m1; v_bus_off := '0';       v_tec_pas := tec_m1_pas;
            when TEC_CLR  => v_tec := 0;      v_bus_off := '0';       v_tec_pas := '0';
            when others   => v_tec := tec;    v_bus_off := tec_bo;    v_tec_pas := tec_pas;
          end case;
          case ip1.rec_op is
            when REC_ADD1 => v_rec := rec_p1; v_rec_pas := rec_p1_pas;
            when REC_ADD8 => v_rec := rec_p8; v_rec_pas := rec_p8_pas;
            when REC_DEC  => v_rec := rec_dn; v_rec_pas := '0';
            when REC_CLR  => v_rec := 0;      v_rec_pas := '0';
            when others   => v_rec := rec;    v_rec_pas := rec_pas;
          end case;
          v_passive := v_tec_pas = '1' or v_rec_pas = '1';

          v_flag_dom := flag_dom;
          if v_bus_off = '1' then
            -- bus off
            v_field     := F_BUS_OFF;
            v_tx_active := '0';
            v_cnt       := 0;
          elsif ip1.flag = '1' then
            -- error flag level: listen only recessive, overload and error active dominant
            if i_listen_only = '1' then
              v_flag_dom := '0';
            elsif ip1.flag_ovl = '1' or not v_passive then
              v_flag_dom := '1';
            else
              v_flag_dom := '0';
            end if;
          end if;
          flag_dom <= v_flag_dom;
          if ip1.flag = '1' then
            flag_same <= 0;
            flag_ovl  <= ip1.flag_ovl;
          end if;
          if ip1.ack_set = '1' then
            ack_defer <= '1';
          elsif ip1.ack_clr = '1' then
            ack_defer <= '0';
          end if;

          if v_bus_off = '1' and field /= F_BUS_OFF then
            bo_rcnt <= 0;
            bo_seq  <= 0;
          end if;

          if ip1.done = '1' then
            o_tx_done       <= '1';
            o_tx_done_id    <= buf_id(tx_cur);
            v_valid(tx_cur) := '0';
          end if;

          -- one shot: drop the frame after its first attempt failed
          if v_attempt = '1' and v_tx_active = '0' and ip1.done = '0' then
            v_attempt := '0';
            if i_one_shot = '1' then
              v_valid(tx_cur) := '0';
              o_tx_dropped    <= '1';
            end if;
          end if;

          -- abort: drop the waiting frames while none is on the bus
          if tx_abort_req = '1' and v_tx_active = '0' then
            if any(v_valid) = '1' then
              o_tx_dropped <= '1';
            end if;
            v_valid      := (others => '0');
            v_attempt    := '0';
            tx_abort_req <= '0';
          end if;

          if v_field = F_IDLE or v_field = F_SUSPEND or (v_field = F_INTERMISSION and v_cnt = 2) then
            hs_en <= '1';
          else
            hs_en <= '0';
          end if;

          -- next bit to send (the selection is void when buffers changed above)
          v_next := '1';
          if v_tx_active = '1' and ip1.stuff = '1' and ip1.same5 = '1' then
            v_next := not ip1.last;   -- stuff bit
          else
            case v_field is
              when F_IDLE =>
                if tx_pending = '1' and v_valid = buf_valid and i_listen_only = '0' then
                  v_next := '0';    -- start of frame
                end if;
              when F_ID_A | F_SRR_RTR | F_IDE | F_ID_B | F_RTR | F_R1 | F_R0 | F_DLC | F_DATA =>
                if v_tx_active = '1' then
                  v_next := ip1.shift101;
                end if;
              when F_CRC =>
                if v_tx_active = '1' then
                  v_next := ip1.crc14;
                end if;
              when F_ACK_SLOT =>
                if v_tx_active = '0' and crc_err = '0' and i_listen_only = '0' then
                  v_next := '0';    -- ACK
                end if;
              when F_FLAG =>
                v_next := not v_flag_dom;
              when others =>
                null;
            end case;
          end if;
          tx_next <= v_next;

          field      <= v_field;
          cnt        <= v_cnt;
          tx_active  <= v_tx_active;
          tx_attempt <= v_attempt;
          tec        <= v_tec;
          rec        <= v_rec;
          if v_passive then
            passive_r <= '1';
          else
            passive_r <= '0';
          end if;
        end if;

        a  <= va;
        p1 <= vp1;
        buf_valid <= v_valid or v_acc;
        if (v_valid or v_acc) /= buf_valid then
          buf_chg <= '1';
        else
          buf_chg <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture;
