-------------------------------------------------------------------------------
-- controls.vhd
--
-- GRISC ASIP control unit FSM.
--
-- Implemented instructions: ori, lw, beq, send, add, j, recv, wpix, plus
-- placeholders for sub, sll, srl, sra, and, or, xor, slt, sgt, seq, jr,
-- rpix, bne, sw, jal, clrscr -- all reuse the same Rops/Iops/Jops scaffolding.
--
-- Timing rules (very important for the FSM):
--   * The register file has ASYNC reads, so 1 wait state between assigning
--     rID and reading regrD is enough (see sRopsRd, sIopsRd).
--   * The instruction memory (irMem), data memory (dMem), framebuffer port 1,
--     and ALU are all SYNCHRONOUS, which means we need *2* clock edges
--     between driving an address/operand and consuming its output. That
--     gives us the sFetch->sIrWait->sDecode pattern as well as the
--     sLwDrive->sLwSettle->sLwWait pattern, the sCalcDrive->sCalcSettle->
--     sCalcWait pattern, and the sRpixDrive->sRpixSettle->sRpixWait pattern.
-------------------------------------------------------------------------------

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity controls is
    Port (
        clk            : in  std_logic;
        en             : in  std_logic;
        rst            : in  std_logic;

        -- Register file
        rID1           : out std_logic_vector(4 downto 0);
        rID2           : out std_logic_vector(4 downto 0);
        wr_enR1        : out std_logic;
        wr_enR2        : out std_logic;
        regrD1         : in  std_logic_vector(15 downto 0);
        regrD2         : in  std_logic_vector(15 downto 0);
        regwD1         : out std_logic_vector(15 downto 0);
        regwD2         : out std_logic_vector(15 downto 0);

        -- Framebuffer (CPU side)
        fbRST          : out std_logic;
        fbAddr1        : out std_logic_vector(11 downto 0);
        fbDin1         : in  std_logic_vector(15 downto 0);
        fbDout1        : out std_logic_vector(15 downto 0);
        fbWr_en        : out std_logic;

        -- Instruction memory
        irAddr         : out std_logic_vector(13 downto 0);
        irWord         : in  std_logic_vector(31 downto 0);

        -- Data memory
        dAddr          : out std_logic_vector(14 downto 0);
        d_wr_en        : out std_logic;
        dOut           : out std_logic_vector(15 downto 0);
        dIn            : in  std_logic_vector(15 downto 0);

        -- ALU
        aluA           : out std_logic_vector(15 downto 0);
        aluB           : out std_logic_vector(15 downto 0);
        aluOp          : out std_logic_vector(3 downto 0);
        aluResult      : in  std_logic_vector(15 downto 0);

        -- UART
        ready          : in  std_logic;
        newChar        : in  std_logic;
        send           : out std_logic;
        charRec        : in  std_logic_vector(7 downto 0);
        charSend       : out std_logic_vector(7 downto 0)
    );
end controls;

architecture Behavioral of controls is
    type state_t is (
        sFetch,      sIrWait,     sDecode,
        sRops,       sRopsRd,
        sCalcDrive,  sCalcSettle, sCalcWait,
        sIops,       sIopsRd,
        sJops,
        sEquals,     sNequal,     sOri,
        sLwDrive,    sLwSettle,   sLwWait,    sSw,
        sJmp,        sJal,        sClrscr,
        sSendDrive,  sSendStart,  sSendWait,
        sRecv,
        sRpixDrive,  sRpixSettle, sRpixWait,
        sWpixRd,     sWpix,
        sJrRd,       sJrAct,
        sStore,      sFinish
    );

    signal state   : state_t := sFetch;

    signal ir      : std_logic_vector(31 downto 0) := (others => '0');
    signal pc_sig  : unsigned(15 downto 0)         := (others => '0');
    signal alu_res : std_logic_vector(15 downto 0) := (others => '0');

    -- Convenience aliases
    signal opcode  : std_logic_vector(4 downto 0);
    signal op_low  : std_logic_vector(2 downto 0);
    signal imm16   : std_logic_vector(15 downto 0);
    signal immJ    : std_logic_vector(15 downto 0);
begin
    opcode <= ir(31 downto 27);
    op_low <= ir(29 downto 27);
    imm16  <= ir(16 downto 1);
    immJ   <= ir(26 downto 11);

    process(clk)
    begin
        if rising_edge(clk) then
            -- Per-cycle defaults so all strobes auto de-assert.
            wr_enR1 <= '0';
            wr_enR2 <= '0';
            d_wr_en <= '0';
            fbWr_en <= '0';
            fbRST   <= '0';
            send    <= '0';

            if rst = '1' then
                state   <= sFetch;
                pc_sig  <= (others => '0');
                ir      <= (others => '0');
                alu_res <= (others => '0');
                rID1    <= (others => '0');
                rID2    <= (others => '0');
                irAddr  <= (others => '0');
                dAddr   <= (others => '0');
                fbAddr1 <= (others => '0');
                aluA    <= (others => '0');
                aluB    <= (others => '0');
                aluOp   <= (others => '0');
            elsif en = '1' then
                case state is

                    -------------------------------------------------------
                    -- Fetch / Decode (sync ROM => 2 cycle latency)
                    -------------------------------------------------------
                    when sFetch =>
                        irAddr <= std_logic_vector(pc_sig(13 downto 0));
                        state  <= sIrWait;

                    when sIrWait =>
                        state <= sDecode;

                    when sDecode =>
                        ir      <= irWord;
                        pc_sig  <= pc_sig + 1;
                        regwD1  <= std_logic_vector(pc_sig + 1);
                        rID1    <= "00001";
                        wr_enR1 <= '1';
                        case irWord(31 downto 30) is
                            when "00" | "01" => state <= sRops;
                            when "10"        => state <= sIops;
                            when others      => state <= sJops;
                        end case;

                    -------------------------------------------------------
                    -- R-type
                    -------------------------------------------------------
                    when sRops =>
                        rID1  <= ir(21 downto 17);
                        rID2  <= ir(16 downto 12);
                        state <= sRopsRd;

                    when sRopsRd =>
                        case opcode is
                            when "01101" =>            -- jr
                                rID1  <= ir(26 downto 22);
                                state <= sJrRd;
                            when "01100" =>            -- recv
                                state <= sRecv;
                            when "01111" =>            -- rpix
                                state <= sRpixDrive;
                            when "01110" =>            -- wpix
                                rID1  <= ir(26 downto 22);
                                rID2  <= ir(21 downto 17);
                                state <= sWpixRd;
                            when "01011" =>            -- send
                                rID1  <= ir(26 downto 22);
                                state <= sSendDrive;
                            when others =>             -- calc
                                state <= sCalcDrive;
                        end case;

                    when sCalcDrive =>
                        aluA  <= regrD1;
                        aluB  <= regrD2;
                        aluOp <= ir(30 downto 27);
                        state <= sCalcSettle;

                    when sCalcSettle =>
                        state <= sCalcWait;

                    when sCalcWait =>
                        alu_res <= aluResult;
                        state   <= sStore;

                    -------------------------------------------------------
                    -- I-type
                    -------------------------------------------------------
                    when sIops =>
                        rID1  <= ir(21 downto 17);
                        rID2  <= ir(26 downto 22);
                        state <= sIopsRd;

                    when sIopsRd =>
                        case op_low is
                            when "000"  => state <= sEquals;
                            when "001"  => state <= sNequal;
                            when "010"  => state <= sOri;
                            when "011"  => state <= sLwDrive;
                            when others => state <= sSw;
                        end case;

                    when sOri =>
                        alu_res <= regrD1 or imm16;
                        state   <= sStore;

                    when sLwDrive =>
                        dAddr <= std_logic_vector(
                                   resize(unsigned(regrD1), 15) +
                                   resize(unsigned(imm16),  15));
                        state <= sLwSettle;

                    when sLwSettle =>
                        state <= sLwWait;

                    when sLwWait =>
                        alu_res <= dIn;
                        state   <= sStore;

                    when sEquals =>
                        if regrD1 = regrD2 then
                            pc_sig  <= unsigned(imm16);
                            regwD1  <= imm16;
                            rID1    <= "00001";
                            wr_enR1 <= '1';
                        end if;
                        state <= sFinish;

                    when sNequal =>
                        if regrD1 /= regrD2 then
                            pc_sig  <= unsigned(imm16);
                            regwD1  <= imm16;
                            rID1    <= "00001";
                            wr_enR1 <= '1';
                        end if;
                        state <= sFinish;

                    when sSw =>
                        dAddr <= std_logic_vector(
                                   resize(unsigned(regrD1), 15) +
                                   resize(unsigned(imm16),  15));
                        dOut    <= regrD2;
                        d_wr_en <= '1';
                        state   <= sFinish;

                    -------------------------------------------------------
                    -- J-type
                    -------------------------------------------------------
                    when sJops =>
                        case opcode is
                            when "11000" => state <= sJmp;
                            when "11001" => state <= sJal;
                            when others  => state <= sClrscr;
                        end case;

                    when sJmp =>
                        pc_sig  <= unsigned(immJ);
                        regwD1  <= immJ;
                        rID1    <= "00001";
                        wr_enR1 <= '1';
                        state   <= sFinish;

                    when sJal =>
                        regwD1  <= std_logic_vector(pc_sig);
                        rID1    <= "00010";
                        wr_enR1 <= '1';
                        pc_sig  <= unsigned(immJ);
                        regwD2  <= immJ;
                        rID2    <= "00001";
                        wr_enR2 <= '1';
                        state   <= sFinish;

                    when sClrscr =>
                        fbRST <= '1';
                        state <= sFinish;

                    -------------------------------------------------------
                    -- ASIP - send. Drive a one-cycle send pulse to the UART
                    -- (which is asynchronous to en), then wait for ready=1
                    -- to indicate the byte left the shift register.
                    -------------------------------------------------------
                    when sSendDrive =>
                        -- Wait for UART to be idle, then drive send for one cycle.
                        charSend <= regrD1(7 downto 0);
                        if ready = '1' then
                            send  <= '1';
                            state <= sSendStart;
                        end if;

                    when sSendStart =>
                        -- UART captured: ready will drop to 0.
                        if ready = '0' then
                            state <= sSendWait;
                        end if;

                    when sSendWait =>
                        -- UART finished: ready returns to 1.
                        if ready = '1' then
                            state <= sFinish;
                        end if;

                    -------------------------------------------------------
                    -- ASIP - recv: block until UART announces newChar.
                    -------------------------------------------------------
                    when sRecv =>
                        if newChar = '1' then
                            alu_res <= x"00" & charRec;
                            state   <= sStore;
                        end if;

                    -------------------------------------------------------
                    -- ASIP - rpix (sync read framebuffer)
                    -------------------------------------------------------
                    when sRpixDrive =>
                        fbAddr1 <= regrD1(11 downto 0);
                        state   <= sRpixSettle;

                    when sRpixSettle =>
                        state <= sRpixWait;

                    when sRpixWait =>
                        alu_res <= fbDin1;
                        state   <= sStore;

                    -------------------------------------------------------
                    -- ASIP - wpix
                    -------------------------------------------------------
                    when sWpixRd =>
                        state <= sWpix;

                    when sWpix =>
                        fbAddr1 <= regrD1(11 downto 0);
                        fbDout1 <= regrD2;
                        fbWr_en <= '1';
                        state   <= sFinish;

                    -------------------------------------------------------
                    -- jr
                    -------------------------------------------------------
                    when sJrRd =>
                        state <= sJrAct;

                    when sJrAct =>
                        pc_sig  <= unsigned(regrD1);
                        regwD1  <= regrD1;
                        rID1    <= "00001";
                        wr_enR1 <= '1';
                        state   <= sFinish;

                    -------------------------------------------------------
                    -- Common store / finish
                    -------------------------------------------------------
                    when sStore =>
                        regwD1  <= alu_res;
                        rID1    <= ir(26 downto 22);
                        wr_enR1 <= '1';
                        state   <= sFinish;

                    when sFinish =>
                        state <= sFetch;

                    when others =>
                        state <= sFetch;
                end case;
            end if;
        end if;
    end process;
end Behavioral;
