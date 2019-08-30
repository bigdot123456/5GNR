//////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995/2005 Xilinx, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor : Xilinx
// \   \   \/     Version : 10.1
//  \   \         Description : Xilinx Function Simulation Library Component
//  /   /                  Configuration Simulation Model
// /___/   /\     Filename : SIM_CONFIG_V5.v
// \   \  /  \    Timestamp : 
//  \___\/\___\
//
// Revision:
//    07/10/06 - Initial version.
//    01/04/07 - Add downcont to skip type2 data.
//    01/05/07 - Add INITB output function.
//    01/15/07 - Modify GSR, GTS and GWE generation.                        
//    01/18/07 - Change startup state machine running after DESYNC command.
//    02/01/07 - PROGB low pulse less than 300 ns will not cause reset.
//               Make INITB output before mode pin sampled.
//    02/06/07 - Make INITB to open-drain output.
//    02/08/07 - Use bit_revers8 for 16 bit mode by swaping bytely.
//               Add power on reset por_b;
//    02/20/07 - Generate INITB out for iprob_b also. Add INITB pin strength.
//    04/18/07 - Remove _ from port name.
//    06/04/07 - Add wire declaration to internal signal.
//    06/19/07 - Add LOC parameter to simprim model (CR 441956).
//    07/30/07 - reset init_b_out when iprob_b high for internal reset.
//    07/15/08 - Change readback data from byte to same as write width.(CR477214)
//    01/12/10 - Reverse bits for readback (CR544212)
//    05/19/10 - Not reset startup_set_pulse when rw_en=0 (CR559852)
// End Revision
////////////////////////////////////////////////////////////////////////////////

`timescale  1 ps / 1 ps

module SIM_CONFIG_V5 ( BUSY,
                   CSOB,
                   DONE,
                   CCLK,
                   CSB,
                   D,
                   DCMLOCK,
                   INITB,
                   M,
                   PROGB,
                   RDWRB
                   );
 
  output BUSY;
  output CSOB;
  inout DONE;
  input  CCLK;
  input  CSB;
  inout  [31:0] D; 
  input  DCMLOCK;
  inout  INITB;
  input  [2:0] M;
  input  PROGB;
  input  RDWRB;

  parameter DEVICE_ID = 32'h0;

  localparam cfg_Tprog = 300000;   // min PROG must be low, 300 ns
  localparam cfg_Tpl =   100000;  // max program latency us.
  localparam STARTUP_PH0 = 3'b000;
  localparam STARTUP_PH1 = 3'b001;
  localparam STARTUP_PH2 = 3'b010;
  localparam STARTUP_PH3 = 3'b011;
  localparam STARTUP_PH4 = 3'b100;
  localparam STARTUP_PH5 = 3'b101;
  localparam STARTUP_PH6 = 3'b110;
  localparam STARTUP_PH7 = 3'b111;

//  tri0 GSR, GTS, GWE;
  wire GSR;
  wire GTS;
  wire GWE;
  wire cclk_in;
  wire init_b_in;
  wire prog_b_in;
  wire rdwr_b_in;
  reg init_b_out = 1;
  reg done_o = 0;
  
  tri1 p_up;

  reg por_b;
  wire [2:0] m_in;
  wire [31:0] d_in, d_out;
  wire busy_out;
  wire cso_b_out;
  wire csi_b_in;
  wire d_out_en;
  wire dcm_locked;
  wire init_b_t;
  wire prog_b_t;
  wire bus_en;
  wire desync_flag;
  wire crc_rst;

  assign DONE = p_up;
  assign INITB = p_up;
  assign glbl.GSR = GSR;
  assign glbl.GTS = GTS;
  
  buf buf_busy (BUSY, busy_out);
  buf buf_cso (CSOB, cso_b_out);
  buf buf_cclk (cclk_in, CCLK);
  buf buf_cs (csi_b_in, CSB);

  buf buf_din[31:0] (d_in, D);
  bufif1 buf_dout[31:0] (D, d_out, d_out_en);
  buf buf_dcm (dcm_locked, DCMLOCK);
 
  buf buf_init (init_b_in, INITB);
  buf buf_m_0  (m_in[0], M[0]);
  buf buf_m_1  (m_in[1], M[1]);
  buf buf_m_2  (m_in[2], M[2]);
  buf buf_prog (prog_b_in, PROGB);
  buf buf_rw (rdwr_b_in, RDWRB);

  time  prog_pulse_low_edge = 0;
  time  prog_pulse_low = 0;
  reg  mode_sample_flag = 0;
  reg  buswid_flag_init = 0;
  reg  buswid_flag = 0;
  reg [1:0] buswidth = 2'b00;
  reg [31:0]  pack_in_reg  = 32'b0;
  reg  [4:0] reg_addr;
  reg  new_data_in_flag  = 0;
  reg  wr_flag  = 0;
  reg  rd_flag  = 0;
  reg  cmd_wr_flag  = 0;
  reg  cmd_reg_new_flag = 0;
  reg  cmd_rd_flag  = 0;
  reg  bus_sync_flag = 0;
  reg  conti_data_flag = 0;
  integer  wr_cnt  = 0;
  integer  conti_data_cnt = 0;
  integer  rd_data_cnt = 0;
  integer  abort_cnt = 0;
  reg  [2:0] st_state = STARTUP_PH0;
  reg  startup_begin_flag = 0;
  reg  startup_end_flag = 0;
  reg  crc_ck = 0;
  reg crc_err_flag = 0;
  wire crc_err_flag_tot;
  reg crc_err_flag_reg = 0;
  wire  crc_en;
  reg  [31:0] crc_curr = 32'b0;
  reg  [31:0] crc_new = 32'b0;
  reg  [36:0] crc_input = 32'b0;
  reg  gwe_out = 0;
  reg  gts_out = 1;
  reg  [31:0] d_o = 32'h0;
  reg  [31:0] outbus = 32'h0;
  reg  [31:0] outbus1 = 32'h0;
  reg  busy_o = 0;
  reg [31:0] tmp_val1, tmp_val2;
  reg [31:0] ctl0_reg = 32'bx0xxxxxxxxxxxxxxxxxxx001x0000xx1;
  reg [31:0] cor0_reg = 32'b00000x0000000000x011111111101100;
  reg [31:0] cor1_reg = 32'b0;
  reg [31:0] wbstar_reg = 32'b0;
  reg [31:0] timer_reg = 32'b0;
  reg [31:0] bootsts_reg = 32'b0;
  reg  [31:0] crc_reg;
  reg  [31:0] far_reg;
  reg  [31:0] fdri_reg;
  reg  [31:0] mask_reg;
  reg  [31:0] lout_reg;
  reg  [31:0] mfwr_reg;
  reg  [31:0] cbc_reg;
  reg  [31:0] idcode_reg;
  reg  [31:0] csob_reg;
  reg  [31:0] ctl1_reg;
  reg  [31:0] axss_reg;
  reg  [4:0] cmd_reg;
  reg  [2:0] mode_pin_in = 3'b0;
  reg  [2:0] mode_reg;
  reg  crc_reset = 0;
  reg  gsr_set = 0;
  reg  gts_usr_b = 1;
  reg  done_pin_drv = 0;
  
  reg  shutdown_set = 0;
  reg  desynch_set = 0;
  reg  [2:0] done_cycle_reg;
  reg  [2:0] gts_cycle_reg;
  reg  [2:0] gwe_cycle_reg;
  reg  init_pin;
  reg  init_rst = 0;
  reg  init_complete; 
  reg  [2:0] nx_st_state  = 3'b000;
  reg  ghigh_b = 0;
  reg  gts_cfg_b = 0;
  reg  eos_startup = 0;
  reg startup_set = 0;
  reg [1:0] startup_set_pulse = 2'b0;
  reg abort_out_en = 0;
  reg [31:0] tmp_dword;
  reg [15:0] tmp_word;
  reg [7:0] tmp_byte;
  reg id_error_flag = 0;
  reg iprog_b = 1;
  reg i_init_b_cmd = 1;
  reg i_init_b = 0;
  reg [7:0] abort_status = 8'b0;
  reg persist_en = 0;
  reg rst_sync = 0;
  reg abort_dis = 0;
  reg [2:0] lock_cycle_reg = 3'b0;
  reg rbcrc_no_pin = 0;
  reg abort_flag_rst = 0;
  reg gsr_st_out = 1; 
  reg gsr_cmd_out = 0;
  reg gsr_cmd_out_pulse = 0;
  reg d_o_en = 0;
  wire [31:0] stat_reg;
  wire rst_intl;
  wire rw_en;
  wire gsr_out;
  wire cfgerr_b_flag;
  reg  abort_flag_wr = 0;
  reg  abort_flag_rd = 0;
  wire  abort_flag;
  integer downcont_cnt = 0;
//  reg rst_en = 1;
  reg rst_en = 0;
  reg prog_b_a = 1;
  reg csbo_flag = 0;
  reg crc_bypass = 0;
  reg csi_sync = 0;
  reg rd_sw_en = 0;
  integer csbo_cnt = 0;
  reg [4:0] rd_reg_addr = 5'b0;
  
  triand (weak1, strong0) INITB=(mode_sample_flag) ? ~crc_err_flag_tot : init_b_out;
  triand (weak1, strong0) DONE=done_o;

  initial begin
    if (DEVICE_ID == 32'h0) begin
      $display("Attribute Error : The attribute DEVICE_ID on  SIM_CONFIG_V5 instance %m is not set.");
      $finish;
     end
   end


   assign GSR = gsr_out;
   assign GTS = gts_out;
   assign GWE = gwe_out;
   assign busy_out = busy_o;
   assign cfgerr_b_flag = rw_en & ~crc_err_flag_tot;
   assign crc_err_flag_tot = id_error_flag | crc_err_flag_reg;
   assign d_out[7:0] = (abort_out_en ) ? abort_status : outbus1[7:0];
   assign d_out[31:8] = (abort_out_en ) ? 24'b0 : outbus1[31:8];
   assign d_out_en = d_o_en;
   assign cso_b_out = (csbo_flag== 1) ? 0 : 1;
   assign crc_en =  1;

   always @(outbus) begin
         outbus1[7:0] = bit_revers8(outbus[7:0]);
         outbus1[15:8] = bit_revers8(outbus[15:8]);
         outbus1[23:16] = bit_revers8(outbus[23:16]);
         outbus1[31:24] = bit_revers8(outbus[31:24]);
   end

   always @(csi_b_in or abort_flag) 
        if (csi_b_in) 
           busy_o = 1'b1;
        else
          if (abort_flag)
            busy_o = 1'b1;
          else
            busy_o = 1'b0;

   always @(abort_out_en or csi_b_in or rdwr_b_in && rd_flag )
    if (abort_out_en)
       d_o_en = 1;
    else
       d_o_en = rdwr_b_in & ~csi_b_in & rd_flag;


  assign init_b_t = init_b_in & i_init_b_cmd;

  always @( negedge prog_b_in) begin
         rst_en = 0;
         rst_en <= #cfg_Tprog 1;
  end

  always @( rst_en or init_rst or prog_b_in or iprog_b )
   if (init_rst)
       init_b_out <= 0;
   else begin
     if ((prog_b_in == 0 ) && (rst_en == 1) || (iprog_b == 0))
         init_b_out <= 0;
     else if ((prog_b_in == 1 ) && (rst_en == 1) || (iprog_b == 1))
         init_b_out <= #(cfg_Tpl) 1;
   end

  always @(posedge id_error_flag) begin
      init_rst <= 1;
      init_rst <= #cfg_Tprog 0;
  end
  
  always @( rst_en or prog_b_in or prog_pulse_low)
    if (rst_en) begin
       if (prog_pulse_low==cfg_Tprog) begin
           prog_b_a = 0;
           prog_b_a <= #500 1;
       end
       else
          prog_b_a = prog_b_in;
    end
    else 
          prog_b_a = 1;

  initial begin
    por_b = 0;
    por_b = #400000 1;
  end 

  assign prog_b_t = prog_b_a  & iprog_b & por_b;

  assign rst_intl = (prog_b_t==0 ) ? 0 : 1;

  always @(posedge init_b_t or negedge prog_b_t) 
    if (prog_b_t==0)
         mode_sample_flag <= 0;
    else if (init_b_t && mode_sample_flag == 0) begin
       if (prog_b_t)  begin
          mode_pin_in <= m_in;
          mode_sample_flag <= #1 1;
          if (m_in != 3'b110) begin
             $display("Error: input M is %h. Only Slave SelectMAP mode M=110 supported on SIM_CONFIG_V5 instance %m.", m_in);
          end
       end     
       else if ($time != 0)
       $display("Error: PROGB is not high when INITB goes high on SIM_CONFIG_V5 instance %m at time %t.", $time);
    end

  always @(m_in)
    if (mode_sample_flag == 1 && persist_en == 1)
       $display("Error : Mode pine M[2:0] changed after rising edge of INITB on SIM_CONFIG_V5 instance %m at time %t.", $time);
  
  always @(posedge prog_b_in or negedge prog_b_in)
    if (prog_b_in ==0) 
        prog_pulse_low_edge <= $time;
    else if (prog_b_in == 1 && $time > 0) begin
       prog_pulse_low = $time - prog_pulse_low_edge;
       if (prog_pulse_low < cfg_Tprog )
        $display("Error: Low time of PROGB is less than required minimum Tprogram time %d on SIM_CONFIG_V5 instance %m at time %t.", cfg_Tprog, $time);
    end

    assign bus_en = (mode_sample_flag == 1 &&  csi_b_in ==0) ? 1 : 0;

    always @(posedge cclk_in or negedge rst_intl)
      if (rst_intl ==0) begin
         buswid_flag_init <= 0;
         buswid_flag <= 0;
         buswidth <= 2'b00;
      end
      else
        if (buswid_flag == 0) begin
           if (bus_en==1 && rdwr_b_in == 0)  begin
                 tmp_byte = bit_revers8(d_in[7:0]);
                 if (buswid_flag_init == 0) begin
                     if (tmp_byte == 8'hBB)
//                     if (tmp_byte == 8'hDD)
                         buswid_flag_init <= 1;
                  end
                  else begin
                     if (tmp_byte == 8'h11) begin
                         buswid_flag <= 1; 
                         buswidth <= 2'b01;
                     end
                     else if (tmp_byte == 8'h22) begin
                         buswid_flag <= 1; 
                         buswidth <= 2'b10;
                     end
                     else if (tmp_byte == 8'h44) begin
                         buswid_flag <= 1; 
                         buswidth <= 2'b11;
                     end
                     else begin
                         buswid_flag <= 0; 
                         buswidth <= 2'b00;
                         buswid_flag_init <= 0;
                         $display("Error : BUS Width Auto Dection did not find 0x11 or 0x22 or 0x44 on D[7:0] followed 0xBB on SIM_CONFIG_V5 instance %m at time %t.", $time);
                         $finish;
                     end
                 end
            end
     end
 
    assign rw_en = (bus_en == 1 && buswid_flag == 1) ?  1 : 0;
    assign desync_flag = ~rst_intl | desynch_set | crc_err_flag | id_error_flag;

    always @(posedge cclk_in)
       csi_sync <= csi_b_in;

    always @(posedge cclk_in or negedge rdwr_b_in)
     if (rdwr_b_in ==0)
       rd_sw_en <= 0;
     else begin
      if (csi_sync == 1 && rdwr_b_in ==1)
          rd_sw_en <= 1;
     end

    always @(posedge cclk_in or posedge desync_flag)
      if (desync_flag == 1) begin
          pack_in_reg <= 32'b0;
          new_data_in_flag <= 0;
          bus_sync_flag <= 0;
          wr_cnt <= 0;
          wr_flag <= 0;
          rd_flag <= 0;
      end
      else begin
       if (rw_en == 1 ) begin
         if (rdwr_b_in == 0) begin
           wr_flag <= 1;
           rd_flag <= 0;
           if (buswidth == 2'b01) begin
               tmp_byte = bit_revers8(d_in[7:0]);
               if (bus_sync_flag == 0) begin
                  if (pack_in_reg[23:16] == 8'hAA && pack_in_reg[15:8] == 8'h99 
                      && pack_in_reg[7:0] == 8'h55 && tmp_byte == 8'h66) begin
                          bus_sync_flag <= 1;
                          new_data_in_flag <= 0;
                          wr_cnt <= 0;
                   end
                   else begin
                      pack_in_reg[31:24] <= pack_in_reg[23:16];
                      pack_in_reg[23:16] <= pack_in_reg[15:8];
                      pack_in_reg[15:8] <= pack_in_reg[7:0];
                      pack_in_reg[7:0] <= tmp_byte;
                   end
               end
               else begin
                 if (wr_cnt == 0) begin
                    pack_in_reg[31:24] <= tmp_byte;
                     new_data_in_flag <= 0;
                     wr_cnt <=  1;
                 end
                 else if (wr_cnt == 1) begin
                     pack_in_reg[23:16] <= tmp_byte;
                     new_data_in_flag <= 0;
                     wr_cnt <= 2;
                 end
                 else if (wr_cnt == 2) begin
                     pack_in_reg[15:8] <= tmp_byte;
                     new_data_in_flag <= 0;
                     wr_cnt <= 3;
                 end
                 else if (wr_cnt == 3) begin
                     pack_in_reg[7:0] <= tmp_byte;
                     new_data_in_flag <= 1;
                     wr_cnt <= 0;
                 end
             end
           end
           else if (buswidth == 2'b10) begin
             tmp_word = {bit_revers8(d_in[15:8]), bit_revers8(d_in[7:0])};
             if (bus_sync_flag == 0) begin
                if (pack_in_reg[15:0] == 16'hAA99 && tmp_word ==16'h5566) begin
                     wr_cnt <= 0;
                     bus_sync_flag <= 1;
                     new_data_in_flag <= 0;
                end
                else begin
                   pack_in_reg[31:16] <= pack_in_reg[15:0];
                   pack_in_reg[15:0] <= tmp_word;
                   new_data_in_flag <= 0;
                   wr_cnt <= 0;
                end
             end
             else begin
               if (wr_cnt == 0) begin
                   pack_in_reg[31:16] <= tmp_word;
                   new_data_in_flag <= 0;
                   wr_cnt <= 1;
               end
               else if (wr_cnt == 1) begin
                   pack_in_reg[15:0] <= tmp_word;
                   new_data_in_flag <= 1;
                   wr_cnt <= 0;
               end
             end
           end
           else if (buswidth == 2'b11 ) begin
             tmp_dword = {bit_revers8(d_in[31:24]), bit_revers8(d_in[23:16]), bit_revers8(d_in[15:8]),
                          bit_revers8(d_in[7:0])};
             pack_in_reg[31:0] <= tmp_dword;
             if (bus_sync_flag == 0) begin
                if (tmp_dword == 32'hAA995566) begin
                     bus_sync_flag <= 1;
                     new_data_in_flag <= 0;
                end
             end
             else begin
                pack_in_reg[31:0] <= tmp_dword;
                new_data_in_flag <= 1;
             end
           end
       end
       else begin
            wr_flag <= 0;
            new_data_in_flag <= 0;
            if (rd_sw_en ==1)
               rd_flag <= 1;
       end
     end
     else begin
            wr_flag <= 0;
            rd_flag <= 0;
            new_data_in_flag <= 0;
     end
   end
           
    always @(negedge cclk_in or negedge rst_intl)
      if (rst_intl ==0) begin
         conti_data_flag <= 0;
         conti_data_cnt <= 0;
         cmd_wr_flag <= 0;
         cmd_rd_flag <= 0;
         id_error_flag <= 0;
         crc_curr <= 32'b0;
         crc_ck <= 0;
         csbo_cnt <= 0;
         csbo_flag <= 0;
         downcont_cnt <= 0;
         rd_data_cnt <= 0;
      end
      else begin
        if (crc_reset == 1 ) begin
            crc_reg <= 32'b0;
            crc_ck <= 0;
            crc_curr <= 32'b0;
        end
        if (crc_ck == 1)
             crc_curr <= 32'b0;

        if (desynch_set || crc_err_flag==1) begin
           conti_data_flag <= 0;
           conti_data_cnt <= 0;
           cmd_wr_flag <= 0;
           cmd_rd_flag <= 0;
           cmd_reg_new_flag <= 0;
           crc_ck <= 0;
           csbo_cnt <= 0;
           csbo_flag <= 0;
           downcont_cnt <= 0;
           rd_data_cnt <= 0;
        end


        if (new_data_in_flag==1 && wr_flag==1) begin
           if (conti_data_flag == 1 ) begin
               case (reg_addr)
               5'b00000 : begin 
                             crc_reg <= pack_in_reg;
                             crc_ck <= 1;
                          end 
               5'b00001 : far_reg <= pack_in_reg;
               5'b00010 : fdri_reg <= pack_in_reg;
               5'b00100 : cmd_reg <= pack_in_reg[4:0];
               5'b00101 : ctl0_reg <= (pack_in_reg & mask_reg) | (ctl0_reg & ~mask_reg);
               5'b00110 : mask_reg <= pack_in_reg;
               5'b01000 : lout_reg <= pack_in_reg;
               5'b01001 : cor0_reg <= pack_in_reg;
               5'b01010 : mfwr_reg <= pack_in_reg;
//              5'b01101 : cbc_reg <= pack_in_reg;
               5'b01100 : begin
                          idcode_reg <= pack_in_reg;
                          if (pack_in_reg[27:0] != DEVICE_ID[27:0]) begin
                             id_error_flag <= 1;
                             $display("Error : written value to IDCODE register is %h which does not match DEVICE ID %h on SIM_CONFIG_V5 instance %m at time %t.", pack_in_reg, DEVICE_ID, $time);
                          end 
                          else
                             id_error_flag <= 0;
                          end
               5'b01101 : axss_reg <= pack_in_reg;
               5'b01110 : cor1_reg <= pack_in_reg;
               5'b01111 : csob_reg <= pack_in_reg;
               5'b10000 : wbstar_reg <= pack_in_reg;
               5'b10001 : timer_reg <= pack_in_reg;
               5'b11000 : ctl1_reg <= (pack_in_reg & mask_reg) | (ctl1_reg & ~mask_reg);
               endcase
   
             if (reg_addr != 5'b00000)
                crc_ck <= 0;

             if (reg_addr == 5'b00100)
                  cmd_reg_new_flag <= 1;
             else
                 cmd_reg_new_flag <= 0;

             if (crc_en == 1) begin 
               if (reg_addr == 5'h04 && pack_in_reg[4:0] == 5'b00111)
                   crc_curr[31:0] = 32'b0;
               else begin
                  if ( reg_addr != 5'h03 && reg_addr != 5'h07 && reg_addr != 5'h16 && 
                    reg_addr != 5'h08 &&  reg_addr != 5'h00) begin
                     crc_input[36:0] = {reg_addr, pack_in_reg}; 
                     crc_new[31:0] = bcc_next(crc_curr, crc_input);
                     crc_curr[31:0] <= crc_new;
                   end
               end
             end

             if (conti_data_cnt <= 1) begin
                  conti_data_cnt <= 0;
              end
             else 
                conti_data_cnt <= conti_data_cnt - 1;
        end
        else if (conti_data_flag == 0 ) begin
            if ( downcont_cnt >= 1) begin
                   if (crc_en == 1) begin
                     crc_input[36:0] =  {5'b00010, pack_in_reg}; 
                     crc_new[31:0] = bcc_next(crc_curr, crc_input);
                     crc_curr[31:0] <= crc_new;
                   end
             end

             if (pack_in_reg[31:29] == 3'b010 && downcont_cnt == 0  ) begin
//                $display("Warning :  only Type 1 Packet supported on SIM_CONFIG_V5 instance %m at time %t.", $time);
                cmd_rd_flag <= 0;
                cmd_wr_flag <= 0;
                conti_data_flag <= 0;
                conti_data_cnt <= 0;
                downcont_cnt <= pack_in_reg[26:0];
             end
             else if (pack_in_reg[31:29] == 3'b001) begin // type 1 package
                if (pack_in_reg[28:27] == 2'b01 && downcont_cnt == 0) begin
                    if (pack_in_reg[10:0] != 10'b0) begin
                       cmd_rd_flag <= 1;
                       cmd_wr_flag <= 0;
                       rd_data_cnt <= pack_in_reg[10:0];
                       rd_data_cnt <= 4;
//                       if (buswidth == 2'b01)
//                          rd_data_cnt <= 4;
//                       else if (buswidth == 2'b10)
//                          rd_data_cnt <= 2;
//                       else if (buswidth == 2'b11)
//                          rd_data_cnt <= 1;
                       conti_data_cnt <= 0;
                       conti_data_flag <= 0;
                       rd_reg_addr <= pack_in_reg[17:13];
                    end
                end
                else if (pack_in_reg[28:27] == 2'b10 && downcont_cnt == 0) begin
                   if (pack_in_reg[17:13] == 5'b01111) begin  // csbo reg
                           csob_reg <= pack_in_reg;
                           csbo_cnt = pack_in_reg[10:0];
                           csbo_flag <= 1;
                           conti_data_flag = 0;
                           reg_addr <= pack_in_reg[17:13];
                           cmd_wr_flag <= 1;
                           conti_data_cnt <= 5'b0;
                    end
                    else if (pack_in_reg[10:0] != 10'b0) begin
                       cmd_rd_flag <= 0;
                       cmd_wr_flag <= 1;
                       conti_data_flag <= 1;
                       conti_data_cnt <= pack_in_reg[10:0];
                       reg_addr <= pack_in_reg[17:13];
                    end
                end
                else begin
                    cmd_wr_flag <= 0;
                    conti_data_flag <= 0;
                    conti_data_cnt <= 0;
                end
             end
             cmd_reg_new_flag <= 0;
             crc_ck <= 0;
          end    // if (conti_data_flag == 0 ) 
          if (csbo_cnt != 0 ) begin
             if (csbo_flag == 1)
              csbo_cnt <= csbo_cnt - 1;
          end
          else
              csbo_flag <= 0;

          if (conti_data_cnt == 5'b00001 ) 
                conti_data_flag <= 0;

      end

      if (rw_en ==1) begin
         if (rd_data_cnt == 1 && rd_flag == 1) 
            rd_data_cnt <= 0;
         else if (rd_data_cnt == 0 && rd_flag == 1)
               cmd_rd_flag <= 0;
         else if (cmd_rd_flag ==1  && rd_flag == 1)
             rd_data_cnt <= rd_data_cnt - 1;

          if (downcont_cnt >= 1 && conti_data_flag == 0 && new_data_in_flag == 1 && wr_flag == 1)
              downcont_cnt <= downcont_cnt - 1;
      end

      if (crc_ck)
        crc_ck <= 0;
    end


   always @(posedge cclk_in or negedge rst_intl)
    if (rst_intl ==0) begin
         outbus <= 32'b0;
     end
    else begin
        if (cmd_rd_flag == 1 && rdwr_b_in == 1 && csi_b_in == 0) begin
               case (rd_reg_addr)
               5'b00000 : if (buswidth == 2'b01) begin
                            outbus[31:8] <= 24'b0;
                            if (rd_data_cnt==1) 
                               outbus[7:0] <= crc_reg[7:0];
                            else if (rd_data_cnt==2) 
                               outbus[7:0] <= crc_reg[15:8];
                            else if (rd_data_cnt==3) 
                               outbus[7:0] <= crc_reg[23:16];
                            else if (rd_data_cnt==4) 
                               outbus[7:0] <= crc_reg[31:24];
                          end
                          else if (buswidth == 2'b10) begin
                             outbus[31:16] <= 16'b0;
                             if (rd_data_cnt==1)
                               outbus[15:0] <= crc_reg[15:0];
                            else if (rd_data_cnt==2)
                               outbus[15:0] <= crc_reg[31:16];
                             else if (rd_data_cnt==3)
                               outbus[15:0] <= 16'h00FF;
                            else if (rd_data_cnt==4)
                               outbus[15:0] <= 16'h00FF;
                          end
                          else if (buswidth == 2'b11) begin
                              if (rd_data_cnt==1)
                               outbus <= crc_reg;
                              else if (rd_data_cnt==2)
                               outbus <= 32'h000000FF;
                              else if (rd_data_cnt==3)
                               outbus <= 32'h000000FF;
                              else if (rd_data_cnt==4)
                               outbus <= 32'h000000FF;
                          end
                             
               5'b00111 : if (buswidth == 2'b01) begin
                             outbus[31:8] <= 24'b0;
                             if (rd_data_cnt==1) 
                               outbus[7:0] <= stat_reg[7:0];
                            else if (rd_data_cnt==2)
                               outbus[7:0] <= stat_reg[15:8];
                            else if (rd_data_cnt==3)
                               outbus[7:0] <= stat_reg[23:16];
                            else if (rd_data_cnt==4)
                               outbus[7:0] <= stat_reg[31:24];
                            end
                            else if (buswidth == 2'b10) begin
                              outbus[31:16] <= 16'b0;
                              if (rd_data_cnt==1)
                               outbus[15:0] <= stat_reg[15:0];
                            else if (rd_data_cnt==2)
                               outbus[15:0] <= stat_reg[31:16];
                            else if (rd_data_cnt==3)
                               outbus[15:0] <= 16'h00FF;
                            else if (rd_data_cnt==4)
                               outbus[15:0] <= 16'h00FF;
                            end
                            else if (buswidth == 2'b11) begin
                              if (rd_data_cnt==1)
                               outbus <= stat_reg;
                              else if (rd_data_cnt==2)
                               outbus <= 32'h000000FF; 
                              else if (rd_data_cnt==3)
                               outbus <= 32'h000000FF;
                              else if (rd_data_cnt==4)
                               outbus <= 32'h000000FF;
                            end
               5'b01100 :   if (buswidth == 2'b01) begin 
                               outbus[31:8] <= 24'b0;
                            if (rd_data_cnt==1)
                               outbus[7:0] <= idcode_reg[7:0];
                            else if (rd_data_cnt==2)
                               outbus[7:0] <= idcode_reg[15:8];
                            else if (rd_data_cnt==3)
                               outbus[7:0] <= idcode_reg[23:16];
                            else if (rd_data_cnt==4)
                               outbus[7:0] <= idcode_reg[31:24];
                            end
                            else if (buswidth == 2'b10) begin
                               outbus[31:16] <= 16'b0;
                            if (rd_data_cnt==1)
                               outbus[15:0] <= idcode_reg[15:0];
                            else if (rd_data_cnt==2)
                               outbus[15:0] <= idcode_reg[31:16];
                            else if (rd_data_cnt==3)
                               outbus[15:0] <= 16'h00FF;
                            else if (rd_data_cnt==4)
                               outbus[15:0] <= 16'h00FF;
                            end
                            else if (buswidth == 2'b11) begin
                              if (rd_data_cnt==1)
                               outbus <= idcode_reg;
                              else if (rd_data_cnt==2)
                               outbus <= 32'h000000FF;
                              else if (rd_data_cnt==3)
                               outbus <= 32'h000000FF;
                              else if (rd_data_cnt==4)
                               outbus <= 32'h000000FF;
                            end
               endcase
       end
       else
             outbus <= 32'b0;
   end

        

    assign crc_rst = crc_reset | ~rst_intl;

    always @(posedge cclk_in or posedge crc_rst )
     if (crc_rst)
         crc_err_flag <= 0;
     else
        if (crc_ck) begin
          if (crc_bypass) begin
             if (crc_reg[15:0] != 16'hdefc) 
                 crc_err_flag <= 1;
             else
                 crc_err_flag <= 0;
          end
          else begin
            if (crc_curr[31:0] != crc_reg[31:0]) 
                crc_err_flag <= 1;
            else
                 crc_err_flag <= 0;
          end
       end
       else
           crc_err_flag <= 0;

    always @(posedge crc_err_flag or negedge rst_intl or posedge bus_sync_flag)
     if (rst_intl == 0)
         crc_err_flag_reg <= 0;
     else if (crc_err_flag == 1)
         crc_err_flag_reg <= 1;
     else
         crc_err_flag_reg <= 0;

    always @(posedge cclk_in or negedge rst_intl)
    if (rst_intl ==0) begin
         startup_set <= 0;
         crc_reset  <= 0;
         gsr_cmd_out <= 0;
         shutdown_set <= 0;
         desynch_set <= 0;
         ghigh_b <= 0;
    end
    else begin
    if (cmd_reg_new_flag ==1) begin
      if (cmd_reg == 5'b00011) 
          ghigh_b <= 1;
      else if (cmd_reg == 5'b01000)
           ghigh_b <= 0;

      if (cmd_reg == 5'b00101)
           startup_set <= 1;

      if (cmd_reg == 5'b00111) 
           crc_reset <= 1;

      if (cmd_reg == 5'b01010) 
           gsr_cmd_out <= 1;

      if (cmd_reg == 5'b01011)
           shutdown_set <= 1;

      if (cmd_reg == 5'b01101) 
           desynch_set <= 1;

      if (cmd_reg == 5'b01111) begin
          iprog_b <= 0;
          i_init_b_cmd <= 0;
          iprog_b <= #cfg_Tprog 1;
          i_init_b_cmd <=#(cfg_Tprog + cfg_Tpl) 1;
      end
    end
    else begin
             startup_set <= 0;
              crc_reset <= 0;
              gsr_cmd_out <= 0;
              shutdown_set <= 0;
              desynch_set <= 0;
      end
    end

   always @(posedge startup_set or posedge desynch_set or   rw_en )
    if (rw_en == 1)
//       startup_set_pulse <= 2'b0;
//    else begin
    begin
      if (startup_set_pulse == 2'b00 && startup_set ==1)
           startup_set_pulse <= 2'b01;
      else if (desynch_set == 1 && startup_set_pulse == 2'b01) begin
           startup_set_pulse <= 2'b11;
           @(posedge cclk_in )
             startup_set_pulse <= 2'b00;
      end
    end

   always @(posedge gsr_cmd_out or   rw_en)
    if (rw_en == 1)
//       gsr_cmd_out_pulse <= 0;
//    else begin
    begin
       gsr_cmd_out_pulse <= 1;
        @(posedge cclk_in );
          @(posedge cclk_in )
           gsr_cmd_out_pulse <=  0;
    end

    always @(ctl0_reg) begin
      if (ctl0_reg[9] == 1)
         abort_dis = 1;
      else
         abort_dis = 0;

      if (ctl0_reg[3] == 1)
         persist_en = 1;
      else
         persist_en = 0;
 
      if (ctl0_reg[0] == 1)
         gts_usr_b = 1;
      else
         gts_usr_b = 0;
    end

    always @(cor0_reg)
    begin
      done_cycle_reg = cor0_reg[14:12];
      lock_cycle_reg = cor0_reg[8:6];
      gts_cycle_reg = cor0_reg[5:3];
      gwe_cycle_reg = cor0_reg[2:0];

     if (cor0_reg[24] == 1'b1)
         done_pin_drv = 1;
      else
         done_pin_drv = 0;

      if (cor0_reg[28] == 1'b1)
         crc_bypass = 1;
      else
         crc_bypass = 0;
    end

    always @(cor1_reg)
       rbcrc_no_pin = cor1_reg[8];


    assign stat_reg[26:25] = buswidth;
    assign stat_reg[20:18] = st_state;
    assign stat_reg[16] = 1'b0;
    assign stat_reg[15] = id_error_flag;
    assign stat_reg[14] = DONE;
    assign stat_reg[13] = (done_o !== 0) ? 1 : 0;
    assign stat_reg[12] = INITB;
    assign stat_reg[11] = mode_sample_flag;
    assign stat_reg[10:8] = mode_pin_in;
    assign stat_reg[7] = ghigh_b;
    assign stat_reg[6] = gwe_out;
    assign stat_reg[5] = gts_cfg_b;
    assign stat_reg[4] = eos_startup;
    assign stat_reg[3] = 1'bx;
    assign stat_reg[2] = dcm_locked;
    assign stat_reg[1] = 1'bx;
    assign stat_reg[0] = crc_err_flag_reg; 


    always @(posedge cclk_in or negedge rst_intl)
      if (rst_intl == 0) begin
        st_state <= STARTUP_PH0;
        startup_begin_flag <= 0;
        startup_end_flag <= 0;
      end
      else begin
           if (nx_st_state == STARTUP_PH1) begin
              startup_begin_flag <= 1;
              startup_end_flag <= 0;
           end
           else if (st_state == STARTUP_PH7) begin
              startup_end_flag <= 1;
              startup_begin_flag <= 0;
           end
           if  (lock_cycle_reg == 3'b111 || dcm_locked == 1 || st_state != lock_cycle_reg ) begin
                st_state <= nx_st_state;
           end
           else
              st_state <= st_state;
      end

    always @(st_state or startup_set_pulse or DONE ) 
//    if ( st_state == (done_cycle_reg + 1) && (DONE == 0) )
//        nx_st_state  = done_cycle_reg + 1;
//    else
    if (((st_state == done_cycle_reg) && (DONE != 0)) || (st_state != done_cycle_reg))
      case (st_state)
      STARTUP_PH0 : if (startup_set_pulse == 2'b11 ) 
                       nx_st_state = STARTUP_PH1;
                    else
                       nx_st_state = STARTUP_PH0;
      STARTUP_PH1 : nx_st_state = STARTUP_PH2;

      STARTUP_PH2 : nx_st_state = STARTUP_PH3;

      STARTUP_PH3 : nx_st_state = STARTUP_PH4;

      STARTUP_PH4 : nx_st_state = STARTUP_PH5;

      STARTUP_PH5 : nx_st_state = STARTUP_PH6;

      STARTUP_PH6 : nx_st_state = STARTUP_PH7;

      STARTUP_PH7 : nx_st_state = STARTUP_PH0;
      endcase

    always @(posedge cclk_in or negedge rst_intl )
      if (rst_intl == 0) begin
          gwe_out <= 0;
          gts_out <= 1;
          eos_startup <= 0;
          gsr_st_out <= 1;
          done_o <= 0;
      end
//      else if (startup_begin_flag == 1) begin
      else  begin

         if (nx_st_state == done_cycle_reg) begin
            if (DONE != 0 || done_pin_drv == 1) 
                  done_o <= 1'b1;
             else 
                 done_o <= 1'bz;
         end
         else begin
            if (DONE  !=  0)
                 done_o <= 1;
         end
         
         if (st_state == gwe_cycle_reg && DONE != 0)  
             gwe_out <= 1;
        
         if (st_state == gts_cycle_reg && DONE != 0)  
             gts_out <= 0;
            
         if (st_state == STARTUP_PH6 && DONE != 0)
             gsr_st_out <= 0;

         if (st_state == STARTUP_PH7 && DONE != 0) 
            eos_startup <= 1;
         
      end
      
     assign gsr_out = gsr_st_out | gsr_cmd_out;
     
    always @(posedge rdwr_b_in  or negedge rst_intl or
                posedge abort_flag_rst or posedge csi_b_in)
      if (rst_intl==0 || abort_flag_rst==1 || csi_b_in == 1)
          abort_flag_wr <= 0;
      else
        if (abort_dis == 0 && csi_b_in == 0) begin
             if ($time != 0) begin
               abort_flag_wr <= 1;
               $display(" Warning : RDWRB changes when CSB low, which causes Configuration abort on SIM_CONFIG_V5 instance %m at time %t.", $time);
             end
        end
        else
           abort_flag_wr <= 0;

    always @( negedge rdwr_b_in or negedge rst_intl or posedge abort_flag_rst or posedge csi_b_in)
      if (rst_intl==0 ||  csi_b_in == 1 || abort_flag_rst==1)
          abort_flag_rd <= 0;
      else
       if (abort_dis == 0 && csi_b_in == 0) begin
         if ($time != 0) begin
          abort_flag_rd <= 1;
          $display(" Warning : RDWRB changes when CSB low, which causes Configuration abort on SIM_CONFIG_V5 instance %m at time %t.", $time);
        end
       end
       else
         abort_flag_rd <= 0;

    assign abort_flag = abort_flag_wr | abort_flag_rd;


    always @(posedge cclk_in or negedge rst_intl)
      if (rst_intl == 0) begin
         abort_cnt <= 0;
         abort_out_en <= 0;
      end
      else begin
         if ( abort_flag ==1 ) begin
             if (abort_cnt < 4) begin
                 abort_cnt <= abort_cnt + 1;
                 abort_out_en <= 1;
             end
             else 
                abort_flag_rst <= 1;
         end
         else begin
                abort_cnt <=  0;
                abort_out_en <= 0;
                abort_flag_rst <= 0;
         end
    
         if (abort_cnt== 0)
            abort_status <= {cfgerr_b_flag, bus_sync_flag, 1'b0, 1'b1, 4'b1111};
         else if (abort_cnt== 1)
            abort_status <= {cfgerr_b_flag, 1'b1, 1'b0, 1'b0, 4'b1111};
         else if (abort_cnt== 2)
            abort_status <= {cfgerr_b_flag, 1'b0, 1'b0, 1'b0, 4'b1111};
         else if (abort_cnt== 3)
            abort_status <= {cfgerr_b_flag, 1'b0, 1'b0, 1'b1, 4'b1111};
     
    end
         

function [31:0] bcc_next;
  input [31:0] bcc;
  input [36:0] in;
reg [31:0] x;
reg [36:0] m;
begin
 m = in;
 x = in[31:0] ^ bcc;

 bcc_next[31] = m[32]^m[36]^x[31]^x[30]^x[29]^x[28]^x[27]^x[24]^x[20]^x[19]^x[18]^x[15]^x[13]^x[11]^x[10]^x[9]^x[8]^x[6]^x[5]^x[1]^x[0];

 bcc_next[30] = m[35]^x[31]^x[30]^x[29]^x[28]^x[27]^x[26]^x[23]^x[19]^x[18]^x[17]^x[14]^x[12]^x[10]^x[9]^x[8]^x[7]^x[5]^x[4]^x[0];

 bcc_next[29] = m[34]^x[30]^x[29]^x[28]^x[27]^x[26]^x[25]^x[22]^x[18]^x[17]^x[16]^x[13]^x[11]^x[9]^x[8]^x[7]^x[6]^x[4]^x[3];

 bcc_next[28] = m[33]^x[29]^x[28]^x[27]^x[26]^x[25]^x[24]^x[21]^x[17]^x[16]^x[15]^x[12]^x[10]^x[8]^x[7]^x[6]^x[5]^x[3]^x[2];

 bcc_next[27] = m[32]^x[28]^x[27]^x[26]^x[25]^x[24]^x[23]^x[20]^x[16]^x[15]^x[14]^x[11]^x[9]^x[7]^x[6]^x[5]^x[4]^x[2]^x[1];

 bcc_next[26] = x[31]^x[27]^x[26]^x[25]^x[24]^x[23]^x[22]^x[19]^x[15]^x[14]^x[13]^x[10]^x[8]^x[6]^x[5]^x[4]^x[3]^x[1]^x[0];

 bcc_next[25] = m[32]^m[36]^x[31]^x[29]^x[28]^x[27]^x[26]^x[25]^x[23]^x[22]^x[21]^x[20]^x[19]^x[15]^x[14]^x[12]^x[11]^x[10]^x[8]^x[7]^x[6]^x[4]^x[3]^x[2]^x[1];

 bcc_next[24] = m[35]^x[31]^x[30]^x[28]^x[27]^x[26]^x[25]^x[24]^x[22]^x[21]^x[20]^x[19]^x[18]^x[14]^x[13]^x[11]^x[10]^x[9]^x[7]^x[6]^x[5]^x[3]^x[2]^x[1]^x[0];

 bcc_next[23] = m[32]^m[34]^m[36]^x[31]^x[28]^x[26]^x[25]^x[23]^x[21]^x[17]^x[15]^x[12]^x[11]^x[4]^x[2];

 bcc_next[22] = m[32]^m[33]^m[35]^m[36]^x[29]^x[28]^x[25]^x[22]^x[19]^x[18]^x[16]^x[15]^x[14]^x[13]^x[9]^x[8]^x[6]^x[5]^x[3]^x[0];

 bcc_next[21] = m[34]^m[35]^m[36]^x[30]^x[29]^x[21]^x[20]^x[19]^x[17]^x[14]^x[12]^x[11]^x[10]^x[9]^x[7]^x[6]^x[4]^x[2]^x[1]^x[0];

 bcc_next[20] = m[32]^m[33]^m[34]^m[35]^m[36]^x[31]^x[30]^x[27]^x[24]^x[16]^x[15]^x[3];

 bcc_next[19] = m[32]^m[33]^m[34]^m[35]^x[31]^x[30]^x[29]^x[26]^x[23]^x[15]^x[14]^x[2];

 bcc_next[18] = m[33]^m[34]^m[36]^x[27]^x[25]^x[24]^x[22]^x[20]^x[19]^x[18]^x[15]^x[14]^x[11]^x[10]^x[9]^x[8]^x[6]^x[5]^x[0];

 bcc_next[17] = m[33]^m[35]^m[36]^x[31]^x[30]^x[29]^x[28]^x[27]^x[26]^x[23]^x[21]^x[20]^x[17]^x[15]^x[14]^x[11]^x[7]^x[6]^x[4]^x[1]^x[0];

 bcc_next[16] = m[32]^m[34]^m[35]^x[30]^x[29]^x[28]^x[27]^x[26]^x[25]^x[22]^x[20]^x[19]^x[16]^x[14]^x[13]^x[10]^x[6]^x[5]^x[3]^x[0];

 bcc_next[15] = m[33]^m[34]^x[31]^x[29]^x[28]^x[27]^x[26]^x[25]^x[24]^x[21]^x[19]^x[18]^x[15]^x[13]^x[12]^x[9]^x[5]^x[4]^x[2];

 bcc_next[14] = m[32]^m[33]^x[30]^x[28]^x[27]^x[26]^x[25]^x[24]^x[23]^x[20]^x[18]^x[17]^x[14]^x[12]^x[11]^x[8]^x[4]^x[3]^x[1];

 bcc_next[13] = m[36]^x[30]^x[28]^x[26]^x[25]^x[23]^x[22]^x[20]^x[18]^x[17]^x[16]^x[15]^x[9]^x[8]^x[7]^x[6]^x[5]^x[3]^x[2]^x[1];

 bcc_next[12] = m[32]^m[35]^m[36]^x[31]^x[30]^x[28]^x[25]^x[22]^x[21]^x[20]^x[18]^x[17]^x[16]^x[14]^x[13]^x[11]^x[10]^x[9]^x[7]^x[4]^x[2];

 bcc_next[11] = m[32]^m[34]^m[35]^m[36]^x[28]^x[21]^x[18]^x[17]^x[16]^x[12]^x[11]^x[5]^x[3]^x[0];

 bcc_next[10] = m[33]^m[34]^m[35]^x[31]^x[27]^x[20]^x[17]^x[16]^x[15]^x[11]^x[10]^x[4]^x[2];

 bcc_next[9] = m[33]^m[34]^m[36]^x[31]^x[29]^x[28]^x[27]^x[26]^x[24]^x[20]^x[18]^x[16]^x[14]^x[13]^x[11]^x[8]^x[6]^x[5]^x[3]^x[0];

 bcc_next[8] = m[33]^m[35]^m[36]^x[31]^x[29]^x[26]^x[25]^x[24]^x[23]^x[20]^x[18]^x[17]^x[12]^x[11]^x[9]^x[8]^x[7]^x[6]^x[4]^x[2]^x[1]^x[0];

 bcc_next[7] = m[32]^m[34]^m[35]^x[30]^x[28]^x[25]^x[24]^x[23]^x[22]^x[19]^x[17]^x[16]^x[11]^x[10]^x[8]^x[7]^x[6]^x[5]^x[3]^x[1]^x[0];

 bcc_next[6] = m[32]^m[33]^m[34]^m[36]^x[30]^x[28]^x[23]^x[22]^x[21]^x[20]^x[19]^x[16]^x[13]^x[11]^x[8]^x[7]^x[4]^x[2]^x[1];

 bcc_next[5] = m[33]^m[35]^m[36]^x[30]^x[28]^x[24]^x[22]^x[21]^x[13]^x[12]^x[11]^x[9]^x[8]^x[7]^x[5]^x[3];

 bcc_next[4] = m[34]^m[35]^m[36]^x[31]^x[30]^x[28]^x[24]^x[23]^x[21]^x[19]^x[18]^x[15]^x[13]^x[12]^x[9]^x[7]^x[5]^x[4]^x[2]^x[1]^x[0];

 bcc_next[3] = m[32]^m[33]^m[34]^m[35]^m[36]^x[31]^x[28]^x[24]^x[23]^x[22]^x[19]^x[17]^x[15]^x[14]^x[13]^x[12]^x[10]^x[9]^x[5]^x[4]^x[3];

 bcc_next[2] = m[32]^m[33]^m[34]^m[35]^x[31]^x[30]^x[27]^x[23]^x[22]^x[21]^x[18]^x[16]^x[14]^x[13]^x[12]^x[11]^x[9]^x[8]^x[4]^x[3]^x[2];

 bcc_next[1] = m[32]^m[33]^m[34]^x[31]^x[30]^x[29]^x[26]^x[22]^x[21]^x[20]^x[17]^x[15]^x[13]^x[12]^x[11]^x[10]^x[8]^x[7]^x[3]^x[2]^x[1];

 bcc_next[0] = m[32]^m[33]^x[31]^x[30]^x[29]^x[28]^x[25]^x[21]^x[20]^x[19]^x[16]^x[14]^x[12]^x[11]^x[10]^x[9]^x[7]^x[6]^x[2]^x[1]^x[0];

end
endfunction

function [7:0] bit_revers8;
  input [7:0] din8;
  begin
      bit_revers8[0] = din8[7];
      bit_revers8[1] = din8[6];
      bit_revers8[2] = din8[5];
      bit_revers8[3] = din8[4];
      bit_revers8[4] = din8[3];
      bit_revers8[5] = din8[2];
      bit_revers8[6] = din8[1];
      bit_revers8[7] = din8[0];
  end
endfunction



endmodule
