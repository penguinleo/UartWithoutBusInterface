// -----------------------------------------------------------------------------
// Copyright (c) 2019-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author   :   Javen Peng, pengjaven@gmail.com
// File     :   ShiftRegister.v
// Create   :   2019-10-21 11:37:45
// Revise   :   2019-10-21 11:37:45
// Editor   :   sublime text3, tab size (4)
// Comment  :   the shift register receive the data from the fifo and send out it bit by bit 
//              at the beats from the FSM. This module control the tx wire signal.
// Input Signal List:
//      1   :   clk, the system input clock signal, the frequency is greater than 40MHz
//      2   :   rst, the system reset signal, the module should be reset asynchronously,
//                   and must be released synchronously with the clock; 
//      3   :   p_BaudSig_i, the Baudrate signal send from the Baudrate module to synchronized
//                           different module;
//      4   :   State_i, the global state machine, controled by the FSM module;
//      5   :   BitCounter_i, the bit index of the shift register, this register was controlled by the FSM
//      6   :   FifoData_i, the interface with the send FIFO module, to get the data
//      7   :   p_FiFoEmpty_i, the FIFO empty signal, 1-empty, 0-nonempty
//      8   :   p_BigEnd_i, the big end mode,
//                          1- the high bit send first
//                          2- the low bit send first
//      9   :   ParityMethod_i, the parity method
// Output Signal List:
//      1   :   n_FifoRe_o, the FIFO read signal, active low.
//      2   :   ShiftData_o, the data in the shift register, could be synthesised
//      3   :   SerialData_o, the bit data sent out by the shift register module, it is the uart tx port output
//      4   :   p_ParityCalTrigger_w, the trigger signal to calculate the parity
// -----------------------------------------------------------------------------
module ShiftRegister(
    input           clk,
    input           rst,
    // interface with the baudrate module
    input           p_BaudSig_i,
    // interface with the fsm
    input   [4:0]   State_i,
    input   [3:0]   BitCounter_i,
    // interface with the fifo output
    output          n_FifoRe_o,
    input   [7:0]   FifoData_i,
    input           p_FiFoEmpty_i,
    // interface with the inner module
    input           p_BigEnd_i,
    input           ParityMethod_i,
    output  [7:0]   ShiftData_o,
    output          SerialData_o
    );
    // register definition
        // Fifo interface register
            reg [1:0]   n_fifo_rd_r;
        // inner module interface register
            reg [7:0]   shift_reg_r;
            reg         serial_data_r;
        // 
    // wire definition
        wire    fifo_re_rising_w; // FIFO RE signal should be 1 when this signal is 1
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
        // Big end and littel end definition
            parameter BIGEND    = 1'b1;
            parameter LITTLEEND = 1'b0;
        // Bit name definition
            parameter BIT0      = 4'd0;
            parameter BIT1      = 4'd1;
            parameter BIT2      = 4'd2;
            parameter BIT3      = 4'd3;
            parameter BIT4      = 4'd4;
            parameter BIT5      = 4'd5;
            parameter BIT6      = 4'd6;
            parameter BIT7      = 4'd7;
        // parity method definition
            parameter EVEN      = 1'b0;
            parameter ODD       = 1'b1;
    // assignment
        // output assign
            assign n_FifoRe_o   = n_fifo_rd_r[0];
            assign ShiftData_o  = shift_reg_r;
            assign SerialData_o = serial_data_r;
        // the fifo re rising time
            assign fifo_re_rising_w     =   (State_i == INTERVAL)           
                                        &   (p_FiFoEmpty_i == NONEMPTY)
                                        &   (p_BaudSig_i == 1'b1);              // same condition with the FSM INTERVAL to STARTBIT
    // rd signal generate module
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                n_fifo_rd_r <= 2'b11;                
            end
            else if (fifo_re_rising_w == 1'b1) begin
                n_fifo_rd_r <= {n_fifo_rd_r[0],1'b0};
            end
            else begin
                n_fifo_rd_r <= {n_fifo_rd_r[0],1'b1};
            end
        end
    // shift register fresh module
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                shift_reg_r <= 7'd0;                
            end
            else if (n_fifo_rd_r[1] == 1'd0) begin
                shift_reg_r <= FifoData_i;
            end
        end
    // serial register output module
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                serial_data_r <= 1'b1;                   
            end
            else if (State_i == STARTBIT) begin
                serial_data_r <= 1'b0;
            end
            else if (State_i == DATABITS) begin
                if (p_BigEnd_i == BIGEND) begin   // the high bit send first
                    case(BitCounter_i)
                        BIT0:   serial_data_r <= shift_reg_r[7];
                        BIT1:   serial_data_r <= shift_reg_r[6];
                        BIT2:   serial_data_r <= shift_reg_r[5];
                        BIT3:   serial_data_r <= shift_reg_r[4];
                        BIT4:   serial_data_r <= shift_reg_r[3];
                        BIT5:   serial_data_r <= shift_reg_r[2];
                        BIT6:   serial_data_r <= shift_reg_r[1];
                        BIT7:   serial_data_r <= shift_reg_r[0];
                        default:serial_data_r <= 1'b0;
                    endcase
                end
                else begin                         // the low bit send first
                    case(BitCounter_i)
                        BIT0:   serial_data_r <= shift_reg_r[0];
                        BIT1:   serial_data_r <= shift_reg_r[1];
                        BIT2:   serial_data_r <= shift_reg_r[2];
                        BIT3:   serial_data_r <= shift_reg_r[3];
                        BIT4:   serial_data_r <= shift_reg_r[4];
                        BIT5:   serial_data_r <= shift_reg_r[5];
                        BIT6:   serial_data_r <= shift_reg_r[6];
                        BIT7:   serial_data_r <= shift_reg_r[7];
                        default:serial_data_r <= 1'b0;
                    endcase
                end
            end
            else if (State_i == PARITYBIT) begin
                if (ParityMethod_i == EVEN) begin
                    serial_data_r <= ^shift_reg_r;
                end
                else begin
                    serial_data_r <= ~(^shift_reg_r);
                end
            end
            else if (State_i == STOPBIT) begin
                serial_data_r <= 1'b1;
            end
            else begin
                serial_data_r <= 1'b1;
            end
        end


endmodule
    