// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen   penguinleo@163.com
// File   : FSM_Rx.v
// Create : 2019-12-02 20:55:52
// Revise : 2019-12-02 20:55:52
// Editor : sublime text3, tab size (4)
// Comment: this module is designed to control the UART rx core. The Rx core would acquisite the rx signal
//          wire at the frequency which is 16 times of baudrate signal.
//          The state definition is described as below.
//          INTERVAL    :   It is an idle state, that there is not data on the wire. Once the level
//                          once the signal wire is pulled down, the state machine should move to Startbit
// 							This state better last at least 1 bit time. But considering the asynchronous equipments,
// 							the receiving core should be ready, in other words, the receiving core could be sychronized
// 							at any time in the INTERVAL state, regardless the state hold time. Be carefull
//          STARTBIT    :   It is the start bit of the byte, always 0. This state would jump to data bits state 
// 							once the ShiftRegister_Rx give out Bit_Synch_i signal, which means the bit has finished passing.
// 			DATABITS 	: 	In this state, the rx core is receiving the data bit of a bytes, each Bit_Synch_i signal
// 							means the ending of one data bit and the bit counter regisnter would gain.
// 			PARITYBIT	:	It is the parity bit of the Byte state
// 			STOPBIT		:	Each bytes must contain at leat 1bit stop bits.
//          Up module:
//              RxCore.v
//          Sub module:
//              -----
// Input Signal List:
//      1   |   clk         	:   clock signal
//      2   |   rst         	:   reset signal
//      3   |   p_Enable_i      :   Module enable signal, which would lock the state machine at INTERVAL state
//      4   |   Rx_Synch_i		:	The sychronation signal at the beginning of each byte
// 		5	|	Bit_Synch_i 	:	The sychronation signal at the end of each bit, the state machine driver signal
// 		6	|	AcqSig_i		:	The Acquisition signal from the Baudrate Generate Module, same signal with the ShiftRegister_Rx input signal.
// 		7	|	ParityEnable_i	:	The Parity method control signal, from the control module
// Output Signal List:
//      1   |   State_o			:   The state machine output, define each bit in byte  
//		2 	|	BitCounter_o	:	In the data receiving state, this output applied to define the index of the data bit.  
// Note:  2019-12-05
//          1,  Consider some over time error detect to self recover from some unexpected error,
//              maybe watch dog is a good idea.
// -----------------------------------------------------------------------------
module FSM_Rx(
    // System signal definition
        input           clk,
        input           rst,
        input           p_Enable_i,
    // signal from ShiftRegister_Rx
        input           Rx_Synch_i,         // the triggle signal that a byte is running on the wire
        input           Bit_Synch_i,        // the bit in the byte has been received successfully
        input           StartBitErr_i,      // the start bit error signal
    // signal from the baudrate generate module
        input           AcqSig_i,
    // signal from the control register
        input           p_ParityEnable_i,
    // output of the FSM RX
        output [4:0]    State_o,            // Rx core state machine output 
        output [3:0]    BitCounter_o        // the bit counter output
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
        wire [4:0]      state_w; // triple mode result output
        wire [3:0]      bit_counter_w;
        // wire 			p_ParityCalTrigger_w;
    // parameter definition
        // state machine definition
            parameter INTERVAL  = 5'b0_0001;
            parameter STARTBIT  = 5'b0_0010;
            parameter DATABITS  = 5'b0_0100;
            parameter PARITYBIT = 5'b0_1000;
            parameter STOPBIT   = 5'b1_0000;
        // Parity Enable definition
            parameter ENABLE    = 1'b1;
            parameter DISABLE   = 1'b0;
    // wire assign
        assign state_w          = (state_A_r & state_B_r)
                                | (state_B_r & state_C_r)
                                | (state_C_r & state_A_r);
        assign bit_counter_w    = (bit_counter_A_r & bit_counter_B_r)
                                | (bit_counter_B_r & bit_counter_C_r)
                                | (bit_counter_C_r & bit_counter_A_r);
        assign State_o          = state_w;
        assign BitCounter_o 	= bit_counter_w;
        // assign p_ParityCalTrigger_o = p_ParityCalTrigger_w;
        // assign p_ParityCalTrigger_w = (Bit_Synch_i == 1'b1) && (bit_counter_w == 4'd8);
    // data bits counter module
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                bit_counter_A_r <= 4'd0;
                bit_counter_B_r <= 4'd0;
                bit_counter_C_r <= 4'd0;                
            end
            else if ((state_w == DATABITS) && (Bit_Synch_i != 1'b1)) begin
                bit_counter_A_r <= bit_counter_w;
                bit_counter_B_r <= bit_counter_w;
                bit_counter_C_r <= bit_counter_w;
            end
            else if ((state_w == DATABITS) && (Bit_Synch_i == 1'b1)) begin
                bit_counter_A_r <= bit_counter_A_r + 1'b1;
                bit_counter_B_r <= bit_counter_B_r + 1'b1;
                bit_counter_C_r <= bit_counter_C_r + 1'b1;
            end
            else begin
                bit_counter_A_r <= 4'd0;
                bit_counter_B_r <= 4'd0;
                bit_counter_C_r <= 4'd0;
            end
         end 
    // state machine module
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                state_A_r <= INTERVAL;                  
                state_B_r <= INTERVAL;
                state_C_r <= INTERVAL;              
            end
            else begin
                case(state_w)
                    INTERVAL: begin
                        if ((Rx_Synch_i == 1'b1) && (p_Enable_i == ENABLE)) begin
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
                    STARTBIT: begin
                        if ((Bit_Synch_i == 1'b1) && (StartBitErr_i == 1'b0)) begin
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
                    DATABITS: begin
                        if ((Bit_Synch_i == 1'b1) && (bit_counter_w == 4'd7) && (p_ParityEnable_i == ENABLE)) begin
                            state_A_r <= PARITYBIT;
                            state_B_r <= PARITYBIT;
                            state_C_r <= PARITYBIT; 
                        end
                        else if ((Bit_Synch_i == 1'b1) && (bit_counter_w == 4'd7) && (p_ParityEnable_i == DISABLE)) begin
                            state_A_r <= STOPBIT;
                            state_B_r <= STOPBIT;
                            state_C_r <= STOPBIT; 
                        end
                        else begin
                            state_A_r <= DATABITS;
                            state_B_r <= DATABITS;
                            state_C_r <= DATABITS;
                        end
                    end
                    PARITYBIT: begin
                        if (Bit_Synch_i == 1'b1) begin
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
                    STOPBIT: begin
                        if ((Rx_Synch_i == 1'b1)&&(p_Enable_i == ENABLE)) begin
                            state_A_r <= STARTBIT;                              
                            state_B_r <= STARTBIT;
                            state_C_r <= STARTBIT;
                        end
                        else if (Bit_Synch_i == 1'b1) begin
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
                    default: begin
                        state_A_r <= INTERVAL;                              
                        state_B_r <= INTERVAL;
                        state_C_r <= INTERVAL;
                    end
                endcase
            end
        end
endmodule