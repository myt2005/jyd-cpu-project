`timescale 1ns / 1ps

module myCPU (
    input  wire         cpu_rst,
    input  wire         cpu_clk,

    output wire [31:0]  irom_addr,
    input  wire [31:0]  irom_data,

    output wire [31:0]  perip_addr,
    output wire         perip_wen,
    output reg  [1:0]   perip_mask,
    output wire [31:0]  perip_wdata,
    input  wire [31:0]  perip_rdata
);

// ============================================================
// 说明：
// 1) 差分 200MHz 时钟 sysclk_p/sysclk_n -> IBUFDS -> BUFG -> cpu_clk_raw
// 2) 再二分频得到 cpu_clk，供 CPU 主体使用
// 3) 所有 CPU 状态寄存器均改为异步高电平复位，解决 pc / 流水寄存器一直为 X 的问题
// 4) 支持 RV32I 教学子集：
//    LUI/AUIPC/JAL/JALR
//    BEQ/BNE/BLT/BGE/BLTU/BGEU
//    LB/LH/LW/LBU/LHU
//    SB/SH/SW
//    ADDI/SLTI/SLTIU/XORI/ORI/ANDI/SLLI/SRLI/SRAI
//    ADD/SUB/SLL/SLT/SLTU/XOR/SRL/SRA/OR/AND
// ============================================================

// ------------------------- 时钟部分 ------------------------- //
// The template top level already generates and distributes cpu_clk.
// Keep board-level differential clock handling outside this core.
localparam RESET_PC = 32'h8000_0000;

// ------------------------- 通用函数 ------------------------- //
function [31:0] load_ext;
    input [2:0]  funct3;
    input [31:0] rdata;
    begin
        case (funct3)
            3'b000: load_ext = {{24{rdata[7]}},  rdata[7:0]};   // LB
            3'b001: load_ext = {{16{rdata[15]}}, rdata[15:0]};  // LH
            3'b010: load_ext = rdata;                           // LW
            3'b100: load_ext = {24'b0, rdata[7:0]};            // LBU
            3'b101: load_ext = {16'b0, rdata[15:0]};           // LHU
            default: load_ext = 32'b0;
        endcase
    end
endfunction

// ------------------------- ALU 编码 ------------------------- //
localparam ALU_ADD  = 4'd0;
localparam ALU_SUB  = 4'd1;
localparam ALU_SLL  = 4'd2;
localparam ALU_SLT  = 4'd3;
localparam ALU_SLTU = 4'd4;
localparam ALU_XOR  = 4'd5;
localparam ALU_SRL  = 4'd6;
localparam ALU_SRA  = 4'd7;
localparam ALU_OR   = 4'd8;
localparam ALU_AND  = 4'd9;
localparam ALU_PASS = 4'd10;

// ------------------------- IF ------------------------- //
reg  [31:0] pc;
wire [31:0] pc_plus4_if;
wire [31:0] next_pc;
wire        stall;
wire        flush;
wire        ex_branch_taken;
wire [31:0] ex_branch_target;

assign pc_plus4_if = pc + 32'd4;
assign flush       = ex_branch_taken;
assign next_pc     = ex_branch_taken ? ex_branch_target : pc_plus4_if;
assign irom_addr   = pc;

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst)
        pc <= RESET_PC;
    else if (!stall)
        pc <= next_pc;
end

// ------------------------- IF/ID ------------------------- //
reg [31:0] if_id_pc;
reg [31:0] if_id_inst;

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        if_id_pc   <= 32'b0;
        if_id_inst <= 32'h0000_0013; // NOP = addi x0,x0,0
    end else if (flush) begin
        if_id_pc   <= 32'b0;
        if_id_inst <= 32'h0000_0013;
    end else if (!stall) begin
        if_id_pc   <= pc;
        if_id_inst <= irom_data;
    end
end

// ------------------------- ID 译码 ------------------------- //
wire [31:0] id_inst;
wire [31:0] id_pc;
wire [31:0] id_pc4;
wire [6:0]  id_opcode;
wire [4:0]  id_rd;
wire [2:0]  id_funct3;
wire [4:0]  id_rs1;
wire [4:0]  id_rs2;
wire [6:0]  id_funct7;

wire [31:0] id_i_imm;
wire [31:0] id_s_imm;
wire [31:0] id_b_imm;
wire [31:0] id_u_imm;
wire [31:0] id_j_imm;

assign id_inst   = if_id_inst;
assign id_pc     = if_id_pc;
assign id_pc4    = id_pc + 32'd4;
assign id_opcode = id_inst[6:0];
assign id_rd     = id_inst[11:7];
assign id_funct3 = id_inst[14:12];
assign id_rs1    = id_inst[19:15];
assign id_rs2    = id_inst[24:20];
assign id_funct7 = id_inst[31:25];

assign id_i_imm = {{20{id_inst[31]}}, id_inst[31:20]};
assign id_s_imm = {{20{id_inst[31]}}, id_inst[31:25], id_inst[11:7]};
assign id_b_imm = {{20{id_inst[31]}}, id_inst[7], id_inst[30:25], id_inst[11:8], 1'b0};
assign id_u_imm = {id_inst[31:12], 12'b0};
assign id_j_imm = {{12{id_inst[31]}}, id_inst[19:12], id_inst[20], id_inst[30:21], 1'b0};

wire id_inst_lui, id_inst_auipc, id_inst_jal, id_inst_jalr;
wire id_inst_beq, id_inst_bne, id_inst_blt, id_inst_bge, id_inst_bltu, id_inst_bgeu;
wire id_inst_lb, id_inst_lh, id_inst_lw, id_inst_lbu, id_inst_lhu;
wire id_inst_sb, id_inst_sh, id_inst_sw;
wire id_inst_addi, id_inst_slti, id_inst_sltiu, id_inst_xori, id_inst_ori, id_inst_andi, id_inst_slli, id_inst_srli, id_inst_srai;
wire id_inst_add, id_inst_sub, id_inst_sll, id_inst_slt, id_inst_sltu, id_inst_xor, id_inst_srl, id_inst_sra, id_inst_or, id_inst_and;
wire id_inst_load, id_inst_store, id_inst_branch, id_inst_op_imm, id_inst_op, id_valid_inst;

assign id_inst_lui    = (id_opcode == 7'b0110111);
assign id_inst_auipc  = (id_opcode == 7'b0010111);
assign id_inst_jal    = (id_opcode == 7'b1101111);
assign id_inst_jalr   = (id_opcode == 7'b1100111) & (id_funct3 == 3'b000);
assign id_inst_beq    = (id_opcode == 7'b1100011) & (id_funct3 == 3'b000);
assign id_inst_bne    = (id_opcode == 7'b1100011) & (id_funct3 == 3'b001);
assign id_inst_blt    = (id_opcode == 7'b1100011) & (id_funct3 == 3'b100);
assign id_inst_bge    = (id_opcode == 7'b1100011) & (id_funct3 == 3'b101);
assign id_inst_bltu   = (id_opcode == 7'b1100011) & (id_funct3 == 3'b110);
assign id_inst_bgeu   = (id_opcode == 7'b1100011) & (id_funct3 == 3'b111);
assign id_inst_lb     = (id_opcode == 7'b0000011) & (id_funct3 == 3'b000);
assign id_inst_lh     = (id_opcode == 7'b0000011) & (id_funct3 == 3'b001);
assign id_inst_lw     = (id_opcode == 7'b0000011) & (id_funct3 == 3'b010);
assign id_inst_lbu    = (id_opcode == 7'b0000011) & (id_funct3 == 3'b100);
assign id_inst_lhu    = (id_opcode == 7'b0000011) & (id_funct3 == 3'b101);
assign id_inst_sb     = (id_opcode == 7'b0100011) & (id_funct3 == 3'b000);
assign id_inst_sh     = (id_opcode == 7'b0100011) & (id_funct3 == 3'b001);
assign id_inst_sw     = (id_opcode == 7'b0100011) & (id_funct3 == 3'b010);
assign id_inst_addi   = (id_opcode == 7'b0010011) & (id_funct3 == 3'b000);
assign id_inst_slti   = (id_opcode == 7'b0010011) & (id_funct3 == 3'b010);
assign id_inst_sltiu  = (id_opcode == 7'b0010011) & (id_funct3 == 3'b011);
assign id_inst_xori   = (id_opcode == 7'b0010011) & (id_funct3 == 3'b100);
assign id_inst_ori    = (id_opcode == 7'b0010011) & (id_funct3 == 3'b110);
assign id_inst_andi   = (id_opcode == 7'b0010011) & (id_funct3 == 3'b111);
assign id_inst_slli   = (id_opcode == 7'b0010011) & (id_funct3 == 3'b001) & (id_funct7 == 7'b0000000);
assign id_inst_srli   = (id_opcode == 7'b0010011) & (id_funct3 == 3'b101) & (id_funct7 == 7'b0000000);
assign id_inst_srai   = (id_opcode == 7'b0010011) & (id_funct3 == 3'b101) & (id_funct7 == 7'b0100000);
assign id_inst_add    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b000) & (id_funct7 == 7'b0000000);
assign id_inst_sub    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b000) & (id_funct7 == 7'b0100000);
assign id_inst_sll    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b001) & (id_funct7 == 7'b0000000);
assign id_inst_slt    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b010) & (id_funct7 == 7'b0000000);
assign id_inst_sltu   = (id_opcode == 7'b0110011) & (id_funct3 == 3'b011) & (id_funct7 == 7'b0000000);
assign id_inst_xor    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b100) & (id_funct7 == 7'b0000000);
assign id_inst_srl    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b101) & (id_funct7 == 7'b0000000);
assign id_inst_sra    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b101) & (id_funct7 == 7'b0100000);
assign id_inst_or     = (id_opcode == 7'b0110011) & (id_funct3 == 3'b110) & (id_funct7 == 7'b0000000);
assign id_inst_and    = (id_opcode == 7'b0110011) & (id_funct3 == 3'b111) & (id_funct7 == 7'b0000000);

assign id_inst_load   = id_inst_lb | id_inst_lh | id_inst_lw | id_inst_lbu | id_inst_lhu;
assign id_inst_store  = id_inst_sb | id_inst_sh | id_inst_sw;
assign id_inst_branch = id_inst_beq | id_inst_bne | id_inst_blt | id_inst_bge | id_inst_bltu | id_inst_bgeu;
assign id_inst_op_imm = id_inst_addi | id_inst_slti | id_inst_sltiu | id_inst_xori | id_inst_ori | id_inst_andi | id_inst_slli | id_inst_srli | id_inst_srai;
assign id_inst_op     = id_inst_add | id_inst_sub | id_inst_sll | id_inst_slt | id_inst_sltu | id_inst_xor | id_inst_srl | id_inst_sra | id_inst_or | id_inst_and;
assign id_valid_inst  = id_inst_lui | id_inst_auipc | id_inst_jal | id_inst_jalr | id_inst_branch | id_inst_load | id_inst_store | id_inst_op_imm | id_inst_op;

// 寄存器堆
reg [31:0] reg_file [0:31];
integer i;
wire [31:0] id_rs1_data;
wire [31:0] id_rs2_data;
wire [31:0] wb_data;
reg        mem_wb_valid;
reg [4:0]  mem_wb_rd;
reg [31:0] mem_wb_alu_result;
reg [31:0] mem_wb_mem_data;
reg [31:0] mem_wb_pc4;
reg [1:0]  mem_wb_wb_sel;
reg        mem_wb_reg_we;
reg [31:0] mem_wb_inst;
assign id_rs1_data = (id_rs1 == 5'd0) ? 32'b0 :
                     (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd == id_rs1)) ? wb_data :
                      reg_file[id_rs1];
assign id_rs2_data = (id_rs2 == 5'd0) ? 32'b0 :
                     (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd == id_rs2)) ? wb_data :
                      reg_file[id_rs2];

// ID 控制信号
reg        id_reg_we;
reg        id_mem_we;
reg        id_mem_re;
reg [3:0]  id_alu_sel;
reg [1:0]  id_src1_sel;   // 0:rs1 1:pc 2:zero
reg [2:0]  id_src2_sel;   // 0:rs2 1:i_imm 2:s_imm 3:u_imm 4:4
reg [1:0]  id_wb_sel;     // 0:alu 1:mem 2:pc+4
reg        id_is_branch;
reg        id_is_jal;
reg        id_is_jalr;
reg        id_is_load;
reg        id_is_store;
reg [2:0]  id_load_funct3;
reg [2:0]  id_store_funct3;
reg [31:0] id_branch_imm;

always @(*) begin
    id_reg_we       = 1'b0;
    id_mem_we       = 1'b0;
    id_mem_re       = 1'b0;
    id_alu_sel      = ALU_ADD;
    id_src1_sel     = 2'd0;
    id_src2_sel     = 3'd0;
    id_wb_sel       = 2'd0;
    id_is_branch    = 1'b0;
    id_is_jal       = 1'b0;
    id_is_jalr      = 1'b0;
    id_is_load      = 1'b0;
    id_is_store     = 1'b0;
    id_load_funct3  = id_funct3;
    id_store_funct3 = id_funct3;
    id_branch_imm   = id_b_imm;

    case (1'b1)
        id_inst_lui: begin
            id_reg_we   = 1'b1;
            id_alu_sel  = ALU_PASS;
            id_src1_sel = 2'd2;
            id_src2_sel = 3'd3;
            id_wb_sel   = 2'd0;
        end
        id_inst_auipc: begin
            id_reg_we   = 1'b1;
            id_alu_sel  = ALU_ADD;
            id_src1_sel = 2'd1;
            id_src2_sel = 3'd3;
            id_wb_sel   = 2'd0;
        end
        id_inst_jal: begin
            id_reg_we     = 1'b1;
            id_is_jal     = 1'b1;
            id_wb_sel     = 2'd2;
            id_branch_imm = id_j_imm;
        end
        id_inst_jalr: begin
            id_reg_we   = 1'b1;
            id_is_jalr  = 1'b1;
            id_wb_sel   = 2'd2;
            id_src1_sel = 2'd0;
            id_src2_sel = 3'd1;
            id_alu_sel  = ALU_ADD;
        end
        id_inst_beq, id_inst_bne, id_inst_blt, id_inst_bge, id_inst_bltu, id_inst_bgeu: begin
            id_is_branch = 1'b1;
        end
        id_inst_lb, id_inst_lh, id_inst_lw, id_inst_lbu, id_inst_lhu: begin
            id_reg_we      = 1'b1;
            id_mem_re      = 1'b1;
            id_is_load     = 1'b1;
            id_src1_sel    = 2'd0;
            id_src2_sel    = 3'd1;
            id_alu_sel     = ALU_ADD;
            id_wb_sel      = 2'd1;
            id_load_funct3 = id_funct3;
        end
        id_inst_sb, id_inst_sh, id_inst_sw: begin
            id_mem_we       = 1'b1;
            id_is_store     = 1'b1;
            id_src1_sel     = 2'd0;
            id_src2_sel     = 3'd2;
            id_alu_sel      = ALU_ADD;
            id_store_funct3 = id_funct3;
        end
        id_inst_addi:  begin id_reg_we=1'b1; id_alu_sel=ALU_ADD;  id_src2_sel=3'd1; end
        id_inst_slti:  begin id_reg_we=1'b1; id_alu_sel=ALU_SLT;  id_src2_sel=3'd1; end
        id_inst_sltiu: begin id_reg_we=1'b1; id_alu_sel=ALU_SLTU; id_src2_sel=3'd1; end
        id_inst_xori:  begin id_reg_we=1'b1; id_alu_sel=ALU_XOR;  id_src2_sel=3'd1; end
        id_inst_ori:   begin id_reg_we=1'b1; id_alu_sel=ALU_OR;   id_src2_sel=3'd1; end
        id_inst_andi:  begin id_reg_we=1'b1; id_alu_sel=ALU_AND;  id_src2_sel=3'd1; end
        id_inst_slli:  begin id_reg_we=1'b1; id_alu_sel=ALU_SLL;  id_src2_sel=3'd1; end
        id_inst_srli:  begin id_reg_we=1'b1; id_alu_sel=ALU_SRL;  id_src2_sel=3'd1; end
        id_inst_srai:  begin id_reg_we=1'b1; id_alu_sel=ALU_SRA;  id_src2_sel=3'd1; end
        id_inst_add:   begin id_reg_we=1'b1; id_alu_sel=ALU_ADD;  id_src2_sel=3'd0; end
        id_inst_sub:   begin id_reg_we=1'b1; id_alu_sel=ALU_SUB;  id_src2_sel=3'd0; end
        id_inst_sll:   begin id_reg_we=1'b1; id_alu_sel=ALU_SLL;  id_src2_sel=3'd0; end
        id_inst_slt:   begin id_reg_we=1'b1; id_alu_sel=ALU_SLT;  id_src2_sel=3'd0; end
        id_inst_sltu:  begin id_reg_we=1'b1; id_alu_sel=ALU_SLTU; id_src2_sel=3'd0; end
        id_inst_xor:   begin id_reg_we=1'b1; id_alu_sel=ALU_XOR;  id_src2_sel=3'd0; end
        id_inst_srl:   begin id_reg_we=1'b1; id_alu_sel=ALU_SRL;  id_src2_sel=3'd0; end
        id_inst_sra:   begin id_reg_we=1'b1; id_alu_sel=ALU_SRA;  id_src2_sel=3'd0; end
        id_inst_or:    begin id_reg_we=1'b1; id_alu_sel=ALU_OR;   id_src2_sel=3'd0; end
        id_inst_and:   begin id_reg_we=1'b1; id_alu_sel=ALU_AND;  id_src2_sel=3'd0; end
        default: begin end
    endcase
end

wire id_use_rs1;
wire id_use_rs2;
assign id_use_rs1 = id_inst_jalr | id_inst_branch | id_inst_load | id_inst_store | id_inst_op_imm | id_inst_op;
assign id_use_rs2 = id_inst_branch | id_inst_store | id_inst_op;

// ------------------------- ID/EX ------------------------- //
reg        id_ex_valid;
reg [4:0]  id_ex_rs1_idx;
reg [4:0]  id_ex_rs2_idx;
reg [4:0]  id_ex_rd;
reg [31:0] id_ex_pc;
reg [31:0] id_ex_pc4;
reg [31:0] id_ex_rs1_val;
reg [31:0] id_ex_rs2_val;
reg [31:0] id_ex_i_imm;
reg [31:0] id_ex_s_imm;
reg [31:0] id_ex_u_imm;
reg [31:0] id_ex_branch_imm;
reg [2:0]  id_ex_funct3;
reg [3:0]  id_ex_alu_sel;
reg [1:0]  id_ex_src1_sel;
reg [2:0]  id_ex_src2_sel;
reg [1:0]  id_ex_wb_sel;
reg        id_ex_reg_we;
reg        id_ex_mem_we;
reg        id_ex_mem_re;
reg        id_ex_is_branch;
reg        id_ex_is_jal;
reg        id_ex_is_jalr;
reg        id_ex_is_load;
reg        id_ex_is_store;
reg [2:0]  id_ex_load_funct3;
reg [2:0]  id_ex_store_funct3;
reg [31:0] id_ex_inst;

assign stall = id_ex_valid && id_ex_is_load && (id_ex_rd != 5'd0) &&
               (((id_ex_rd == id_rs1) && id_use_rs1) ||
                ((id_ex_rd == id_rs2) && id_use_rs2));

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        id_ex_valid        <= 1'b0;
        id_ex_rs1_idx      <= 5'b0;
        id_ex_rs2_idx      <= 5'b0;
        id_ex_rd           <= 5'b0;
        id_ex_pc           <= 32'b0;
        id_ex_pc4          <= 32'b0;
        id_ex_rs1_val      <= 32'b0;
        id_ex_rs2_val      <= 32'b0;
        id_ex_i_imm        <= 32'b0;
        id_ex_s_imm        <= 32'b0;
        id_ex_u_imm        <= 32'b0;
        id_ex_branch_imm   <= 32'b0;
        id_ex_funct3       <= 3'b0;
        id_ex_alu_sel      <= ALU_ADD;
        id_ex_src1_sel     <= 2'b0;
        id_ex_src2_sel     <= 3'b0;
        id_ex_wb_sel       <= 2'b0;
        id_ex_reg_we       <= 1'b0;
        id_ex_mem_we       <= 1'b0;
        id_ex_mem_re       <= 1'b0;
        id_ex_is_branch    <= 1'b0;
        id_ex_is_jal       <= 1'b0;
        id_ex_is_jalr      <= 1'b0;
        id_ex_is_load      <= 1'b0;
        id_ex_is_store     <= 1'b0;
        id_ex_load_funct3  <= 3'b0;
        id_ex_store_funct3 <= 3'b0;
        id_ex_inst         <= 32'h0000_0013;
    end else if (flush) begin
        id_ex_valid        <= 1'b0;
        id_ex_rs1_idx      <= 5'b0;
        id_ex_rs2_idx      <= 5'b0;
        id_ex_rd           <= 5'b0;
        id_ex_pc           <= 32'b0;
        id_ex_pc4          <= 32'b0;
        id_ex_rs1_val      <= 32'b0;
        id_ex_rs2_val      <= 32'b0;
        id_ex_i_imm        <= 32'b0;
        id_ex_s_imm        <= 32'b0;
        id_ex_u_imm        <= 32'b0;
        id_ex_branch_imm   <= 32'b0;
        id_ex_funct3       <= 3'b0;
        id_ex_alu_sel      <= ALU_ADD;
        id_ex_src1_sel     <= 2'b0;
        id_ex_src2_sel     <= 3'b0;
        id_ex_wb_sel       <= 2'b0;
        id_ex_reg_we       <= 1'b0;
        id_ex_mem_we       <= 1'b0;
        id_ex_mem_re       <= 1'b0;
        id_ex_is_branch    <= 1'b0;
        id_ex_is_jal       <= 1'b0;
        id_ex_is_jalr      <= 1'b0;
        id_ex_is_load      <= 1'b0;
        id_ex_is_store     <= 1'b0;
        id_ex_load_funct3  <= 3'b0;
        id_ex_store_funct3 <= 3'b0;
        id_ex_inst         <= 32'h0000_0013;
    end else if (stall) begin
        id_ex_valid        <= 1'b0;
        id_ex_rs1_idx      <= 5'b0;
        id_ex_rs2_idx      <= 5'b0;
        id_ex_rd           <= 5'b0;
        id_ex_pc           <= 32'b0;
        id_ex_pc4          <= 32'b0;
        id_ex_rs1_val      <= 32'b0;
        id_ex_rs2_val      <= 32'b0;
        id_ex_i_imm        <= 32'b0;
        id_ex_s_imm        <= 32'b0;
        id_ex_u_imm        <= 32'b0;
        id_ex_branch_imm   <= 32'b0;
        id_ex_funct3       <= 3'b0;
        id_ex_alu_sel      <= ALU_ADD;
        id_ex_src1_sel     <= 2'b0;
        id_ex_src2_sel     <= 3'b0;
        id_ex_wb_sel       <= 2'b0;
        id_ex_reg_we       <= 1'b0;
        id_ex_mem_we       <= 1'b0;
        id_ex_mem_re       <= 1'b0;
        id_ex_is_branch    <= 1'b0;
        id_ex_is_jal       <= 1'b0;
        id_ex_is_jalr      <= 1'b0;
        id_ex_is_load      <= 1'b0;
        id_ex_is_store     <= 1'b0;
        id_ex_load_funct3  <= 3'b0;
        id_ex_store_funct3 <= 3'b0;
        id_ex_inst         <= 32'h0000_0013;
    end else begin
        id_ex_valid        <= id_valid_inst;
        id_ex_rs1_idx      <= id_rs1;
        id_ex_rs2_idx      <= id_rs2;
        id_ex_rd           <= id_rd;
        id_ex_pc           <= id_pc;
        id_ex_pc4          <= id_pc4;
        id_ex_rs1_val      <= id_rs1_data;
        id_ex_rs2_val      <= id_rs2_data;
        id_ex_i_imm        <= id_i_imm;
        id_ex_s_imm        <= id_s_imm;
        id_ex_u_imm        <= id_u_imm;
        id_ex_branch_imm   <= id_branch_imm;
        id_ex_funct3       <= id_funct3;
        id_ex_alu_sel      <= id_alu_sel;
        id_ex_src1_sel     <= id_src1_sel;
        id_ex_src2_sel     <= id_src2_sel;
        id_ex_wb_sel       <= id_wb_sel;
        id_ex_reg_we       <= id_reg_we;
        id_ex_mem_we       <= id_mem_we;
        id_ex_mem_re       <= id_mem_re;
        id_ex_is_branch    <= id_is_branch;
        id_ex_is_jal       <= id_is_jal;
        id_ex_is_jalr      <= id_is_jalr;
        id_ex_is_load      <= id_is_load;
        id_ex_is_store     <= id_is_store;
        id_ex_load_funct3  <= id_load_funct3;
        id_ex_store_funct3 <= id_store_funct3;
        id_ex_inst         <= id_inst;
    end
end

// ------------------------- EX ------------------------- //
reg        ex_mem_valid;
reg [4:0]  ex_mem_rd;
reg [31:0] ex_mem_alu_result;
reg [31:0] ex_mem_rs2_forwarded;
reg [31:0] ex_mem_pc4;
reg [1:0]  ex_mem_wb_sel;
reg        ex_mem_reg_we;
reg        ex_mem_mem_we;
reg        ex_mem_mem_re;
reg [2:0]  ex_mem_load_funct3;
reg [2:0]  ex_mem_store_funct3;
reg [31:0] ex_mem_inst;

wire [31:0] ex_forward_rs1;
wire [31:0] ex_forward_rs2;
reg  [31:0] ex_src1;
reg  [31:0] ex_src2;
reg  [31:0] ex_alu_result;
reg         ex_cmp_taken;

assign wb_data = (mem_wb_wb_sel == 2'd1) ? mem_wb_mem_data :
                 (mem_wb_wb_sel == 2'd2) ? mem_wb_pc4 :
                                            mem_wb_alu_result;

assign ex_forward_rs1 =
    (ex_mem_valid && ex_mem_reg_we && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs1_idx) && !ex_mem_mem_re) ?
        ((ex_mem_wb_sel == 2'd2) ? ex_mem_pc4 : ex_mem_alu_result) :
    (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs1_idx)) ?
        wb_data :
        id_ex_rs1_val;

assign ex_forward_rs2 =
    (ex_mem_valid && ex_mem_reg_we && (ex_mem_rd != 5'd0) && (ex_mem_rd == id_ex_rs2_idx) && !ex_mem_mem_re) ?
        ((ex_mem_wb_sel == 2'd2) ? ex_mem_pc4 : ex_mem_alu_result) :
    (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd != 5'd0) && (mem_wb_rd == id_ex_rs2_idx)) ?
        wb_data :
        id_ex_rs2_val;

always @(*) begin
    case (id_ex_src1_sel)
        2'd0: ex_src1 = ex_forward_rs1;
        2'd1: ex_src1 = id_ex_pc;
        2'd2: ex_src1 = 32'b0;
        default: ex_src1 = ex_forward_rs1;
    endcase
end

always @(*) begin
    case (id_ex_src2_sel)
        3'd0: ex_src2 = ex_forward_rs2;
        3'd1: ex_src2 = id_ex_i_imm;
        3'd2: ex_src2 = id_ex_s_imm;
        3'd3: ex_src2 = id_ex_u_imm;
        3'd4: ex_src2 = 32'd4;
        default: ex_src2 = ex_forward_rs2;
    endcase
end

always @(*) begin
    case (id_ex_alu_sel)
        ALU_ADD:  ex_alu_result = ex_src1 + ex_src2;
        ALU_SUB:  ex_alu_result = ex_src1 - ex_src2;
        ALU_SLL:  ex_alu_result = ex_src1 << ex_src2[4:0];
        ALU_SLT:  ex_alu_result = ($signed(ex_src1) < $signed(ex_src2)) ? 32'd1 : 32'd0;
        ALU_SLTU: ex_alu_result = (ex_src1 < ex_src2) ? 32'd1 : 32'd0;
        ALU_XOR:  ex_alu_result = ex_src1 ^ ex_src2;
        ALU_SRL:  ex_alu_result = ex_src1 >> ex_src2[4:0];
        ALU_SRA:  ex_alu_result = $signed(ex_src1) >>> ex_src2[4:0];
        ALU_OR:   ex_alu_result = ex_src1 | ex_src2;
        ALU_AND:  ex_alu_result = ex_src1 & ex_src2;
        ALU_PASS: ex_alu_result = ex_src2;
        default:  ex_alu_result = 32'b0;
    endcase
end

always @(*) begin
    case (id_ex_funct3)
        3'b000: ex_cmp_taken = (ex_forward_rs1 == ex_forward_rs2);
        3'b001: ex_cmp_taken = (ex_forward_rs1 != ex_forward_rs2);
        3'b100: ex_cmp_taken = ($signed(ex_forward_rs1) <  $signed(ex_forward_rs2));
        3'b101: ex_cmp_taken = ($signed(ex_forward_rs1) >= $signed(ex_forward_rs2));
        3'b110: ex_cmp_taken = (ex_forward_rs1 <  ex_forward_rs2);
        3'b111: ex_cmp_taken = (ex_forward_rs1 >= ex_forward_rs2);
        default: ex_cmp_taken = 1'b0;
    endcase
end

assign ex_branch_taken  = id_ex_valid && (id_ex_is_jal || id_ex_is_jalr || (id_ex_is_branch && ex_cmp_taken));
assign ex_branch_target = id_ex_is_jalr ? ((ex_forward_rs1 + id_ex_i_imm) & 32'hffff_fffe) :
                                         (id_ex_pc + id_ex_branch_imm);

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        ex_mem_valid         <= 1'b0;
        ex_mem_rd            <= 5'b0;
        ex_mem_alu_result    <= 32'b0;
        ex_mem_rs2_forwarded <= 32'b0;
        ex_mem_pc4           <= 32'b0;
        ex_mem_wb_sel        <= 2'b0;
        ex_mem_reg_we        <= 1'b0;
        ex_mem_mem_we        <= 1'b0;
        ex_mem_mem_re        <= 1'b0;
        ex_mem_load_funct3   <= 3'b0;
        ex_mem_store_funct3  <= 3'b0;
        ex_mem_inst          <= 32'h0000_0013;
    end else begin
        ex_mem_valid         <= id_ex_valid;
        ex_mem_rd            <= id_ex_rd;
        ex_mem_alu_result    <= ex_alu_result;
        ex_mem_rs2_forwarded <= ex_forward_rs2;
        ex_mem_pc4           <= id_ex_pc4;
        ex_mem_wb_sel        <= id_ex_wb_sel;
        ex_mem_reg_we        <= id_ex_reg_we;
        ex_mem_mem_we        <= id_ex_mem_we;
        ex_mem_mem_re        <= id_ex_mem_re;
        ex_mem_load_funct3   <= id_ex_load_funct3;
        ex_mem_store_funct3  <= id_ex_store_funct3;
        ex_mem_inst          <= id_ex_inst;
    end
end

// ------------------------- MEM ------------------------- //
wire [31:0] mem_load_data;
assign perip_addr  = ex_mem_alu_result;
assign perip_wen   = ex_mem_valid && ex_mem_mem_we;
assign perip_wdata = ex_mem_rs2_forwarded;
assign mem_load_data = load_ext(ex_mem_load_funct3, perip_rdata);

always @(*) begin
    if (ex_mem_mem_we && (ex_mem_store_funct3 == 3'b000))
        perip_mask = 2'b00; // byte
    else if (ex_mem_mem_we && (ex_mem_store_funct3 == 3'b001))
        perip_mask = 2'b01; // half
    else if (ex_mem_mem_we && (ex_mem_store_funct3 == 3'b010))
        perip_mask = 2'b10; // word
    else if (ex_mem_mem_re && ((ex_mem_load_funct3 == 3'b000) || (ex_mem_load_funct3 == 3'b100)))
        perip_mask = 2'b00;
    else if (ex_mem_mem_re && ((ex_mem_load_funct3 == 3'b001) || (ex_mem_load_funct3 == 3'b101)))
        perip_mask = 2'b01;
    else if (ex_mem_mem_re && (ex_mem_load_funct3 == 3'b010))
        perip_mask = 2'b10;
    else
        perip_mask = 2'b00;
end

always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        mem_wb_valid      <= 1'b0;
        mem_wb_rd         <= 5'b0;
        mem_wb_alu_result <= 32'b0;
        mem_wb_mem_data   <= 32'b0;
        mem_wb_pc4        <= 32'b0;
        mem_wb_wb_sel     <= 2'b0;
        mem_wb_reg_we     <= 1'b0;
        mem_wb_inst       <= 32'h0000_0013;
    end else begin
        mem_wb_valid      <= ex_mem_valid;
        mem_wb_rd         <= ex_mem_rd;
        mem_wb_alu_result <= ex_mem_alu_result;
        mem_wb_mem_data   <= mem_load_data;
        mem_wb_pc4        <= ex_mem_pc4;
        mem_wb_wb_sel     <= ex_mem_wb_sel;
        mem_wb_reg_we     <= ex_mem_reg_we;
        mem_wb_inst       <= ex_mem_inst;
    end
end

// ------------------------- WB ------------------------- //
always @(posedge cpu_clk or posedge cpu_rst) begin
    if (cpu_rst) begin
        for (i = 0; i < 32; i = i + 1)
            reg_file[i] <= 32'b0;
    end else begin
        if (mem_wb_valid && mem_wb_reg_we && (mem_wb_rd != 5'd0))
            reg_file[mem_wb_rd] <= wb_data;
    end
end

endmodule
