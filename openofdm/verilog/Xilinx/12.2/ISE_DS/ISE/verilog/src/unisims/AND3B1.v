// $Header: /devl/xcs/repo/env/Databases/CAEInterfaces/verunilibs/data/unisims/AND3B1.v,v 1.6 2007/05/23 21:43:33 patrickp Exp $
///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995/2004 Xilinx, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor : Xilinx
// \   \   \/     Version : 10.1
//  \   \         Description : Xilinx Functional Simulation Library Component
//  /   /                  3-input AND Gate
// /___/   /\     Filename : AND3B1.v
// \   \  /  \    Timestamp : Thu Mar 25 16:42:12 PST 2004
//  \___\/\___\
//
// Revision:
//    03/23/04 - Initial version.
//    05/23/07 - Changed timescale to 1 ps / 1 ps.
//    05/23/07 - Added wire declaration for internal signals.

`timescale  1 ps / 1 ps


module AND3B1 (O, I0, I1, I2);

    output O;

    input  I0, I1, I2;

    wire i0_inv;

    not N0 (i0_inv, I0);
    and A1 (O, i0_inv, I1, I2);


endmodule

