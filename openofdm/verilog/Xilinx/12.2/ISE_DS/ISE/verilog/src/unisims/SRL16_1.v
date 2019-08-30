// $Header: /devl/xcs/repo/env/Databases/CAEInterfaces/verunilibs/data/unisims/SRL16_1.v,v 1.8 2007/05/23 21:43:44 patrickp Exp $
///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995/2004 Xilinx, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor : Xilinx
// \   \   \/     Version : 10.1
//  \   \         Description : Xilinx Functional Simulation Library Component
//  /   /                  16-Bit Shift Register Look-Up-Table with Negative-Edge Clock
// /___/   /\     Filename : SRL16_1.v
// \   \  /  \    Timestamp : Thu Mar 25 16:43:40 PST 2004
//  \___\/\___\
//
// Revision:
//    03/23/04 - Initial version.

`timescale  1 ps / 1 ps


module SRL16_1 (Q, A0, A1, A2, A3, CLK, D);

    parameter INIT = 16'h0000;

    output Q;

    input  A0, A1, A2, A3, CLK, D;

    reg  [15:0] data;
    wire	clk_;


    assign Q = data[{A3, A2, A1, A0}];
    assign clk_ = ~CLK;

    initial
    begin
          assign  data = INIT;
          while (clk_ === 1'b1 || clk_ === 1'bX) 
            #10; 
          deassign data;
    end


    always @(posedge clk_)
    begin
	{data[15:0]} <= #100 {data[14:0], D};
    end


endmodule

