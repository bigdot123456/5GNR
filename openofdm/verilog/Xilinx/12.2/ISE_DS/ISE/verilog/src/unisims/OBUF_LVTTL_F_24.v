// $Header: /devl/xcs/repo/env/Databases/CAEInterfaces/verunilibs/data/unisims/OBUF_LVTTL_F_24.v,v 1.6 2007/05/23 21:43:41 patrickp Exp $
///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995/2004 Xilinx, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor : Xilinx
// \   \   \/     Version : 10.1
//  \   \         Description : Xilinx Functional Simulation Library Component
//  /   /                  Output Buffer with LVTTL I/O Standard Fast Slew 24 mA Drive
// /___/   /\     Filename : OBUF_LVTTL_F_24.v
// \   \  /  \    Timestamp : Thu Mar 25 16:43:27 PST 2004
//  \___\/\___\
//
// Revision:
//    03/23/04 - Initial version.
//    05/23/07 - Changed timescale to 1 ps / 1 ps.

`timescale  1 ps / 1 ps


module OBUF_LVTTL_F_24 (O, I);

    output O;

    input  I;

    tri0 GTS = glbl.GTS;

    bufif0 B1 (O, I, GTS);


endmodule

