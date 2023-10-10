// Copyright (c) 2020 Sonal Pinto
// SPDX-License-Identifier: Apache-2.0

`include "vunit_defines.svh"

module tb_kronos_IF_ut;

import kronos_types::*;

logic clk;
logic rstz;
logic [31:0] instr_addr;
logic [31:0] instr_data;
logic instr_req;
logic instr_ack;
pipeIFID_t fetch;
logic fetch_vld;
logic fetch_rdy;
logic [31:0] branch_target;
logic branch;
logic [31:0] immediate;
logic [31:0] regrd_rs1;
logic [31:0] regrd_rs2;
logic regrd_rs1_en;
logic regrd_rs2_en;
logic [31:0] regwr_data;
logic [4:0] regwr_sel;
logic regwr_en;

logic miss;

kronos_IF u_dut (
  .clk          (clk          ),
  .rstz         (rstz         ),
  .instr_addr   (instr_addr   ),
  .instr_data   (instr_data   ),
  .instr_req    (instr_req    ),
  .instr_ack    (instr_ack    ),
  .fetch        (fetch        ),
  .immediate    (immediate    ),
  .regrd_rs1    (regrd_rs1    ),
  .regrd_rs2    (regrd_rs2    ),
  .regrd_rs1_en (regrd_rs1_en ),
  .regrd_rs2_en (regrd_rs2_en ),
  .fetch_vld    (fetch_vld    ),
  .fetch_rdy    (fetch_rdy    ),
  .branch_target(branch_target),
  .branch       (branch       ),
  .regwr_data   (regwr_data   ),
  .regwr_sel    (regwr_sel    ),
  .regwr_en     (regwr_en     )
);

spsram32_model #(.WORDS(256)) u_imem (
  .clk    (clk       ),
  .addr   (instr_addr),
  .wdata  (32'b0     ),
  .rdata  (instr_data),
  .en     (instr_req ),
  .wr_en  (1'b0      ),
  .mask   (4'hf      )
);

always_ff @(posedge clk) begin
  instr_ack <= instr_req & ~miss;
end

default clocking cb @(posedge clk);
  default input #10ps output #10ps;
  input fetch, fetch_vld, instr_req;
  output negedge fetch_rdy;
endclocking

always_ff @(posedge clk) begin
  assert (fetch_vld == u_dut.u_rf.reg_vld);
end

// ============================================================

`TEST_SUITE begin
  `TEST_SUITE_SETUP begin
    clk = 0;
    rstz = 0;
    miss = 0;

    branch = 0;
    branch_target = 0;
    fetch_rdy = 0;
    regwr_en = 0;

    for(int i=0; i<256; i++)
      u_imem.MEM[i] = $urandom;

    fork 
      forever #1ns clk = ~clk;
    join_none

    ##4 rstz = 1;
  end

  `TEST_CASE("ideal") begin
    logic [31:0] expected_pc;
    
    expected_pc = 0;
    fetch_rdy = 1;

    repeat(1024) begin
      @(cb iff fetch_vld) begin        
        $display("PC=%h, IR=%h", fetch.pc, fetch.ir);
        assert(fetch.ir == u_imem.MEM[fetch.pc[9:2]]);
        assert(expected_pc == fetch.pc);
        expected_pc += 4;
      end
    end
    ##64;
  end

  `TEST_CASE("stall") begin
    // backpressure from ID, i.e. stall
    logic [31:0] expected_pc;

    expected_pc = 0;
    fetch_rdy = 1;

    repeat(1024) begin
      @(cb iff fetch_vld) begin
        // random chance of backpressure from memory
        if ($urandom_range(0,1)) begin
          cb.fetch_rdy <= 0;
          ##($urandom_range(1,4));
        end
        cb.fetch_rdy <= 1;

        $display("PC=%h, IR=%h", fetch.pc, fetch.ir);
        assert(fetch.ir == u_imem.MEM[fetch.pc[9:2]]);
        assert(expected_pc == fetch.pc);
        expected_pc += 4;
      end
    end
    ##64;
  end

  `TEST_CASE("miss") begin
    // backpressure from memory, i.e. miss
    logic [31:0] expected_pc;

    expected_pc = 0;
    fetch_rdy = 1;

    fork
      forever @(negedge clk) begin
        // random chance of miss (arbitration loss or miss)
        if ($urandom_range(0,1)) begin
          miss = 1;
          ##($urandom_range(1,4));
        end
        @(negedge clk);
        miss = 0;
      end

      repeat(1024) begin
        @(cb iff fetch_vld) begin        
          $display("PC=%h, IR=%h", fetch.pc, fetch.ir);
          assert(fetch.ir == u_imem.MEM[fetch.pc[9:2]]);
          assert(expected_pc == fetch.pc);
          expected_pc += 4;
        end
      end
    join_any

    ##64;
  end

  `TEST_CASE("miss_and_stall") begin
    // backpressure from memory, i.e. miss
    logic [31:0] expected_pc;

    expected_pc = 0;
    fetch_rdy = 1;

    fork
      forever @(negedge clk) begin
        // random chance of miss (arbitration loss or miss)
        if ($urandom_range(0,1)) begin
          miss = 1;
          ##($urandom_range(1,4));
        end
        @(negedge clk);
        miss = 0;
      end

      repeat(1024) begin
        @(cb iff fetch_vld) begin
           // random chance of backpressure from memory
          if ($urandom_range(0,1)) begin
            cb.fetch_rdy <= 0;
            ##($urandom_range(1,4));
          end
          cb.fetch_rdy <= 1;

          $display("PC=%h, IR=%h", fetch.pc, fetch.ir);
          assert(fetch.ir == u_imem.MEM[fetch.pc[9:2]]);
          assert(expected_pc == fetch.pc);
          expected_pc += 4;
        end
      end
    join_any

    ##64;
  end
end

`WATCHDOG(1ms);

endmodule
