--------------------------------------------------------------------------------
-- Synchronous FIFO with AXI-stream style handshake
-- w1gx
-- Created 2026-11-14
--------------------------------------------------------------------------------
-- Single clock first-in first-out buffer for g_DEPTH words of g_WIDTH bits.
--
--   input  (slave):  a word is written on a rising clk edge with
--                    i_s_tvalid = '1' and o_s_tready = '1' (not full)
--   output (master): o_m_tdata is the oldest word while o_m_tvalid = '1'
--                    (not empty); it is removed with i_m_tready = '1'
--   o_count          number of words stored
--
-- Write and read in the same cycle are allowed (count unchanged). A word
-- written into an empty FIFO is on the output one cycle later. o_s_tready and
-- o_m_tvalid depend only on the fill level, never on the other handshake
-- signal. g_DEPTH need not be a power of two. The memory starts as all zeros
-- (so o_m_tdata is '0' until the first write), is not cleared by rst and has
-- an asynchronous read port (distributed / LUT RAM). While o_m_tvalid = '0',
-- o_m_tdata shows the slot that will be written next and must be ignored.
--------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fifo is
  generic (
    g_WIDTH : positive := 8;
    g_DEPTH : positive := 16
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;   -- synchronous, active high: empties the FIFO
    -- write side
    i_s_tdata  : in  std_logic_vector(g_WIDTH - 1 downto 0);
    i_s_tvalid : in  std_logic;
    o_s_tready : out std_logic;
    -- read side
    o_m_tdata  : out std_logic_vector(g_WIDTH - 1 downto 0);
    o_m_tvalid : out std_logic;
    i_m_tready : in  std_logic;
    o_count    : out natural range 0 to g_DEPTH
  );
end fifo;

architecture rtl of fifo is

  type t_mem is array (0 to g_DEPTH - 1) of std_logic_vector(g_WIDTH - 1 downto 0);
  signal mem : t_mem := (others => (others => '0'));

  signal wr_ptr : natural range 0 to g_DEPTH - 1 := 0;
  signal rd_ptr : natural range 0 to g_DEPTH - 1 := 0;
  signal count  : natural range 0 to g_DEPTH     := 0;

  signal s_ready, m_valid : std_logic;
  signal wr_en, rd_en     : std_logic;

  function next_ptr(p : natural) return natural is
  begin
    if p = g_DEPTH - 1 then return 0; else return p + 1; end if;
  end function;

begin

  ------------------------------------------------------------------------------
  -- Concurrent statements
  ------------------------------------------------------------------------------

  s_ready <= '1' when count < g_DEPTH else '0';
  m_valid <= '1' when count > 0       else '0';
  wr_en   <= i_s_tvalid and s_ready;
  rd_en   <= i_m_tready and m_valid;

  o_s_tready <= s_ready;
  o_m_tvalid <= m_valid;
  o_m_tdata  <= mem(rd_ptr);
  o_count    <= count;

  ------------------------------------------------------------------------------
  -- Processes
  ------------------------------------------------------------------------------

  MEM_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if wr_en = '1' then
        mem(wr_ptr) <= i_s_tdata;
      end if;
    end if;
  end process;

  PTR_PROC : process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        wr_ptr <= 0;
        rd_ptr <= 0;
        count  <= 0;
      else
        if wr_en = '1' then
          wr_ptr <= next_ptr(wr_ptr);
        end if;
        if rd_en = '1' then
          rd_ptr <= next_ptr(rd_ptr);
        end if;
        if wr_en = '1' and rd_en = '0' then
          count <= count + 1;
        elsif wr_en = '0' and rd_en = '1' then
          count <= count - 1;
        end if;
      end if;
    end if;
  end process;

end architecture;
