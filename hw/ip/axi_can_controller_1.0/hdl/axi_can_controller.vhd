--------------------------------------------------------------------------------
-- AXI CAN Controller - AXI4-Lite wrapper around can_controller
-- W1GX
-- Generated 2026-11-23 by vivado-axi-ip from ip_spec.json. Do not edit: change the
-- spec and run axi_ip.py generate again.
--------------------------------------------------------------------------------
-- can_controller is instantiated unchanged. Everything runs on S_AXI_ACLK; the
-- reset is S_AXI_ARESETN (synchronous, active low, from proc_sys_reset).
--
-- AXI4-Lite slave: a write is accepted when AWVALID and WVALID are both high and
-- no response is pending (3 clocks per write), a read takes 2 clocks. RDATA is
-- registered. BRESP / RRESP are always OKAY; unmapped words read 0 and ignore
-- writes. Byte strobes are honoured. VHDL-93 (block design Module Reference and
-- IP top level).
--
-- Register map (byte offsets, see docs/registers.md):
--   0x00      ID           ID    [31:16] magic, [15:8] major version, [7:0] min
--   0x04      CONFIG       RO    IP configuration
--   0x08      CTRL         RW    mode control (change modes only in reset or wh
--   0x0C      CMD          PULSE commands (self-clearing)
--   0x10      STATUS       RO    controller status
--   0x14      EVENTS       W1C   events, write 1 to clear; interrupt sources
--   0x18      IER          RW    interrupt enable, same layout as EVENTS
--   0x1C      TX_DONE_ID   RO    identifier of the last frame sent
--   0x20      TX_ID        RW    TX frame identifier (standard frames: bits 10.
--   0x24      TX_DLC       RW    TX frame DLC and flags
--   0x28      RX_ID        RO    RX frame identifier
--   0x2C      RX_DLC       RO    RX frame DLC, flags and matching filter
--   0x40+4n   TX_DATAn     RW    TX data bytes, word n = bytes 4n..4n+3, byte 4
--   0x80+4n   RX_DATAn     RO    RX data bytes, word n = bytes 4n..4n+3, byte 4
--   0x100+4n  ACC_IDn      RW    acceptance filter identifiers
--   0x180+4n  ACC_MASKn    RW    acceptance filter masks: 1 = bit compared, all
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity axi_can_controller is
  generic (
    C_CLOCK_FREQUENCY : integer := 100000000;
    C_BIT_RATE : integer := 500000;
    C_TQ_PER_BIT : integer := 20;
    C_PHASE_SEG2 : integer := 4;
    C_SJW : integer := 4;
    C_RX_FIFO_DEPTH : integer := 4;
    C_TX_BUFFERS : integer := 3;
    C_FILTERS : integer := 4;
    C_S_AXI_DATA_WIDTH : integer := 32;
    C_S_AXI_ADDR_WIDTH : integer := 9
  );
  port (
    can_tx : out std_logic;
    can_rx : in std_logic;
    irq : out std_logic;
    S_AXI_ACLK : in std_logic;
    S_AXI_ARESETN : in std_logic;
    S_AXI_AWADDR : in std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
    S_AXI_AWPROT : in std_logic_vector(2 downto 0);
    S_AXI_AWVALID : in std_logic;
    S_AXI_AWREADY : out std_logic;
    S_AXI_WDATA : in std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
    S_AXI_WSTRB : in std_logic_vector(C_S_AXI_DATA_WIDTH / 8 - 1 downto 0);
    S_AXI_WVALID : in std_logic;
    S_AXI_WREADY : out std_logic;
    S_AXI_BRESP : out std_logic_vector(1 downto 0);
    S_AXI_BVALID : out std_logic;
    S_AXI_BREADY : in std_logic;
    S_AXI_ARADDR : in std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
    S_AXI_ARPROT : in std_logic_vector(2 downto 0);
    S_AXI_ARVALID : in std_logic;
    S_AXI_ARREADY : out std_logic;
    S_AXI_RDATA : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
    S_AXI_RRESP : out std_logic_vector(1 downto 0);
    S_AXI_RVALID : out std_logic;
    S_AXI_RREADY : in std_logic
  );

  -- Interface attributes (entity declarative region, where the LRM puts them for ports)
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO of S_AXI_ACLK : signal is "xilinx.com:signal:clock:1.0 S_AXI_ACLK CLK";
  attribute X_INTERFACE_PARAMETER of S_AXI_ACLK : signal is "ASSOCIATED_BUSIF S_AXI, ASSOCIATED_RESET S_AXI_ARESETN";
  attribute X_INTERFACE_INFO of S_AXI_ARESETN : signal is "xilinx.com:signal:reset:1.0 S_AXI_ARESETN RST";
  attribute X_INTERFACE_PARAMETER of S_AXI_ARESETN : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of S_AXI_AWADDR : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWADDR";
  attribute X_INTERFACE_INFO of S_AXI_AWPROT : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWPROT";
  attribute X_INTERFACE_INFO of S_AXI_AWVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWVALID";
  attribute X_INTERFACE_INFO of S_AXI_AWREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI AWREADY";
  attribute X_INTERFACE_INFO of S_AXI_WDATA : signal is "xilinx.com:interface:aximm:1.0 S_AXI WDATA";
  attribute X_INTERFACE_INFO of S_AXI_WSTRB : signal is "xilinx.com:interface:aximm:1.0 S_AXI WSTRB";
  attribute X_INTERFACE_INFO of S_AXI_WVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI WVALID";
  attribute X_INTERFACE_INFO of S_AXI_WREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI WREADY";
  attribute X_INTERFACE_INFO of S_AXI_BRESP : signal is "xilinx.com:interface:aximm:1.0 S_AXI BRESP";
  attribute X_INTERFACE_INFO of S_AXI_BVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI BVALID";
  attribute X_INTERFACE_INFO of S_AXI_BREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI BREADY";
  attribute X_INTERFACE_INFO of S_AXI_ARADDR : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARADDR";
  attribute X_INTERFACE_INFO of S_AXI_ARPROT : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARPROT";
  attribute X_INTERFACE_INFO of S_AXI_ARVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARVALID";
  attribute X_INTERFACE_INFO of S_AXI_ARREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI ARREADY";
  attribute X_INTERFACE_INFO of S_AXI_RDATA : signal is "xilinx.com:interface:aximm:1.0 S_AXI RDATA";
  attribute X_INTERFACE_INFO of S_AXI_RRESP : signal is "xilinx.com:interface:aximm:1.0 S_AXI RRESP";
  attribute X_INTERFACE_INFO of S_AXI_RVALID : signal is "xilinx.com:interface:aximm:1.0 S_AXI RVALID";
  attribute X_INTERFACE_INFO of S_AXI_RREADY : signal is "xilinx.com:interface:aximm:1.0 S_AXI RREADY";
  attribute X_INTERFACE_PARAMETER of S_AXI_AWADDR : signal is "PROTOCOL AXI4LITE";
  attribute X_INTERFACE_INFO of irq : signal is "xilinx.com:signal:interrupt:1.0 irq INTERRUPT";
  attribute X_INTERFACE_PARAMETER of irq : signal is "SENSITIVITY LEVEL_HIGH";
end entity axi_can_controller;

architecture rtl of axi_can_controller is

  -- register map: word index = byte offset / 4
  constant IDX_ID : integer := 0;
  constant IDX_CONFIG : integer := 1;
  constant IDX_CTRL : integer := 2;
  constant IDX_CMD : integer := 3;
  constant IDX_STATUS : integer := 4;
  constant IDX_EVENTS : integer := 5;
  constant IDX_IER : integer := 6;
  constant IDX_TX_DONE_ID : integer := 7;
  constant IDX_TX_ID : integer := 8;
  constant IDX_TX_DLC : integer := 9;
  constant IDX_RX_ID : integer := 10;
  constant IDX_RX_DLC : integer := 11;
  constant IDX_TX_DATA : integer := 16;   -- 2 words
  constant IDX_RX_DATA : integer := 32;   -- 2 words
  constant IDX_ACC_ID : integer := 64;   -- 32 words
  constant IDX_ACC_MASK : integer := 96;   -- 32 words
  constant C_NUM_REGS : integer := 128;

  constant K_NONE  : integer := 0;   -- unmapped: reads 0, writes ignored
  constant K_ID    : integer := 1;   -- constant ID word
  constant K_RW    : integer := 2;   -- read/write, masked on write
  constant K_RO    : integer := 3;   -- read-only, decoded in READ_PROC
  constant K_W1C   : integer := 4;   -- status, set by the core, write 1 to clear
  constant K_PULSE : integer := 5;   -- write 1: one-cycle pulse, reads 0
  type t_kinds is array (0 to C_NUM_REGS - 1) of integer;
  constant C_KIND : t_kinds := (0 => K_ID, 1 => K_RO, 2 => K_RW, 3 => K_PULSE, 4 => K_RO, 5 => K_W1C, 6 => K_RW, 7 => K_RO, 8 => K_RW, 9 => K_RW, 10 => K_RO, 11 => K_RO, 16 => K_RW, 17 => K_RW, 32 => K_RO, 33 => K_RO, 64 => K_RW, 65 => K_RW, 66 => K_RW, 67 => K_RW, 68 => K_RW, 69 => K_RW, 70 => K_RW, 71 => K_RW, 72 => K_RW, 73 => K_RW, 74 => K_RW, 75 => K_RW, 76 => K_RW, 77 => K_RW, 78 => K_RW, 79 => K_RW, 80 => K_RW, 81 => K_RW, 82 => K_RW, 83 => K_RW, 84 => K_RW, 85 => K_RW, 86 => K_RW, 87 => K_RW, 88 => K_RW, 89 => K_RW, 90 => K_RW, 91 => K_RW, 92 => K_RW, 93 => K_RW, 94 => K_RW, 95 => K_RW, 96 => K_RW, 97 => K_RW, 98 => K_RW, 99 => K_RW, 100 => K_RW, 101 => K_RW, 102 => K_RW, 103 => K_RW, 104 => K_RW, 105 => K_RW, 106 => K_RW, 107 => K_RW, 108 => K_RW, 109 => K_RW, 110 => K_RW, 111 => K_RW, 112 => K_RW, 113 => K_RW, 114 => K_RW, 115 => K_RW, 116 => K_RW, 117 => K_RW, 118 => K_RW, 119 => K_RW, 120 => K_RW, 121 => K_RW, 122 => K_RW, 123 => K_RW, 124 => K_RW, 125 => K_RW, 126 => K_RW, 127 => K_RW, others => K_NONE);
  constant C_ID_WORD : std_logic_vector(31 downto 0) := x"434E0100";

  type t_regs is array (0 to C_NUM_REGS - 1) of std_logic_vector(31 downto 0);

  -- bits lsb .. lsb + width - 1 set
  function field_mask(lsb, width : integer) return std_logic_vector is
    variable m : std_logic_vector(31 downto 0) := (others => '0');
  begin
    for b in 0 to 31 loop
      if b >= lsb and b < lsb + width then
        m(b) := '1';
      end if;
    end loop;
    return m;
  end function;

  -- value placed at lsb, cut to width; value < 0: all ones
  function field_value(lsb, width, value : integer) return std_logic_vector is
  begin
    if value < 0 then
      return field_mask(lsb, width);
    end if;
    return std_logic_vector(shift_left(to_unsigned(value, 32), lsb)) and field_mask(lsb, width);
  end function;

  -- bits a register stores (0 for unimplemented slots: those flip-flops are removed)
  function reg_mask(idx : integer) return std_logic_vector is
    variable m : std_logic_vector(31 downto 0) := (others => '0');
  begin
    if idx = IDX_CTRL then
      m := field_mask(0, 1) or field_mask(1, 1) or field_mask(2, 1) or field_mask(7, 1);
    end if;
    if idx = IDX_CMD then
      m := field_mask(0, 1) or field_mask(1, 1) or field_mask(2, 1);
    end if;
    if idx = IDX_EVENTS then
      m := field_mask(0, 1) or field_mask(1, 1) or field_mask(2, 1) or field_mask(3, 1) or field_mask(4, 1) or field_mask(5, 1) or field_mask(6, 1);
    end if;
    if idx = IDX_IER then
      m := field_mask(0, 1) or field_mask(1, 1) or field_mask(2, 1) or field_mask(3, 1) or field_mask(4, 1) or field_mask(5, 1) or field_mask(6, 1);
    end if;
    if idx = IDX_TX_ID then
      m := field_mask(0, 29);
    end if;
    if idx = IDX_TX_DLC then
      m := field_mask(0, 4) or field_mask(8, 1) or field_mask(9, 1);
    end if;
    if idx >= IDX_TX_DATA and idx < IDX_TX_DATA + 2 then
      m := field_mask(0, 32);
    end if;
    if idx >= IDX_ACC_ID and idx < IDX_ACC_ID + 32 and idx - IDX_ACC_ID < (C_FILTERS) then
      m := field_mask(0, 29);
    end if;
    if idx >= IDX_ACC_MASK and idx < IDX_ACC_MASK + 32 and idx - IDX_ACC_MASK < (C_FILTERS) then
      m := field_mask(0, 29);
    end if;
    return m;
  end function;

  -- reset value of a register
  function reg_reset(idx : integer) return std_logic_vector is
    variable m : std_logic_vector(31 downto 0) := (others => '0');
  begin
    return m;
  end function;

  -- word index of a byte address, -1 when unmapped
  function addr_index(addr : std_logic_vector) return integer is
    variable n : integer;
  begin
    n := to_integer(unsigned(addr(addr'high downto 2)));
    if n < C_NUM_REGS then
      return n;
    end if;
    return -1;
  end function;

  function or_reduce(v : std_logic_vector) return std_logic is
  begin
    for i in v'range loop
      if v(i) = '1' then return '1'; end if;
    end loop;
    return '0';
  end function;

  signal rst : std_logic;   -- active high

  -- VHDL-93 can't read out ports: internal copies of the handshake outputs
  signal awready, wready, bvalid, arready, rvalid : std_logic;
  signal rdata    : std_logic_vector(31 downto 0);
  signal awaddr_q : std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
  signal araddr_q : std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);

  signal regs   : t_regs;   -- RW, W1C and PULSE storage (PULSE words are high for one cycle)
  signal wr_stb : std_logic_vector(C_NUM_REGS - 1 downto 0);   -- '1' for one cycle after a write to word i
  signal rd_stb : std_logic_vector(C_NUM_REGS - 1 downto 0);   -- '1' for one cycle when word i is read

  -- can_controller outputs
  signal core_o_tx_tready : std_logic;
  signal core_o_tx_done : std_logic;
  signal core_o_tx_arb_lost : std_logic;
  signal core_o_tx_dropped : std_logic;
  signal core_o_tx_done_id : std_logic_vector(28 downto 0);
  signal core_o_rx_id : std_logic_vector(28 downto 0);
  signal core_o_rx_ext : std_logic;
  signal core_o_rx_rtr : std_logic;
  signal core_o_rx_dlc : std_logic_vector(3 downto 0);
  signal core_o_rx_data : std_logic_vector(63 downto 0);
  signal core_o_rx_tvalid : std_logic;
  signal core_o_rx_overrun : std_logic;
  signal core_o_rx_filter : std_logic_vector(4 downto 0);
  signal core_o_error : std_logic;
  signal core_o_error_type : std_logic_vector(2 downto 0);
  signal core_o_error_passive : std_logic;
  signal core_o_bus_off : std_logic;
  signal core_o_error_warning : std_logic;
  signal core_o_tec : std_logic_vector(7 downto 0);
  signal core_o_rec : std_logic_vector(7 downto 0);
  signal core_o_can_tx : std_logic;

  -- glue (ip_spec.json)
  signal core_rst      : std_logic;
  signal tx_valid      : std_logic;
  signal tx_data_flat  : std_logic_vector(63 downto 0);
  signal acc_id_flat   : std_logic_vector(29 * C_FILTERS - 1 downto 0);
  signal acc_mask_flat : std_logic_vector(29 * C_FILTERS - 1 downto 0);
  signal state_now     : std_logic_vector(2 downto 0);
  signal state_q       : std_logic_vector(2 downto 0);
  signal state_chg     : std_logic;

begin

  ----------------------------------------------------------------------------
  -- Instances
  ----------------------------------------------------------------------------

  CORE : entity work.can_controller
    generic map (
      g_CLOCK_FREQUENCY => C_CLOCK_FREQUENCY,
      g_BIT_RATE => C_BIT_RATE,
      g_TQ_PER_BIT => C_TQ_PER_BIT,
      g_PHASE_SEG2 => C_PHASE_SEG2,
      g_SJW => C_SJW,
      g_RX_FIFO_DEPTH => C_RX_FIFO_DEPTH,
      g_TX_BUFFERS => C_TX_BUFFERS,
      g_FILTERS => C_FILTERS
    )
    port map (
      clk => S_AXI_ACLK,
      rst => core_rst,
      i_tx_id => regs(IDX_TX_ID)(28 downto 0),
      i_tx_ext => regs(IDX_TX_DLC)(8),
      i_tx_rtr => regs(IDX_TX_DLC)(9),
      i_tx_dlc => regs(IDX_TX_DLC)(3 downto 0),
      i_tx_data => tx_data_flat,
      i_tx_tvalid => tx_valid,
      o_tx_tready => core_o_tx_tready,
      i_tx_abort => regs(IDX_CMD)(1),
      o_tx_done => core_o_tx_done,
      o_tx_arb_lost => core_o_tx_arb_lost,
      i_one_shot => regs(IDX_CTRL)(2),
      o_tx_dropped => core_o_tx_dropped,
      o_tx_done_id => core_o_tx_done_id,
      o_rx_id => core_o_rx_id,
      o_rx_ext => core_o_rx_ext,
      o_rx_rtr => core_o_rx_rtr,
      o_rx_dlc => core_o_rx_dlc,
      o_rx_data => core_o_rx_data,
      o_rx_tvalid => core_o_rx_tvalid,
      i_rx_tready => regs(IDX_CMD)(2),
      o_rx_overrun => core_o_rx_overrun,
      o_rx_filter => core_o_rx_filter,
      i_acc_id => acc_id_flat,
      i_acc_mask => acc_mask_flat,
      o_error => core_o_error,
      o_error_type => core_o_error_type,
      o_error_passive => core_o_error_passive,
      o_bus_off => core_o_bus_off,
      o_error_warning => core_o_error_warning,
      o_tec => core_o_tec,
      o_rec => core_o_rec,
      i_listen_only => regs(IDX_CTRL)(0),
      i_loopback => regs(IDX_CTRL)(1),
      o_can_tx => core_o_can_tx,
      i_can_rx => can_rx
    );

  ----------------------------------------------------------------------------
  -- Concurrent statements
  ----------------------------------------------------------------------------

  assert C_S_AXI_DATA_WIDTH = 32
    report "axi_can_controller: C_S_AXI_DATA_WIDTH must be 32" severity failure;
  assert C_S_AXI_ADDR_WIDTH >= 9 and C_S_AXI_ADDR_WIDTH <= 32
    report "axi_can_controller: C_S_AXI_ADDR_WIDTH must be 9..32" severity failure;
  assert C_CLOCK_FREQUENCY >= 8000
    report "axi_can_controller: C_CLOCK_FREQUENCY out of range" severity failure;
  assert C_BIT_RATE >= 1000 and C_BIT_RATE <= 1000000
    report "axi_can_controller: C_BIT_RATE out of range" severity failure;
  assert C_TQ_PER_BIT >= 8 and C_TQ_PER_BIT <= 25
    report "axi_can_controller: C_TQ_PER_BIT out of range" severity failure;
  assert C_PHASE_SEG2 >= 1 and C_PHASE_SEG2 <= 8
    report "axi_can_controller: C_PHASE_SEG2 out of range" severity failure;
  assert C_SJW >= 1 and C_SJW <= 4
    report "axi_can_controller: C_SJW out of range" severity failure;
  assert C_RX_FIFO_DEPTH >= 0 and C_RX_FIFO_DEPTH <= 64
    report "axi_can_controller: C_RX_FIFO_DEPTH out of range" severity failure;
  assert C_TX_BUFFERS >= 1 and C_TX_BUFFERS <= 8
    report "axi_can_controller: C_TX_BUFFERS out of range" severity failure;
  assert C_FILTERS >= 1 and C_FILTERS <= 32
    report "axi_can_controller: C_FILTERS out of range" severity failure;
  assert (C_FILTERS) <= 32
    report "axi_can_controller: more ACC_ID registers implemented than reserved" severity failure;
  assert (C_FILTERS) <= 32
    report "axi_can_controller: more ACC_MASK registers implemented than reserved" severity failure;

  rst <= not S_AXI_ARESETN;

  -- AXI outputs ---
  S_AXI_AWREADY <= awready;
  S_AXI_WREADY  <= wready;
  S_AXI_BVALID  <= bvalid;
  S_AXI_BRESP   <= "00";
  S_AXI_ARREADY <= arready;
  S_AXI_RVALID  <= rvalid;
  S_AXI_RDATA   <= rdata;
  S_AXI_RRESP   <= "00";

  -- external pins ---
  can_tx <= core_o_can_tx;

  -- interrupt: level high while an enabled status bit is set ---
  irq <= or_reduce(regs(IDX_EVENTS) and regs(IDX_IER));

  -- glue (ip_spec.json) ---
  -- software reset: CTRL.RESET holds the controller in reset
  core_rst <= rst or regs(IDX_CTRL)(7);
  
  -- TX frame: CMD.TX_SEND queues the frame in TX_ID / TX_DLC / TX_DATA
  TX_PROC : process (S_AXI_ACLK)
  begin
    if rising_edge(S_AXI_ACLK) then
      if core_rst = '1' then
        tx_valid <= '0';
      elsif regs(IDX_CMD)(0) = '1' then
        tx_valid <= '1';
      elsif core_o_tx_tready = '1' then
        tx_valid <= '0';
      end if;
    end if;
  end process;
  
  G_TX_DATA : for i in 0 to 1 generate
    tx_data_flat(i * 32 + 31 downto i * 32) <= regs(IDX_TX_DATA + i);
  end generate;
  
  -- acceptance filters, 29 bits each
  G_FILTERS : for i in 0 to C_FILTERS - 1 generate
    acc_id_flat(i * 29 + 28 downto i * 29)   <= regs(IDX_ACC_ID + i)(28 downto 0);
    acc_mask_flat(i * 29 + 28 downto i * 29) <= regs(IDX_ACC_MASK + i)(28 downto 0);
  end generate;
  
  -- EVENTS.STATE: error state (warning, passive, bus off) changed
  state_now <= core_o_error_warning & core_o_error_passive & core_o_bus_off;
  STATE_PROC : process (S_AXI_ACLK)
  begin
    if rising_edge(S_AXI_ACLK) then
      if rst = '1' then
        state_q <= (others => '0');
      else
        state_q <= state_now;
      end if;
    end if;
  end process;
  state_chg <= '1' when state_q /= state_now else '0';

  ----------------------------------------------------------------------------
  -- Processes
  ----------------------------------------------------------------------------

  -- write channel: AW + W accepted together, one response outstanding
  WRITE_PROC : process (S_AXI_ACLK)
    variable widx  : integer;
    variable bytes : std_logic_vector(31 downto 0);   -- byte lanes of the current write
    variable wsel  : std_logic_vector(31 downto 0);   -- bytes, for the addressed word only
    variable sets  : t_regs;                          -- W1C set bits from the core
  begin
    if rising_edge(S_AXI_ACLK) then
      if rst = '1' then
        awready  <= '0';
        wready   <= '0';
        bvalid   <= '0';
        awaddr_q <= (others => '0');
        wr_stb   <= (others => '0');
        for i in 0 to C_NUM_REGS - 1 loop
          regs(i) <= reg_reset(i);
        end loop;
      else
        -- accept AW and W in the same cycle
        if awready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' and bvalid = '0' then
          awready  <= '1';
          wready   <= '1';
          awaddr_q <= S_AXI_AWADDR;
        else
          awready <= '0';
          wready  <= '0';
        end if;

        -- handshake: write the addressed word, raise BVALID
        widx  := -1;
        bytes := (others => '0');
        if awready = '1' and S_AXI_AWVALID = '1' and wready = '1' and S_AXI_WVALID = '1' then
          widx := addr_index(awaddr_q);
          for b in 0 to 3 loop
            if S_AXI_WSTRB(b) = '1' then
              bytes(8 * b + 7 downto 8 * b) := (others => '1');
            end if;
          end loop;
          bvalid <= '1';
        elsif bvalid = '1' and S_AXI_BREADY = '1' then
          bvalid <= '0';
        end if;

        -- status bits set by the core (a set wins over a simultaneous clear)
        sets := (others => (others => '0'));
        sets(IDX_EVENTS)(0) := core_o_tx_done;
        sets(IDX_EVENTS)(1) := core_o_tx_arb_lost;
        sets(IDX_EVENTS)(2) := core_o_tx_dropped;
        sets(IDX_EVENTS)(3) := core_o_rx_overrun;
        sets(IDX_EVENTS)(4) := core_o_error;
        sets(IDX_EVENTS)(5) := core_o_rx_tvalid;
        sets(IDX_EVENTS)(6) := state_chg;

        for i in 0 to C_NUM_REGS - 1 loop
          if i = widx then
            wsel := bytes;
            wr_stb(i) <= '1';
          else
            wsel := (others => '0');
            wr_stb(i) <= '0';
          end if;
          if C_KIND(i) = K_RW then
            regs(i) <= ((regs(i) and not wsel) or (S_AXI_WDATA and wsel)) and reg_mask(i);
          elsif C_KIND(i) = K_W1C then
            regs(i) <= ((regs(i) and not (S_AXI_WDATA and wsel)) or sets(i)) and reg_mask(i);
          elsif C_KIND(i) = K_PULSE then
            regs(i) <= S_AXI_WDATA and wsel and reg_mask(i);
          else
            regs(i) <= (others => '0');
          end if;
        end loop;
      end if;
    end if;
  end process;

  -- read channel: address captured, then registered data
  READ_PROC : process (S_AXI_ACLK)
    variable ridx : integer;
    variable v    : std_logic_vector(31 downto 0);
  begin
    if rising_edge(S_AXI_ACLK) then
      if rst = '1' then
        arready  <= '0';
        rvalid   <= '0';
        araddr_q <= (others => '0');
        rdata    <= (others => '0');
        rd_stb   <= (others => '0');
      else
        if arready = '0' and S_AXI_ARVALID = '1' and rvalid = '0' then
          arready  <= '1';
          araddr_q <= S_AXI_ARADDR;
        else
          arready <= '0';
        end if;

        rd_stb <= (others => '0');
        if arready = '1' and S_AXI_ARVALID = '1' then
          ridx := addr_index(araddr_q);
          v := (others => '0');
          if ridx >= 0 then
            if C_KIND(ridx) = K_RW or C_KIND(ridx) = K_W1C then
              v := regs(ridx);
            end if;
            rd_stb(ridx) <= '1';
          end if;
          if ridx = IDX_ID then
            v := C_ID_WORD;
          end if;
          if ridx = IDX_CONFIG then
            v(7 downto 0) := std_logic_vector(to_unsigned(C_RX_FIFO_DEPTH, 8));
            v(11 downto 8) := std_logic_vector(to_unsigned(C_TX_BUFFERS, 4));
            v(21 downto 16) := std_logic_vector(to_unsigned(C_FILTERS, 6));
            v(24) := '0';
          end if;
          if ridx = IDX_STATUS then
            v(0) := core_o_tx_tready and not tx_valid;
            v(1) := core_o_rx_tvalid;
            v(2) := core_o_error_warning;
            v(3) := core_o_error_passive;
            v(4) := core_o_bus_off;
            v(10 downto 8) := core_o_error_type;
            v(23 downto 16) := core_o_tec;
            v(31 downto 24) := core_o_rec;
          end if;
          if ridx = IDX_TX_DONE_ID then
            v(28 downto 0) := core_o_tx_done_id;
          end if;
          if ridx = IDX_RX_ID then
            v(28 downto 0) := core_o_rx_id;
          end if;
          if ridx = IDX_RX_DLC then
            v(3 downto 0) := core_o_rx_dlc;
            v(8) := core_o_rx_ext;
            v(9) := core_o_rx_rtr;
            v(20 downto 16) := core_o_rx_filter;
          end if;
          for i in 0 to 1 loop
            if ridx = IDX_RX_DATA + i then
              v(31 downto 0) := core_o_rx_data(i * 32 + 31 downto i * 32);
            end if;
          end loop;
          rdata  <= v;
          rvalid <= '1';
        elsif rvalid = '1' and S_AXI_RREADY = '1' then
          rvalid <= '0';
        end if;
      end if;
    end if;
  end process;

end architecture rtl;
