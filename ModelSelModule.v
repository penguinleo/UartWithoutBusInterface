// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen   penguinleo@163.com
// File   : ModelSelModule.v
// Create : 2020-08-11 11:48:15
// Revise : 2020-08-11 11:48:15
// Editor : sublime text3, tab size (4)
// Comment: This module is a logic definition moudle for the UART module work mode select.
//          different mode value set would make the uart module in normal mode, auto-echo, local loopback
//          remote looback.
//          Up module:
//              
//          Sub module:
//             
// Input Signal List:
//      1   |   CLK                 :   clock signal
//      2   |   RST                 :   reset signal
//      3   |   ModeSelected_i[3:0] :   Mode selecte information from the control core module
//      4   |   TxPort_o            :   the
// Output Signal List:      
//      1   |                                                                                            
// Note:  
// -----------------------------------------------------------------------------   
module ModelSelModule (
    input clk,    // Clock
    input rst,  // Asynchronous reset active low
    // interface with the Control module
        input [3:0]     ModeSelected_i,
    // interface with the hardware IO port
        output          TxPort_o,
        input           RxPort_i,
    // interface with the Rx module
        output          RxModulePort_o,
    // interface with the Tx module
        input           TxModulePort_i 
);
    // parameter definition
        // ModeSel  --UartMode Definition 
            parameter   UartMode_NORMAL             = 4'b0001;    // Normal mode, tx port sends data and rx port receives data
            parameter   UartMode_AUTO_ECHO          = 4'b0010;    // Automatic echo mode, rx port receives data and transfer to tx port
            parameter   UartMode_LOCAL_LOOPBACK     = 4'b0100;    // Local loop-back mode, rx port connected to the tx port directly would not send out
            parameter   UartMode_REMOTE_LOOPBACK    = 4'b1000;    // Remote loop-back mode, the input io and output io of uart was connected directly  
    // output logic assign
        assign TxPort_o         =   (ModeSelected_i == UartMode_NORMAL)         ? TxModulePort_i    :
                                    (ModeSelected_i == UartMode_AUTO_ECHO)      ? RxPort_i          :
                                    (ModeSelected_i == UartMode_LOCAL_LOOPBACK) ? 1'b1              :
                                    (ModeSelected_i == UartMode_REMOTE_LOOPBACK)? RxPort_i          :
                                    1'b1;
        assign RxModulePort_o   =   (ModeSelected_i == UartMode_NORMAL)         ? RxPort_i          :
                                    (ModeSelected_i == UartMode_AUTO_ECHO)      ? RxPort_i          :
                                    (ModeSelected_i == UartMode_LOCAL_LOOPBACK) ? TxModulePort_i    :
                                    (ModeSelected_i == UartMode_REMOTE_LOOPBACK)? 1'b1              :
                                    1'b1;

endmodule