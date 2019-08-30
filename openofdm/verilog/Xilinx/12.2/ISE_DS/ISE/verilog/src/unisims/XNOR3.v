// $Header: /devl/xcs/repo/env/Databases/CAEInterfaces/verunilibs/data/unisims/XNOR3.v,v 1.6 2007/05/23 21:43:44 patrickp Exp $
///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995/2004 Xilinx, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor : Xilinx
// \   \   \/     Version : 10.1
//  \   \         Description : Xilinx Functional Simulation Library Component
//  /   /                  3-input XNOR Gate
// /___/   /\     Filename : XNOR3.v
// \   \  /  \    Timestamp : Thu Mar 25 16:43:42 PST 2004
//  \___\/\___\
//
// Revision:
//    03/23/04 - Initial version.
//    05/23/07 - Changed timescale to 1 ps / 1 ps.

`timescale  1 ps / 1 ps


module XNOR3 (O, I0, I1, I2);

    output O;

    input  I0, I1, I2;

	xnor X1 (O, I0, I1, I2);


endmodule

