// -----------------------------------------------------------------------------
// Copyright (c) 2019-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author   :   Javen Peng, pengjaven@gmail.com
// File     :   FSM.v
// Create   :   2019-10-18 10:06:59
// Revise   :   2019-10-18 10:06:59
// Editor   :   sublime text3, tab size (4)
// Comment  :   This module is the state machine of the txcore, the upper module of this module is the TxCore. 
//              The state machine is designed according to the protocol of serial transmitting.
//              INTERVAL :  it is the idle state, the interval time between two bytes, or waiting for the upper module send data into the fifo
//                          the next state is the STARTBIT if the statement is satisfied, or the INTERVAL otherwise.
//              STARTBIT :  when the fifo is not empty, the state machine would step into the startbit state, that means the txcore
//                          would set the tx signal low for a bit time. at the same time the txcore should read the fifo and get the 
//                          data which need to be sent.
//                          the next state is DATABITS, the state transfer is triggered by the positive of BaudSig.
//              DATABITS :  when start bit time is passed, the tx core would send out the byte bit by bit. This state would last until 
//                          all data bits are send. The BitCounter register would help the core to identify the index of the bit. The 
//                          data bit shift is controlled by the BaudSig. When BaudSig is positive, the tx wire would setup the next data 
//                          bit, at the same time, the BitCounter would gain.
//                          The next state if the PARITYBIT when the parity bit function was enabled, or the STOPBIT when the parity function
//                          is disabled.
//              PARITYBIT:  in this state the parity bit is sending on the tx wire.
//              STOPBIT  :  the last bit sent on the tx wire, After the parity bit, when the parity function is enabled or the last bit of the 
//                          data bit.
// Input Signal List:
//      1   :   clk, the system input clock signal, the frequency is greater than 40MHz
//      2   :   rst, the system reset signal, the module should be reset asynchronously,
//                   and must be released synchronously with the clock; 
//      3   :   p_Enable_i, the module enable signal, which could lock the state machine at the INTERVAL state
//      3   :   p_BaudSig_i, the baudrate signal from the baudrate module to drive the FSM.
//                   this signal only last 1 clk.
//      4   :   p_FiFoEmpty_i, the empty signal of the fifo, if not empty the FSM start. 
//      5   :   ParityEnable_i, the parity enable control bit. 
// Output Signal List:
//      1   :   State_o[4:0], the state machine output
//      2   :   p_ParityCalTrigger_o, the trigger signal for the parity calculate module to start the parity calculate
//      3   :   BitCounter_o[3:0], indicate the index of the data bit which is on the tx wire.
// 
// -----------------------------------------------------------------------------
module FSM(
    input           clk,
    input           rst,
    input           p_Enable_i,
    input           p_BaudSig_i,
    input           p_FiFoEmpty_i,
    input           ParityEnable_i,
    // output          p_ParityCalTrigger_o,
    output [4:0]    State_o,
    output [3:0]    BitCounter_o
    );
    // register definition
        // state machine register
            reg [4:0]   state_A_r/*synthesis syn_preserve=1*/;    // the state machine
            reg [4:0]   state_B_r/*synthesis syn_preserve=1*/;
            reg [4:0]   state_C_r/*synthesis syn_preserve=1*/;
        // bit counter
            reg [3:0]   bit_counter_A_r/*synthesis syn_preserve=1*/;  // bit counter
            reg [3:0]   bit_counter_B_r/*synthesis syn_preserve=1*/;
            reg [3:0]   bit_counter_C_r/*synthesis syn_preserve=1*/;
    // wire definition
        // state machine 
            wire [4:0]  state_w;   //triple mode output
        // bit counter 
            wire [3:0]  bit_counter_w;
        // trigger for parity calculate
            wire        p_ParityCalTrigger_w;
    // parameter definition
        // state machine definition
            parameter INTERVAL  = 5'b0_0001;
            parameter STARTBIT  = 5'b0_0010;
            parameter DATABITS  = 5'b0_0100;
            parameter PARITYBIT = 5'b0_1000;
            parameter STOPBIT   = 5'b1_0000;
        // fifo state definition
            parameter EMPTY     = 1'b1;
            parameter NONEMPTY  = 1'b0;
        // parity enable definition
            parameter ENABLE    = 1'b1;
            parameter DISABLE   = 1'b0;
        // data bit number
            parameter BITNUMBER = 4'd7;
    // wire assign
        assign state_w          = (state_A_r & state_B_r) 
                                | (state_B_r & state_C_r) 
                                | (state_C_r & state_A_r);
        assign bit_counter_w    = (bit_counter_A_r & bit_counter_B_r) 
                                | (bit_counter_B_r & bit_counter_C_r) 
                                | (bit_counter_C_r & bit_counter_A_r);
        assign BitCounter_o     = bit_counter_w;
        assign State_o          = state_w;
        // assign p_ParityCalTrigger_o = p_ParityCalTrigger_w;
        // assign p_ParityCalTrigger_w = (state_w == DATABITS) && (bit_counter_w == 4'd0) && (p_BaudSig_i == 1'b1);
    // data bits counter module
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                bit_counter_A_r <= 4'd0;
                bit_counter_B_r <= 4'd0;
                bit_counter_C_r <= 4'd0;                
            end
            else if (state_w == DATABITS & p_BaudSig_i == 1'b1) begin
                bit_counter_A_r <= bit_counter_A_r + 1'b1;
                bit_counter_B_r <= bit_counter_B_r + 1'b1;
                bit_counter_C_r <= bit_counter_C_r + 1'b1;
            end
            else if (state_w == DATABITS & p_BaudSig_i == 1'b0) begin
                bit_counter_A_r <= bit_counter_A_r;
                bit_counter_B_r <= bit_counter_B_r;
                bit_counter_C_r <= bit_counter_C_r;
            end
            else begin
                bit_counter_A_r <= 4'd0;
                bit_counter_B_r <= 4'd0;
                bit_counter_C_r <= 4'd0;
            end
        end
    // FSM always module
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                state_A_r <= INTERVAL;
                state_B_r <= INTERVAL;
                state_C_r <= INTERVAL;                
            end
            else begin
                case(state_w)
                    INTERVAL:   begin
                        if (p_FiFoEmpty_i == NONEMPTY & p_BaudSig_i == 1'b1 & p_Enable_i == ENABLE) begin
                            state_A_r <= STARTBIT;
                            state_B_r <= STARTBIT;
                            state_C_r <= STARTBIT;
                        end
                        else begin
                            state_A_r <= INTERVAL;                            
                            state_B_r <= INTERVAL;
                            state_C_r <= INTERVAL;                            
                        end
                    end
                    STARTBIT:   begin
                        if (p_BaudSig_i == 1'b1) begin
                            state_A_r <= DATABITS;
                            state_B_r <= DATABITS;
                            state_C_r <= DATABITS;
                        end
                        else begin
                            state_A_r <= STARTBIT;                            
                            state_B_r <= STARTBIT;
                            state_C_r <= STARTBIT;                            
                        end
                    end
                    DATABITS:   begin
                        if ((bit_counter_w >= BITNUMBER) & (p_BaudSig_i == 1'b1) & (ParityEnable_i == ENABLE)) begin
                            state_A_r <= PARITYBIT;
                            state_B_r <= PARITYBIT;
                            state_C_r <= PARITYBIT;
                        end
                        else if ((bit_counter_w >= BITNUMBER) & (p_BaudSig_i == 1'b1) & (ParityEnable_i == DISABLE)) begin
                            state_A_r <= STOPBIT;
                            state_B_r <= STOPBIT;
                            state_C_r <= STOPBIT;
                        end
                        // else if ((bit_counter_w < BITNUMBER) & (p_BaudSig_i == 1'b1)) begin
                        //     state_A_r <= DATABITS;
                        //     state_B_r <= DATABITS;
                        //     state_C_r <= DATABITS;
                        // end
                        else begin
                            state_A_r <= DATABITS;                            
                            state_B_r <= DATABITS;
                            state_C_r <= DATABITS;   
                        end
                    end
                    PARITYBIT:  begin
                        if (p_BaudSig_i == 1'b1) begin
                            state_A_r <= STOPBIT;
                            state_B_r <= STOPBIT;
                            state_C_r <= STOPBIT;
                        end
                        else begin
                            state_A_r <= PARITYBIT;
                            state_B_r <= PARITYBIT;
                            state_C_r <= PARITYBIT;
                        end
                    end
                    STOPBIT:    begin
                        if (p_BaudSig_i == 1'b1) begin
                            state_A_r <= INTERVAL;
                            state_B_r <= INTERVAL;
                            state_C_r <= INTERVAL;
                        end
                        else begin
                            state_A_r <= STOPBIT;
                            state_B_r <= STOPBIT;
                            state_C_r <= STOPBIT;
                        end
                    end
                    default:    begin
                        state_A_r <= INTERVAL;                        
                        state_B_r <= INTERVAL;
                        state_C_r <= INTERVAL;                        
                    end
                endcase
            end
        end
endmodule
