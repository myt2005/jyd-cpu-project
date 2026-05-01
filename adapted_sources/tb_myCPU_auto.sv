`timescale 1ns / 1ps

module tb_myCPU_auto;
    localparam [31:0] PASS_ADDR   = 32'h8010_0000;
    localparam [31:0] FAIL_ADDR   = 32'h8010_0004;
    localparam [31:0] LED_ADDR    = 32'h8020_0040;
    localparam [31:0] END_PC      = 32'h8000_0010;
    localparam [31:0] END_INST    = 32'h0000_006f;
    localparam [31:0] PASS_EXPECT = 32'd37;
    localparam [31:0] FAIL_EXPECT = 32'd0;
    localparam [31:0] LED_PASS    = 32'h1022_1c08;
    localparam integer MIN_END_CYCLE = 100;
    localparam integer END_STABLE_CYCLES = 16;
    localparam integer STOP_AFTER_37_TESTS = 1;

    reg cpu_clk;
    reg clk_50Mhz;
    reg rst;

    wire [31:0] virtual_led;
    wire [39:0] virtual_seg;

    reg [31:0] pass_cnt;
    reg [31:0] fail_cnt;
    reg [31:0] last_led;
    reg        led_written;
    reg        end_seen;
    reg        rv37_done;

    integer cycle_cnt;
    integer end_cycle;
    integer end_stable_cnt;

    student_top uut (
        .w_cpu_clk   (cpu_clk),
        .w_clk_50Mhz (clk_50Mhz),
        .w_clk_rst   (rst),
        .virtual_key (8'b0),
        .virtual_sw  (64'b0),
        .virtual_led (virtual_led),
        .virtual_seg (virtual_seg)
    );

    initial begin
        cpu_clk = 1'b0;
        forever #5 cpu_clk = ~cpu_clk;
    end

    initial begin
        clk_50Mhz = 1'b0;
        forever #10 clk_50Mhz = ~clk_50Mhz;
    end

    initial begin
        rst = 1'b1;
        pass_cnt = 32'b0;
        fail_cnt = 32'b0;
        last_led = 32'b0;
        led_written = 1'b0;
        end_seen = 1'b0;
        rv37_done = 1'b0;
        cycle_cnt = 0;
        end_cycle = 0;
        end_stable_cnt = 0;

        repeat (20) @(posedge cpu_clk);
        rst = 1'b0;
    end

    always @(posedge cpu_clk) begin
        if (rst) begin
            cycle_cnt <= 0;
            end_seen <= 1'b0;
            end_stable_cnt <= 0;
        end else begin
            cycle_cnt <= cycle_cnt + 1;

            if (uut.perip_wen) begin
                case (uut.perip_addr)
                    PASS_ADDR: begin
                        pass_cnt <= uut.perip_wdata;
                        $display("[%0t] PASS counter write: %0d, pc=0x%08h, inst=0x%08h",
                                 $time, uut.perip_wdata, uut.pc, uut.instruction);

                        if (uut.perip_wdata + fail_cnt == PASS_EXPECT) begin
                            rv37_done <= 1'b1;
                        end
                    end
                    FAIL_ADDR: begin
                        fail_cnt <= uut.perip_wdata;
                        $display("[%0t] FAIL counter write: %0d, pc=0x%08h, inst=0x%08h",
                                 $time, uut.perip_wdata, uut.pc, uut.instruction);

                        if (pass_cnt + uut.perip_wdata == PASS_EXPECT) begin
                            rv37_done <= 1'b1;
                        end
                    end
                    LED_ADDR: begin
                        last_led <= uut.perip_wdata;
                        led_written <= 1'b1;
                        $display("[%0t] LED write: 0x%08h, pc=0x%08h, inst=0x%08h",
                                 $time, uut.perip_wdata, uut.pc, uut.instruction);
                    end
                    default: begin
                    end
                endcase
            end

            if (!end_seen) begin
                if (cycle_cnt >= MIN_END_CYCLE &&
                    uut.pc == END_PC &&
                    uut.instruction == END_INST) begin
                    end_stable_cnt <= end_stable_cnt + 1;

                    if (end_stable_cnt == END_STABLE_CYCLES - 1) begin
                        end_seen <= 1'b1;
                        end_cycle <= cycle_cnt;
                        $display("[%0t] End loop reached at cycle %0d", $time, cycle_cnt);
                    end
                end else begin
                    end_stable_cnt <= 0;
                end
            end
        end
    end

    initial begin
        wait (rst == 1'b0);
        wait (rv37_done == 1'b1);
        repeat (20) @(posedge cpu_clk);

        $display("==== RV32I 37-instruction auto check ====");
        $display("cycle_cnt = %0d", cycle_cnt);
        $display("pass_cnt  = %0d (0x%08h)", pass_cnt, pass_cnt);
        $display("fail_cnt  = %0d (0x%08h)", fail_cnt, fail_cnt);

        if (pass_cnt === PASS_EXPECT && fail_cnt === FAIL_EXPECT) begin
            $display("PASS: RV32I 37 instruction tests passed.");
        end else begin
            $display("FAIL: RV32I 37 instruction tests failed.");
        end

        if (STOP_AFTER_37_TESTS) begin
            $finish;
        end
    end

    initial begin
        wait (rst == 1'b0);
        wait (end_seen == 1'b1);
        repeat (50) @(posedge cpu_clk);

        $display("==== COE program auto check ====");
        $display("cycles_to_end = %0d", end_cycle);
        $display("pass_cnt      = %0d (0x%08h)", pass_cnt, pass_cnt);
        $display("fail_cnt      = %0d (0x%08h)", fail_cnt, fail_cnt);
        $display("last_led      = 0x%08h, led_written = %0d", last_led, led_written);
        $display("pc            = 0x%08h", uut.pc);
        $display("instruction   = 0x%08h", uut.instruction);

        if (pass_cnt === PASS_EXPECT &&
            fail_cnt === FAIL_EXPECT &&
            led_written === 1'b1 &&
            last_led === LED_PASS) begin
            $display("PASS: CPU completed the template COE program.");
        end else begin
            $display("FAIL: CPU did not meet the expected template COE result.");
        end

        $finish;
    end

    initial begin
        #200_000_000;
        $display("TIMEOUT: CPU did not reach the expected end loop.");
        $display("pc          = 0x%08h", uut.pc);
        $display("instruction = 0x%08h", uut.instruction);
        $display("pass_cnt    = %0d (0x%08h)", pass_cnt, pass_cnt);
        $display("fail_cnt    = %0d (0x%08h)", fail_cnt, fail_cnt);
        $display("last_led    = 0x%08h, led_written = %0d", last_led, led_written);
        $finish;
    end
endmodule
