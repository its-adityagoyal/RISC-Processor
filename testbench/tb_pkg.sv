// =============================================================================
// tb_pkg -- verification package for the MiniRISC processors
//
//   * ISA constants and instruction encoders
//   * IsaModel : golden reference model (instruction-accurate ISS)
//   * Program builders : directed ISA tests, hazard tests, benchmarks and a
//     constrained-random program generator
//
// The reference model is written from the ISA definition (ISA_MiniRISC report
// + course appendix), NOT from the RTL, so the two can disagree when the RTL
// is wrong. Documented ISA decisions:
//   - every 16-bit immediate is sign-extended, including ANDI/ORI/XORI/NORI
//     (the course appendix says zero-extend; the team chose sign-extend)
//   - R-type shifts use the 5-bit shamt field; I-type shifts use imm[4:0]
//   - BR is absolute (PC <- sext(imm26)); BMI/BPL/BZ are PC-relative
//   - BPL is "strictly positive" (rs > 0)
//   - SLT/SGT/CMOV compare signed
//   - R0 is an ordinary register (not hard-wired to zero)
//   - data/instruction memories are 256 words, addressed by bits [7:0]
// =============================================================================
package tb_pkg;

  // ---------------------------------------------------------------- opcodes
  localparam bit [5:0] OP_R    = 6'b000000;
  localparam bit [5:0] OP_ADDI = 6'b001000;
  localparam bit [5:0] OP_SUBI = 6'b001001;
  localparam bit [5:0] OP_ANDI = 6'b010000;
  localparam bit [5:0] OP_ORI  = 6'b010001;
  localparam bit [5:0] OP_XORI = 6'b010010;
  localparam bit [5:0] OP_NORI = 6'b010011;
  localparam bit [5:0] OP_SLAI = 6'b011000;
  localparam bit [5:0] OP_SRLI = 6'b011001;
  localparam bit [5:0] OP_SRAI = 6'b011010;
  localparam bit [5:0] OP_LUI  = 6'b100001;
  localparam bit [5:0] OP_LD   = 6'b101010;
  localparam bit [5:0] OP_ST   = 6'b101011;
  localparam bit [5:0] OP_BR   = 6'b110000;
  localparam bit [5:0] OP_BMI  = 6'b110001;
  localparam bit [5:0] OP_BPL  = 6'b110010;
  localparam bit [5:0] OP_BZ   = 6'b110011;
  localparam bit [5:0] OP_HALT = 6'b111000;
  localparam bit [5:0] OP_NOP  = 6'b111001;

  // ------------------------------------------------------- R-type funct codes
  localparam bit [5:0] F_ADD  = 6'b001000;
  localparam bit [5:0] F_SUB  = 6'b001001;
  localparam bit [5:0] F_INC  = 6'b001010;
  localparam bit [5:0] F_DEC  = 6'b001011;
  localparam bit [5:0] F_SLT  = 6'b001100;
  localparam bit [5:0] F_SGT  = 6'b001101;
  localparam bit [5:0] F_AND  = 6'b010000;
  localparam bit [5:0] F_OR   = 6'b010001;
  localparam bit [5:0] F_XOR  = 6'b010010;
  localparam bit [5:0] F_NOR  = 6'b010011;
  localparam bit [5:0] F_NOT  = 6'b010100;
  localparam bit [5:0] F_SL   = 6'b011000;
  localparam bit [5:0] F_SRL  = 6'b011001;
  localparam bit [5:0] F_SRA  = 6'b011010;
  localparam bit [5:0] F_HAM  = 6'b100000;
  localparam bit [5:0] F_MOVE = 6'b101000;
  localparam bit [5:0] F_CMOV = 6'b101001;

  localparam bit [31:0] HALT_I = {OP_HALT, 26'd0};
  localparam bit [31:0] NOP_I  = {OP_NOP,  26'd0};

  localparam int MEM_WORDS = 256;

  // ------------------------------------------------------------- encoders
  // Arguments follow the field order: opcode/funct, rs, rt, then rd or imm.
  // Explicit part-selects: xsim 2025.2 was observed not to truncate wider
  // actuals to the formal's width inside a concatenation.
  function automatic bit [31:0] encR(bit [5:0] funct, bit [3:0] rs, bit [3:0] rt,
                                     bit [3:0] rd, bit [4:0] shamt = 5'd0);
    bit [31:0] w;
    w[31:26] = OP_R;
    w[25:22] = rs[3:0];
    w[21:18] = rt[3:0];
    w[17:14] = rd[3:0];
    w[13:9]  = shamt[4:0];
    w[8:3]   = funct[5:0];
    w[2:0]   = 3'b000;
    return w;
  endfunction

  function automatic bit [31:0] encI(bit [5:0] op, bit [3:0] rs, bit [3:0] rt, bit [15:0] imm);
    bit [31:0] w;
    w[31:26] = op[5:0];
    w[25:22] = rs[3:0];
    w[21:18] = rt[3:0];
    w[17:2]  = imm[15:0];
    w[1:0]   = 2'b00;
    return w;
  endfunction

  function automatic bit [31:0] encJ(bit [5:0] op, bit [25:0] imm26);
    bit [31:0] w;
    w[31:26] = op[5:0];
    w[25:0]  = imm26[25:0];
    return w;
  endfunction

  // ---------------------------------------------------------- commit record
  typedef struct packed {
    bit [31:0] pc;
    bit [31:0] insn;
    bit        rd_we;
    bit [3:0]  rd;
    bit [31:0] rd_wdata;
    bit        mem_we;
    bit [7:0]  mem_addr;
    bit [31:0] mem_wdata;
  } commit_t;

  // Known-answer check attached to a directed test (independent of the model,
  // so it also guards against a wrong reference model).
  typedef struct {
    bit        is_mem;
    bit [7:0]  idx;
    bit [31:0] value;
    string     name;
  } kat_t;

  // ------------------------------------------------------------ mnemonics
  function automatic string mnemonic(bit [31:0] in);
    bit [5:0] op = in[31:26];
    bit [5:0] fn = in[8:3];
    if (op == OP_R) begin
      case (fn)
        F_ADD: return "ADD";   F_SUB: return "SUB";   F_INC: return "INC";
        F_DEC: return "DEC";   F_SLT: return "SLT";   F_SGT: return "SGT";
        F_AND: return "AND";   F_OR:  return "OR";    F_XOR: return "XOR";
        F_NOR: return "NOR";   F_NOT: return "NOT";   F_SL:  return "SL";
        F_SRL: return "SRL";   F_SRA: return "SRA";   F_HAM: return "HAM";
        F_MOVE: return "MOVE"; F_CMOV: return "CMOV";
        default: return "R-UNDEF";
      endcase
    end
    case (op)
      OP_ADDI: return "ADDI"; OP_SUBI: return "SUBI"; OP_ANDI: return "ANDI";
      OP_ORI:  return "ORI";  OP_XORI: return "XORI"; OP_NORI: return "NORI";
      OP_SLAI: return "SLAI"; OP_SRLI: return "SRLI"; OP_SRAI: return "SRAI";
      OP_LUI:  return "LUI";  OP_LD:   return "LD";   OP_ST:   return "ST";
      OP_BR:   return "BR";   OP_BMI:  return "BMI";  OP_BPL:  return "BPL";
      OP_BZ:   return "BZ";   OP_HALT: return "HALT"; OP_NOP:  return "NOP";
      default: return "UNDEF";
    endcase
  endfunction

  function automatic bit is_branch(bit [31:0] in);
    return in[31:26] inside {OP_BR, OP_BMI, OP_BPL, OP_BZ};
  endfunction

  // =========================================================================
  // IsaModel -- golden reference: executes one instruction per step()
  // =========================================================================
  class IsaModel;
    bit [31:0] imem [MEM_WORDS];
    bit [31:0] dmem [MEM_WORDS];
    bit [31:0] regs [16];
    bit [31:0] pc;
    bit        halted;
    bit        last_taken;   // control-flow outcome of the last step (stats)

    function void reset();
      foreach (regs[i]) regs[i] = '0;
      pc = '0;
      halted = 1'b0;
    endfunction

    function commit_t step();
      commit_t   c;
      bit [31:0] in    = imem[pc[7:0]];
      bit [5:0]  op    = in[31:26];
      bit [3:0]  rs    = in[25:22];
      bit [3:0]  rt    = in[21:18];
      bit [3:0]  rd    = in[17:14];
      bit [4:0]  sh    = in[13:9];
      bit [5:0]  fn    = in[8:3];
      bit [31:0] imm   = {{16{in[17]}}, in[17:2]};
      bit [31:0] imm26 = {{6{in[25]}}, in[25:0]};
      bit [31:0] a     = regs[rs];
      bit [31:0] b     = regs[rt];
      bit [31:0] npc   = pc + 1;
      bit [31:0] ea    = a + imm;

      c = '0;
      c.pc   = pc;
      c.insn = in;
      last_taken = 1'b0;

      case (op)
        OP_R: begin
          c.rd_we = 1'b1;
          c.rd    = rd;
          case (fn)
            F_ADD:  c.rd_wdata = a + b;
            F_SUB:  c.rd_wdata = a - b;
            F_INC:  c.rd_wdata = a + 1;
            F_DEC:  c.rd_wdata = a - 1;
            F_SLT:  c.rd_wdata = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
            F_SGT:  c.rd_wdata = ($signed(a) > $signed(b)) ? 32'd1 : 32'd0;
            F_AND:  c.rd_wdata = a & b;
            F_OR:   c.rd_wdata = a | b;
            F_XOR:  c.rd_wdata = a ^ b;
            F_NOR:  c.rd_wdata = ~(a | b);
            F_NOT:  c.rd_wdata = ~a;
            F_SL:   c.rd_wdata = a << sh;
            F_SRL:  c.rd_wdata = a >> sh;
            F_SRA:  c.rd_wdata = $signed(a) >>> sh;
            F_HAM:  c.rd_wdata = $countones(a);
            F_MOVE: c.rd_wdata = a;
            F_CMOV: c.rd_wdata = ($signed(a) < $signed(b)) ? a : b;
            default: $fatal(1, "[ISA] undefined R-type funct %b at pc %0d", fn, pc);
          endcase
        end
        OP_ADDI, OP_SUBI, OP_ANDI, OP_ORI, OP_XORI, OP_NORI,
        OP_SLAI, OP_SRLI, OP_SRAI, OP_LUI: begin
          c.rd_we = 1'b1;
          c.rd    = rt;
          case (op)
            OP_ADDI: c.rd_wdata = a + imm;
            OP_SUBI: c.rd_wdata = a - imm;
            OP_ANDI: c.rd_wdata = a & imm;
            OP_ORI:  c.rd_wdata = a | imm;
            OP_XORI: c.rd_wdata = a ^ imm;
            OP_NORI: c.rd_wdata = ~(a | imm);
            OP_SLAI: c.rd_wdata = a << imm[4:0];
            OP_SRLI: c.rd_wdata = a >> imm[4:0];
            OP_SRAI: c.rd_wdata = $signed(a) >>> imm[4:0];
            OP_LUI:  c.rd_wdata = {in[17:2], 16'h0000};
          endcase
        end
        OP_LD: begin
          c.rd_we    = 1'b1;
          c.rd       = rt;
          c.rd_wdata = dmem[ea[7:0]];
        end
        OP_ST: begin
          c.mem_we    = 1'b1;
          c.mem_addr  = ea[7:0];
          c.mem_wdata = b;
          dmem[ea[7:0]] = b;
        end
        OP_BR:  begin npc = imm26; last_taken = 1'b1; end
        OP_BMI: if ($signed(a) <  0) begin npc = pc + imm; last_taken = 1'b1; end
        OP_BPL: if ($signed(a) >  0) begin npc = pc + imm; last_taken = 1'b1; end
        OP_BZ:  if (a == 32'd0)      begin npc = pc + imm; last_taken = 1'b1; end
        OP_HALT: begin halted = 1'b1; npc = pc; end
        OP_NOP: ;
        default: $fatal(1, "[ISA] undefined opcode %b at pc %0d", op, pc);
      endcase

      if (c.rd_we) regs[c.rd] = c.rd_wdata;
      pc = npc;
      return c;
    endfunction
  endclass

  // =========================================================================
  // Deterministic PRNG (xorshift32) -- identical streams on every simulator
  // =========================================================================
  class Rng;
    bit [31:0] s;
    function new(int unsigned seed);
      s = (seed == 0) ? 32'h1234_5678 : seed;
      repeat (4) void'(next());
    endfunction
    function bit [31:0] next();
      s ^= s << 13;
      s ^= s >> 17;
      s ^= s << 5;
      return s;
    endfunction
    // uniform integer in [lo, hi]
    function int range(int lo, int hi);
      return lo + int'(next() % (hi - lo + 1));
    endfunction
    function bit chance(int percent);
      return range(0, 99) < percent;
    endfunction
  endclass

  // =========================================================================
  // Program image handed from the builders to the testbench
  // =========================================================================
  class Program;
    string     name;
    bit [31:0] imem [MEM_WORDS];
    bit [31:0] dmem [MEM_WORDS];
    int        len;          // instructions up to and including HALT
    kat_t      kats [$];

    function new(string n);
      name = n;
      foreach (imem[i]) imem[i] = HALT_I;
      foreach (dmem[i]) dmem[i] = '0;
      len = 0;
    endfunction

    function void emit(bit [31:0] in);
      imem[len] = in;
      len++;
    endfunction

    function void kat_reg(int r, bit [31:0] v, string n);
      kat_t k; k.is_mem = 0; k.idx = r; k.value = v; k.name = n; kats.push_back(k);
    endfunction

    function void kat_mem(int a, bit [31:0] v, string n);
      kat_t k; k.is_mem = 1; k.idx = a; k.value = v; k.name = n; kats.push_back(k);
    endfunction
  endclass

  // =========================================================================
  // Directed ISA tests -- ported from the team's 15-phase single-cycle bench
  // =========================================================================
  function automatic Program build_isa(int phase);
    Program p = new($sformatf("isa_p%0d", phase));
    case (phase)
      1: begin // arithmetic
        p.emit(encI(OP_ADDI, 0, 1, 16'd10));
        p.emit(encI(OP_ADDI, 0, 2, 16'd3));
        p.emit(encR(F_ADD, 1, 2, 3));
        p.emit(encR(F_SUB, 1, 2, 4));
        p.emit(encR(F_INC, 1, 0, 5));
        p.emit(encR(F_DEC, 2, 0, 6));
        p.emit(encI(OP_SUBI, 1, 7, 16'd4));
        p.emit(encR(F_SLT, 1, 2, 8));
        p.emit(encR(F_SLT, 2, 1, 9));
        p.emit(encR(F_SGT, 1, 2, 10));
        p.emit(HALT_I);
        p.kat_reg(1, 10, "ADDI"); p.kat_reg(2, 3, "ADDI");  p.kat_reg(3, 13, "ADD");
        p.kat_reg(4, 7, "SUB");   p.kat_reg(5, 11, "INC");  p.kat_reg(6, 2, "DEC");
        p.kat_reg(7, 6, "SUBI");  p.kat_reg(8, 0, "SLT 10<3"); p.kat_reg(9, 1, "SLT 3<10");
        p.kat_reg(10, 1, "SGT 10>3");
      end
      2: begin // logic
        p.emit(encI(OP_ADDI, 0, 1, 16'h00F0));
        p.emit(encI(OP_ADDI, 0, 2, 16'h000F));
        p.emit(encR(F_AND, 1, 2, 3));
        p.emit(encR(F_OR,  1, 2, 4));
        p.emit(encR(F_XOR, 1, 2, 5));
        p.emit(encR(F_NOR, 1, 2, 6));
        p.emit(encR(F_NOT, 1, 0, 7));
        p.emit(encI(OP_ANDI, 1, 8,  16'h00FF));
        p.emit(encI(OP_ORI,  1, 9,  16'h000F));
        p.emit(encI(OP_XORI, 1, 10, 16'h00FF));
        p.emit(encI(OP_NORI, 1, 11, 16'h000F));
        p.emit(HALT_I);
        p.kat_reg(3, 32'h0, "AND");          p.kat_reg(4, 32'hFF, "OR");
        p.kat_reg(5, 32'hFF, "XOR");         p.kat_reg(6, 32'hFFFF_FF00, "NOR");
        p.kat_reg(7, 32'hFFFF_FF0F, "NOT");  p.kat_reg(8, 32'hF0, "ANDI");
        p.kat_reg(9, 32'hFF, "ORI");         p.kat_reg(10, 32'h0F, "XORI");
        p.kat_reg(11, 32'hFFFF_FF00, "NORI");
      end
      3: begin // shifts
        p.emit(encI(OP_ADDI, 0, 1, 16'd16));
        p.emit(encR(F_SL,  1, 0, 3, 5'd2));
        p.emit(encR(F_SRL, 1, 0, 4, 5'd1));
        p.emit(encI(OP_SLAI, 1, 5, 16'd3));
        p.emit(encI(OP_SRLI, 1, 6, 16'd2));
        p.emit(encI(OP_ADDI, 0, 7, 16'hFFFF));
        p.emit(encR(F_SRA, 7, 0, 8, 5'd4));
        p.emit(encI(OP_SRAI, 7, 9, 16'd8));
        p.emit(HALT_I);
        p.kat_reg(3, 64, "SL 16<<2");   p.kat_reg(4, 8, "SRL 16>>1");
        p.kat_reg(5, 128, "SLAI 16<<3"); p.kat_reg(6, 4, "SRLI 16>>2");
        p.kat_reg(8, 32'hFFFF_FFFF, "SRA -1>>>4"); p.kat_reg(9, 32'hFFFF_FFFF, "SRAI -1>>>8");
      end
      4: begin // LUI
        p.emit(encI(OP_LUI, 0, 1, 16'h00AB));
        p.emit(HALT_I);
        p.kat_reg(1, 32'h00AB_0000, "LUI");
      end
      5: begin // load / store
        p.emit(encI(OP_ADDI, 0, 1, 16'd42));
        p.emit(encI(OP_ST,   0, 1, 16'd20));
        p.emit(encI(OP_LD,   0, 2, 16'd20));
        p.emit(encI(OP_ADDI, 0, 3, 16'd99));
        p.emit(encI(OP_ST,   0, 3, 16'd50));
        p.emit(encI(OP_LD,   0, 4, 16'd50));
        p.emit(HALT_I);
        p.kat_reg(2, 42, "LD MEM[20]"); p.kat_reg(4, 99, "LD MEM[50]");
        p.kat_mem(20, 42, "ST MEM[20]"); p.kat_mem(50, 99, "ST MEM[50]");
      end
      6: begin // BZ taken
        p.emit(encI(OP_ADDI, 0, 1, 16'd0));
        p.emit(encI(OP_BZ,   1, 0, 16'd2));
        p.emit(encI(OP_ADDI, 0, 2, 16'd99));
        p.emit(encI(OP_ADDI, 0, 3, 16'd77));
        p.emit(HALT_I);
        p.kat_reg(2, 0, "BZ taken: skipped"); p.kat_reg(3, 77, "BZ taken: target");
      end
      7: begin // BZ not taken
        p.emit(encI(OP_ADDI, 0, 1, 16'd5));
        p.emit(encI(OP_BZ,   1, 0, 16'd2));
        p.emit(encI(OP_ADDI, 0, 2, 16'd55));
        p.emit(encI(OP_ADDI, 0, 3, 16'd77));
        p.emit(HALT_I);
        p.kat_reg(2, 55, "BZ not taken: fall-through"); p.kat_reg(3, 77, "BZ not taken");
      end
      8: begin // BMI taken
        p.emit(encI(OP_ADDI, 0, 1, 16'hFFFF));
        p.emit(encI(OP_BMI,  1, 0, 16'd2));
        p.emit(encI(OP_ADDI, 0, 2, 16'd55));
        p.emit(encI(OP_ADDI, 0, 3, 16'd33));
        p.emit(HALT_I);
        p.kat_reg(2, 0, "BMI taken: skipped"); p.kat_reg(3, 33, "BMI taken: target");
      end
      9: begin // BMI not taken
        p.emit(encI(OP_ADDI, 0, 1, 16'd16));
        p.emit(encI(OP_BMI,  1, 0, 16'd2));
        p.emit(encI(OP_ADDI, 0, 2, 16'd88));
        p.emit(HALT_I);
        p.kat_reg(2, 88, "BMI not taken: fall-through");
      end
      10: begin // BPL taken
        p.emit(encI(OP_ADDI, 0, 1, 16'd5));
        p.emit(encI(OP_BPL,  1, 0, 16'd2));
        p.emit(encI(OP_ADDI, 0, 2, 16'd44));
        p.emit(encI(OP_ADDI, 0, 3, 16'd22));
        p.emit(HALT_I);
        p.kat_reg(2, 0, "BPL taken: skipped"); p.kat_reg(3, 22, "BPL taken: target");
      end
      11: begin // BR unconditional (absolute)
        p.emit(encJ(OP_BR, 26'd3));
        p.emit(encI(OP_ADDI, 0, 1, 16'd11));
        p.emit(encI(OP_ADDI, 0, 2, 16'd22));
        p.emit(encI(OP_ADDI, 0, 3, 16'd33));
        p.emit(HALT_I);
        p.kat_reg(1, 0, "BR: skipped"); p.kat_reg(2, 0, "BR: skipped");
        p.kat_reg(3, 33, "BR: target");
      end
      12: begin // MOVE / CMOV
        p.emit(encI(OP_ADDI, 0, 1, 16'd5));
        p.emit(encI(OP_ADDI, 0, 2, 16'd10));
        p.emit(encR(F_MOVE, 1, 0, 3));
        p.emit(encR(F_CMOV, 1, 2, 4));
        p.emit(encR(F_CMOV, 2, 1, 5));
        p.emit(HALT_I);
        p.kat_reg(3, 5, "MOVE"); p.kat_reg(4, 5, "CMOV min(5,10)"); p.kat_reg(5, 5, "CMOV min(10,5)");
      end
      13: begin // NOP
        p.emit(encI(OP_ADDI, 0, 1, 16'd7));
        p.emit(NOP_I); p.emit(NOP_I); p.emit(NOP_I);
        p.emit(encI(OP_ADDI, 0, 2, 16'd7));
        p.emit(HALT_I);
        p.kat_reg(1, 7, "NOP: R1 unchanged"); p.kat_reg(2, 7, "NOP: R2 after NOPs");
      end
      14: begin // HALT must stop execution
        p.emit(encI(OP_ADDI, 0, 1, 16'd1));
        p.emit(HALT_I);
        p.len = 2;
        // Live instructions after HALT: none of these may take effect.
        p.imem[2] = encI(OP_ADDI, 0, 2, 16'd99);
        p.imem[3] = encI(OP_ADDI, 0, 3, 16'd98);
        p.imem[4] = encI(OP_ST,   0, 1, 16'd7);
        p.imem[5] = encI(OP_ADDI, 0, 4, 16'd97);
        p.kat_reg(1, 1, "HALT: R1 before halt"); p.kat_reg(2, 0, "HALT: R2 not written");
        p.kat_reg(3, 0, "HALT: R3 not written"); p.kat_reg(4, 0, "HALT: R4 not written");
        p.kat_mem(7, 0, "HALT: MEM[7] not written");
      end
      15: begin // end-to-end sum 1..5, store and reload
        for (int i = 1; i <= 5; i++) p.emit(encI(OP_ADDI, 0, i[3:0], i[15:0]));
        p.emit(encR(F_ADD, 1, 2, 6));
        p.emit(encR(F_ADD, 6, 3, 6));
        p.emit(encR(F_ADD, 6, 4, 6));
        p.emit(encR(F_ADD, 6, 5, 6));
        p.emit(encI(OP_ST, 0, 6, 16'd100));
        p.emit(encI(OP_LD, 0, 7, 16'd100));
        p.emit(HALT_I);
        p.kat_reg(6, 15, "SUM 1..5"); p.kat_reg(7, 15, "LD MEM[100]");
        p.kat_mem(100, 15, "ST MEM[100]");
      end
      16: begin // HAM + I-type shift amounts > 3
        p.emit(encI(OP_ADDI, 0, 1, 16'h00F7));      // 0xF7 has 7 ones
        p.emit(encR(F_HAM, 1, 0, 2));
        p.emit(encI(OP_LUI,  0, 3, 16'h8000));
        p.emit(encR(F_HAM, 3, 0, 4));                // 1
        p.emit(encI(OP_SRAI, 3, 5, 16'd31));          // 0xFFFFFFFF
        p.emit(encI(OP_SRLI, 3, 6, 16'd31));          // 1
        p.emit(encI(OP_SLAI, 1, 7, 16'd24));          // 0xF7000000
        p.emit(encR(F_SL,  1, 0, 8, 5'd28));          // 0x70000000
        p.emit(HALT_I);
        p.kat_reg(2, 7, "HAM 0xF7"); p.kat_reg(4, 1, "HAM 0x80000000");
        p.kat_reg(5, 32'hFFFF_FFFF, "SRAI 31"); p.kat_reg(6, 1, "SRLI 31");
        p.kat_reg(7, 32'hF700_0000, "SLAI 24"); p.kat_reg(8, 32'h7000_0000, "SL 28");
      end
      default: $fatal(1, "no ISA phase %0d", phase);
    endcase
    return p;
  endfunction

  // =========================================================================
  // Hazard test -- every forwarding / stall / flush path in the pipeline
  // =========================================================================
  function automatic Program build_hazards();
    Program p = new("hazards");
    p.emit(encI(OP_ADDI, 0, 1, 16'd5));        //  0 r1 = 5
    p.emit(encR(F_ADD, 1, 1, 2));              //  1 MEM->EX on rs and rt
    p.emit(encR(F_ADD, 2, 1, 3));              //  2 MEM->EX (r2) + WB->EX (r1)
    p.emit(encR(F_SUB, 3, 2, 4));              //  3 MEM->EX (r3) + WB->EX (r2)
    p.emit(NOP_I);                             //  4
    p.emit(encR(F_ADD, 4, 3, 5));              //  5 WB->EX (r4) + regfile (r3)
    p.emit(encI(OP_ST, 0, 5, 16'd10));         //  6 store
    p.emit(encI(OP_LD, 0, 6, 16'd10));         //  7 load same address
    p.emit(encR(F_ADD, 6, 6, 7));              //  8 load-use on rs and rt
    p.emit(encI(OP_LD, 0, 8, 16'd10));         //  9
    p.emit(encI(OP_ST, 0, 8, 16'd11));         // 10 load -> store data
    p.emit(encI(OP_LD, 0, 9, 16'd11));         // 11
    p.emit(encI(OP_BZ, 9, 0, 16'd2));          // 12 load -> branch (not taken)
    p.emit(encI(OP_ADDI, 10, 10, 16'd1));      // 13 executes
    p.emit(encR(F_SUB, 9, 9, 11));             // 14 r11 = 0
    p.emit(encI(OP_BZ, 11, 0, 16'd2));         // 15 branch on MEM-forwarded value (taken)
    p.emit(encI(OP_ADDI, 0, 12, 16'd99));      // 16 squashed
    p.emit(encJ(OP_BR, 26'd19));               // 17 jump
    p.emit(encI(OP_ADDI, 0, 12, 16'd98));      // 18 squashed
    p.emit(encI(OP_BMI, 1, 0, 16'd5));         // 19 not taken
    p.emit(encI(OP_BPL, 1, 0, 16'd2));         // 20 taken, back-to-back branch
    p.emit(encI(OP_ADDI, 0, 12, 16'd97));      // 21 squashed
    p.emit(encI(OP_ADDI, 0, 13, 16'hFFFF));    // 22 r13 = -1
    p.emit(encI(OP_BMI, 13, 0, 16'd2));        // 23 branch on MEM-forwarded negative (taken)
    p.emit(encI(OP_ADDI, 0, 12, 16'd96));      // 24 squashed
    p.emit(encR(F_ADD, 1, 1, 0));              // 25 write r0 (ordinary register)
    p.emit(encR(F_ADD, 0, 0, 14));             // 26 read r0 -> 20
    p.emit(encI(OP_ADDI, 0, 15, 16'd3));       // 27 r15 = r0 + 3 = 13 (r0 is 10 now)
    p.emit(encI(OP_ST, 15, 14, 16'hFFFF));     // 28 negative offset: MEM[12] = 20
    p.emit(encI(OP_LD, 15, 1, 16'hFFFF));      // 29 r1 = MEM[12]
    p.emit(encI(OP_BZ, 1, 0, 16'd3));          // 30 load -> branch (not taken)
    p.emit(encI(OP_LD, 0, 2, 16'd22));         // 31
    p.emit(encR(F_CMOV, 2, 13, 3));            // 32 load-use into CMOV -> -1
    p.emit(encR(F_MOVE, 3, 0, 4));             // 33 MEM->EX into MOVE
    p.emit(HALT_I);                            // 34
    p.imem[35] = encI(OP_ADDI, 0, 12, 16'd55); // must never execute
    p.imem[36] = encI(OP_ST,   0, 12, 16'd0);
    p.kat_reg(12, 0, "no squashed instruction retired");
    p.kat_reg(10, 1, "not-taken load->branch fall-through");
    p.kat_reg(0, 10, "R0 is writable");
    p.kat_reg(14, 20, "R0 read back");
    p.kat_reg(4, 32'hFFFF_FFFF, "load-use CMOV then MOVE");
    p.kat_mem(12, 20, "negative-offset store");
    return p;
  endfunction

  // =========================================================================
  // Benchmarks
  // =========================================================================
  // Bubble sort kernel (from the team's program). base = index of the first
  // kernel instruction; BR targets are absolute so they are offset by base.
  function automatic void emit_bubble_kernel(Program p, int n, int base);
    p.emit(encI(OP_ADDI, 0, 1, 16'd0));                 // i = 0
    p.emit(encI(OP_ADDI, 0, 2, 16'(n - 1)));            // n-1
    p.emit(encR(F_SLT, 1, 2, 9));                       // outer: i < n-1
    p.emit(encI(OP_BZ, 9, 0, 16'd16));                  //   -> done
    p.emit(encI(OP_ADDI, 0, 3, 16'd0));                 // j = 0
    p.emit(encR(F_SUB, 2, 1, 4));                       // n-1-i
    p.emit(encR(F_SLT, 3, 4, 9));                       // inner: j < n-1-i
    p.emit(encI(OP_BZ, 9, 0, 16'd10));                  //   -> next i
    p.emit(encI(OP_LD, 3, 6, 16'd0));                   // a[j]
    p.emit(encI(OP_ADDI, 3, 7, 16'd1));
    p.emit(encI(OP_LD, 7, 8, 16'd0));                   // a[j+1]
    p.emit(encR(F_SGT, 6, 8, 9));
    p.emit(encI(OP_BZ, 9, 0, 16'd3));                   //   no swap
    p.emit(encI(OP_ST, 3, 8, 16'd0));
    p.emit(encI(OP_ST, 7, 6, 16'd0));
    p.emit(encI(OP_ADDI, 3, 3, 16'd1));                 // j++
    p.emit(encJ(OP_BR, 26'(base + 6)));                 // -> inner
    p.emit(encI(OP_ADDI, 1, 1, 16'd1));                 // i++
    p.emit(encJ(OP_BR, 26'(base + 2)));                 // -> outer
    p.emit(HALT_I);
  endfunction

  function automatic void emit_insertion_kernel(Program p, int n, int base);
    p.emit(encI(OP_ADDI, 0, 1, 16'd1));                 // i = 1
    p.emit(encI(OP_ADDI, 0, 2, 16'(n)));
    p.emit(encI(OP_ADDI, 0, 8, 16'd1));                 // const 1
    p.emit(encI(OP_ADDI, 0, 9, 16'hFFFF));              // const -1
    p.emit(encR(F_SLT, 1, 2, 6));                       // outer: i < n
    p.emit(encI(OP_BZ, 6, 0, 16'd17));                  //   -> done
    p.emit(encI(OP_LD, 1, 4, 16'd0));                   // key = a[i]
    p.emit(encR(F_ADD, 1, 9, 3));                       // j = i-1
    p.emit(encR(F_SLT, 3, 0, 6));                       // inner: j < 0 ?
    p.emit(encR(F_SUB, 8, 6, 7));
    p.emit(encI(OP_BZ, 7, 0, 16'd8));                   //   -> insert
    p.emit(encI(OP_LD, 3, 5, 16'd0));                   // a[j]
    p.emit(encR(F_SGT, 5, 4, 6));
    p.emit(encI(OP_BZ, 6, 0, 16'd5));                   //   -> insert
    p.emit(encR(F_ADD, 3, 8, 7));
    p.emit(encI(OP_ST, 7, 5, 16'd0));                   // a[j+1] = a[j]
    p.emit(encR(F_ADD, 3, 9, 3));                       // j--
    p.emit(encJ(OP_BR, 26'(base + 8)));                 // -> inner
    p.emit(encR(F_ADD, 3, 8, 7));
    p.emit(encI(OP_ST, 7, 4, 16'd0));                   // a[j+1] = key
    p.emit(encR(F_ADD, 1, 8, 1));                       // i++
    p.emit(encJ(OP_BR, 26'(base + 4)));                 // -> outer
    p.emit(HALT_I);
  endfunction

  // Exact programs from the team's Bubble_Sort_TB / Insertion_Sort_TB.
  function automatic Program build_bubble_orig();
    Program p = new("bubble5");
    for (int i = 0; i < 5; i++) begin
      p.emit(encI(OP_ADDI, 0, 1, 16'(25 - 5 * i)));     // 25,20,15,10,5
      p.emit(encI(OP_ST,   0, 1, 16'(i)));
    end
    emit_bubble_kernel(p, 5, 10);
    for (int i = 0; i < 5; i++) p.kat_mem(i, 5 * (i + 1), "sorted");
    return p;
  endfunction

  function automatic Program build_insertion_orig();
    Program p = new("insertion10");
    for (int i = 0; i < 10; i++) begin
      p.emit(encI(OP_ADDI, 0, 1, 16'(100 - 10 * i)));   // 100,90,...,10
      p.emit(encI(OP_ST,   0, 1, 16'(i)));
    end
    emit_insertion_kernel(p, 10, 20);
    for (int i = 0; i < 10; i++) p.kat_mem(i, 10 * (i + 1), "sorted");
    return p;
  endfunction

  // =========================================================================
  // Constrained-random program generator
  //   - every defined instruction, biased towards back-to-back dependencies
  //   - forward branches only, plus counted loops on a reserved register,
  //     so every program provably terminates
  //   - live random instructions after HALT (must never take effect)
  // =========================================================================
  localparam int LOOP_REG = 14;   // reserved loop counter, never randomly written

  function automatic bit [3:0] pick_src(Rng r, ref bit [3:0] recent[$]);
    if (recent.size() > 0 && r.chance(60))
      return recent[r.range(0, recent.size() - 1)];
    return r.range(0, 15);
  endfunction

  function automatic bit [3:0] pick_dst(Rng r, ref bit [3:0] recent[$]);
    bit [3:0] d;
    do d = r.range(0, 15); while (d == LOOP_REG);
    recent.push_back(d);
    if (recent.size() > 3) void'(recent.pop_front());
    return d;
  endfunction

  function automatic bit [15:0] rand_imm16(Rng r);
    bit [31:0] v;
    case (r.range(0, 3))
      0: v = r.range(0, 15);                    // small
      1: v = r.range(-16, -1);                  // small negative
      2: v = r.next();                          // anything (exercises sign-extend)
      default: v = r.range(0, 255);
    endcase
    return v[15:0];
  endfunction

  // One random non-control instruction.
  function automatic bit [31:0] rand_alu_mem(Rng r, ref bit [3:0] recent[$]);
    bit [5:0] rfn[17] = '{F_ADD, F_SUB, F_INC, F_DEC, F_SLT, F_SGT, F_AND, F_OR,
                          F_XOR, F_NOR, F_NOT, F_SL, F_SRL, F_SRA, F_HAM, F_MOVE, F_CMOV};
    bit [5:0] iop[10] = '{OP_ADDI, OP_SUBI, OP_ANDI, OP_ORI, OP_XORI, OP_NORI,
                          OP_SLAI, OP_SRLI, OP_SRAI, OP_LUI};
    bit [3:0] s1 = pick_src(r, recent);
    bit [3:0] s2 = pick_src(r, recent);
    int k = r.range(0, 99);
    if (k < 40) begin
      return encR(rfn[r.range(0, 16)], s1, s2, pick_dst(r, recent), r.range(0, 31));
    end else if (k < 70) begin
      return encI(iop[r.range(0, 9)], s1, pick_dst(r, recent), rand_imm16(r));
    end else if (k < 85) begin
      // load: base often r0-relative small offsets so loads and stores alias
      return encI(OP_LD, s1, pick_dst(r, recent), r.chance(50) ? 16'(r.range(0, 15)) : rand_imm16(r));
    end else if (k < 97) begin
      return encI(OP_ST, s1, s2, r.chance(50) ? 16'(r.range(0, 15)) : rand_imm16(r));
    end
    return NOP_I;
  endfunction

  function automatic Program build_random(int unsigned seed, int target_len);
    Program p = new($sformatf("random_s%0d", seed));
    Rng r = new(seed);
    bit [3:0] recent[$];
    bit [5:0] bops[3] = '{OP_BMI, OP_BPL, OP_BZ};

    foreach (p.dmem[i]) p.dmem[i] = r.next();
    // seed registers with varied values (negatives, large, small)
    for (int i = 0; i < 14; i++) begin
      if (r.chance(50)) p.emit(encI(OP_LUI, 0, i[3:0], r.next()));
      p.emit(encI(OP_ADDI, i[3:0], i[3:0], rand_imm16(r)));
    end

    while (p.len < target_len) begin
      int room = target_len - p.len;   // instructions left before HALT
      int k = r.range(0, 99);
      if (k < 10 && room > 2) begin
        // forward conditional branch, target strictly inside the program
        int off = r.range(1, (room < 6) ? room : 6);
        p.emit(encI(bops[r.range(0, 2)], pick_src(r, recent), 0, 16'(off)));
      end else if (k < 13 && room > 2) begin
        // forward absolute jump
        int off = r.range(1, (room < 6) ? room : 6);
        p.emit(encJ(OP_BR, 26'(p.len + off)));
      end else if (k < 18 && room > 12) begin
        // counted loop: r14 = n; body; r14--; BPL r14 -> body
        int n = r.range(1, 6);
        int body = r.range(2, 6);
        int start;
        p.emit(encI(OP_ANDI, LOOP_REG, LOOP_REG, 16'd0));
        p.emit(encI(OP_ADDI, LOOP_REG, LOOP_REG, 16'(n)));
        start = p.len;
        for (int b = 0; b < body; b++) begin
          int left = body - b;           // instructions left in the body incl. this one
          if (r.chance(15) && left > 1)  // forward branch that stays inside the body
            p.emit(encI(bops[r.range(0, 2)], pick_src(r, recent), 0, 16'(r.range(1, left))));
          else
            p.emit(rand_alu_mem(r, recent));
        end
        p.emit(encI(OP_SUBI, LOOP_REG, LOOP_REG, 16'd1));
        p.emit(encI(OP_BPL,  LOOP_REG, 0, 16'(start - p.len)));
      end else begin
        p.emit(rand_alu_mem(r, recent));
      end
    end
    p.emit(HALT_I);
    // live junk after HALT, then the rest of memory
    for (int i = p.len; i < MEM_WORDS; i++) p.imem[i] = rand_alu_mem(r, recent);
    return p;
  endfunction

  // =========================================================================
  // Test registry
  // =========================================================================
  function automatic Program build_test(string name, int unsigned seed);
    int ph;
    if (name == "hazards")          return build_hazards();
    if (name == "orig_bubble5")     return build_bubble_orig();     // reference program
    if (name == "orig_insertion10") return build_insertion_orig();  // reference program
    if (name == "random")           return build_random(seed, 120 + int'(seed % 60));
    if ($sscanf(name, "isa_p%d", ph) == 1) return build_isa(ph);
    $fatal(1, "unknown test '%s'", name);
    return null;
  endfunction

endpackage
