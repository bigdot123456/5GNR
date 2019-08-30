// $Header: /devl/xcs/repo/env/Databases/CAEInterfaces/verunilibs/data/unisims/IOBUF_HSTL_I.v,v 1.6 2007/05/23 21:43:37 patrickp Exp $
///////////////////////////////////////////////////////////////////////////////
// Copyright (c) 1995/2004 Xilinx, Inc.
// All Right Reserved.
///////////////////////////////////////////////////////////////////////////////
//   ____  ____
//  /   /\/   /
// /___/  \  /    Vendor : Xilinx
// \   \   \/     Version : 10.1
//  \   \         Description : Xilinx Functional Simulation Library Component
//  /   /                  Bi-Directional Buffer with HSTL_I I/O Standard
// /___/   /\     Filename : IOBUF_HSTL_I.v
// \   \  /  \    Timestamp : Thu Mar 25 16:42:39 PST 2004
//  \___\/\___\
//
// Revision:
//    03/23/04 - Initial version.
//    05/23/07 - Changed timescale to 1 ps / 1 ps.
//    05/23/07 - Added wire declaration for internal signals.

`timescale  1 ps / 1 ps


module IOBUF_HSTL_I (O, IO, I, T);

    output O;

    inout  IO;

    input  I, T;

    wire ts;

    tri0 GTS = glbl.GTS;

    or O1 (ts, GTS, T);
    bufif0 T1 (IO, I, ts);

    buf B1 (O, IO);


endmodule

