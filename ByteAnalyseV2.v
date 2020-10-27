// -----------------------------------------------------------------------------
// Copyright (c) 2014-2020 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen Peng, pengjaven@gmail.com
// File   : ByteAnalyseV2.v
// Create : 2020-01-26 17:14:16
// Revise : 2020-01-26 21:52:30
// Editor : sublime text3, tab size (4)
// Comment: This module function:
//          1, Byte data anlayse;
//          2, Time stamp generate;
//          3, Send byte data into the fifo
//          This module is independent with the Rx core state machine. The state machine of this module is as below
//              IDLE    :       The analyse module waiting for the Rx core trigger the  opperation. 
//              BUFF    :       Once trigger this state machine, this module would buffer the input data from the 
//                              shift register
//              PARR    :       In this state this module would trigger the parity calculate module generate the 
//                              parity result. And the big end or little end style would be checked.
//              CHCK    :       In this state this module compare the parity calculate result and the received 
//                              parity bit.
//              FIFO    :       In this state this module would send the data into the fifo according to the parity
//                              check result.
//          Above are the basic function of this module.
//              This module would counting the byte interval by the baudsig.
//              The byte interval in one frame should less than 16.5 baudrate time.
//              The interval between two consecutive frames should less than 55 baudrate time.
//              When a new frame was recognized, the old frame information would be send to the frame info register.
// Input Signal List:
//      1   :   clk,                        :   the system input clock signal, the frequency is greater than 40MHz
//      2   :   rst,                        :   the system reset signal, the module should be reset asynchronously,
//                                              and must be released synchronously with the clock;
//      3   :   p_full_i,                   :   the receive fifo full signal, positive is full;
//      4   :   BaudSig_i,                  :   the baudrate signal
//      5   :   byte_i[11:0]                :   the byte data from the shift register, acquisited from the rx wire;
//      7   :   Byte_Synch_i                :   the byte synchronouse signal, generated in the stop bit acquisite
//                                              point.
//      9   :   acqurate_stamp_i[3:0]       :   The time stamp(0.1ms) from other module. The equivalent of this data 
//                                              is 0.1ms. The range of data is 0 ~ 9;
//      10  :   millisecond_stamp_i[11:0]   :   The time stamp(millisecond) from other module. The equivalent of this
//                                              data is 1ms. The range of this data is 0 ~ 999;
//      11  :   second_stamp_i[31:0]        :   The time stamp(second) from other module. The equivalent of this data
//                                              is sencond. The range of this data is 0 ~ ‭4294967295‬  
//      12  :   p_ParityEnable_i            :   The parity enable control,When this signal is high, the parity function 
//                                              is the receive core is enabled, the byte analyse module would check the 
//                                              parity bit.
//      13  :   p_BigEnd_i                  :   Big end sending, When it is high, that means the bits in the byte would 
//                                              be sent on the tx wire from bit 7 to bit 0, bit by bit. In contrast, 
//                                              the bits would be sent on the wire from bit 0 to bit 7.
//      14  :   n_rd_frame_fifo_i           :   This module could analyse the seperate the data into fram, and give out 
//                                              the frame timestamp and frame length. This signal is the read signal, 
//                                              when it is active(low), the module would send out the oldest frame info
//                                              and shift other info. The maximum fifo info number is 4.
//      15  :   ParityResult_i              :   The parity result from the parity calculate module. This module would 
//                                              send out the trigger signal to the parity calculate module.
// Output Signal List:
//      1   :   n_we_o                      :   
// Note:
//      2020-02-16  This module should be seperated from the state machine of the Rx machine.
//                  The data process could compensate many clocks, thus the baudrate would be
//                  limited by the data processing module.
// -----------------------------------------------------------------------------
module ByteAnalyseV2(
    input   clk,
    input   rst,
    // the interface with fifo 
        output          n_we_o,
        output  [7:0]   data_o,
    // the interface with the baudrate module
        input           BaudSig_i,
    // the interface with shift register
        input   [11:0]  byte_i,
        input           Byte_Synch_i,
    // the interface with the Time Stamp Module
        input   [3:0]   acqurate_stamp_i,
        input   [11:0]  millisecond_stamp_i,
        input   [31:0]  second_stamp_i,
    // the control register
        input           p_ParityEnable_i,
        input           p_BigEnd_i,
    // the frame fifo interface
        input           n_rd_frame_fifo_i,
        output  [27:0]  frame_info_o,
    // the interface with the parity generator module
        output  [7:0]   ParityCalData_o,
        output          p_ParityCalTrigger_o,
        input           ParityResult_i,
    // status signal 
        output          p_ParityErr_o,    // Parity error status flag
        output          p_FrameErr_o,     // Stop bit missing flag
        output  [7:0]   ParityErrorNum_o
    );
    // register definition
        // state machine
            reg [4:0]       state_r;        // the state machine register of the module
            reg [11:0]      byte_r;   // the buffer for the input data
            reg             parity_trig_r;
            reg [2:0]       parity_result_r/*Synthesis syn_preserve = 1*/;
            reg [2:0]       frame_error_r/*Synthesis syn_preserve = 1*/;
            reg [7:0]       fifo_data_r;        // the data that sent to the fifo
            reg             n_we_r;             // the we signal of the fifo
            reg             n_rd_frame_fifo_r;  // 
            reg [2:0]       rd_frame_fifo_shift_r;
            reg [7:0]       parity_error_num_r; // the parity error number    

        // the time stamp
            reg [31:0]  t0_s_stamp_r;
            reg [11:0]  t0_ms_stamp_r;
            reg [3:0]   t0_100us_stamp_r;   
        // the frame info recognize register
            reg [7:0]   byte_interval_cnt_r;    // the frame interval counter
            reg [7:0]   byte_num_cnt_r;         // the frame byte number counter
            reg [3:0]   frame_num_cnt_r;        // indicate that how many frame left in the  fifo
            reg         new_frame_sig_r;        // indicate that this byte belong to another frame
        // Frame information buffer
            reg [27:0]  frame0_info_r;
            reg [27:0]  frame1_info_r;
            reg [27:0]  frame2_info_r;  
            reg [27:0]  frame3_info_r;
            reg [27:0]  frame_info_output_r;        
    // wire definition
        // control signal
            wire [7:0]  big_end_data_w; 
            wire [7:0]  little_end_data_w;  
            wire        start_bit_w;
            wire        parity_bit_w;
            wire        stop_bit_w;
            wire        falling_edge_rd_fifo_w;
            wire        parity_result_w;
            wire        frame_error_w;
        // Frame0 information definition
            wire [11:0] frame0_stamp_ms_w;
            wire [3:0]  frame0_stamp_us_w;
            wire [11:0] frame0_byte_num_w;
        // Frame3 information definition
            wire [11:0] frame3_stamp_ms_w;
            wire [3:0]  frame3_stamp_us_w;
            wire [11:0] frame3_byte_num_w;
    // parameter definition
        // State Machine definition
            parameter IDLE      = 5'b0_0001;    // the module is waiting the shiftregister module give out data
            parameter BUFF      = 5'b0_0010;    // the module is buffering the data and give out the time stamp
            parameter PARR      = 5'b0_0100;    // the module is checking the data according to the parity data
            parameter CHCK      = 5'b0_1000;    // the module recognizes the frame 
            parameter FIFO      = 5'b1_0000;    // the module should send out the data to the FIFO
        // The Byte interval definition
            parameter MAX_CNT_NUM           = 8'hff;
            parameter BYTE_CNT_NUM          = 8'd11;
            parameter FRAME_BYTE_INTERVAL   = BYTE_CNT_NUM + 8'd17;  // the byte interval in one frame should less than 16.5 baudrate time
            parameter FRAME_INTERVAL        = BYTE_CNT_NUM + 8'd55;  // the interval between two consecutive frames should less than 55 baudrate time
        // The frame definition
            parameter NEW_FRAME = 1'b1;
            parameter NOT_FINISH= 1'b0;
        // parity enable definition
            parameter ENABLE    = 1'b1;
            parameter DISABLE   = 1'b0;
        // Big end and littel end definition
            parameter BIGEND    = 1'b1;
            parameter LITTLEEND = 1'b0;
        // Parity check results
            parameter PAR_TRUE  = 1'b1;
            parameter PAR_FALSE = 1'b0;
        // Frame Error Chck
            parameter FRM_TRUE  = 1'b0;
            parameter FRM_FALSE = 1'b1; 
    // Logic definition
        // output logic definition
            assign ParityCalData_o      = byte_r[10:3];
            assign data_o               = fifo_data_r;
            assign p_ParityCalTrigger_o = parity_trig_r;
            assign n_we_o               = n_we_r;
            assign ParityErrorNum_o     = parity_error_num_r;
            assign p_ParityErr_o        = ~parity_result_w;
            assign p_FrameErr_o         = frame_error_w;
        // inner logic signal
            assign start_bit_w              = byte_r[11];
            assign little_end_data_w        = {
                                                byte_r[3],byte_r[4],byte_r[5],byte_r[6],
                                                byte_r[7],byte_r[8],byte_r[9],byte_r[10]
                                                };
            assign big_end_data_w           = {
                                                byte_r[10],byte_r[9],byte_r[8],byte_r[7],
                                                byte_r[6],byte_r[5],byte_r[4],byte_r[3]
                                                };
            assign parity_bit_w             = byte_r[2];
            assign stop_bit_w               = byte_r[1];
            assign parity_result_w          = (
                                                    (parity_result_r[0]&parity_result_r[1])
                                                ||  (parity_result_r[1]&parity_result_r[2])
                                                ||  (parity_result_r[2]&parity_result_r[0])
                                            );
            assign frame_error_w            = (
                                                    (frame_error_r[0]&frame_error_r[1])
                                                ||  (frame_error_r[1]&frame_error_r[2])
                                                ||  (frame_error_r[2]&frame_error_r[0])
                                            ) ;
        // Frame0 and Frame1 logic definition
            assign frame0_stamp_ms_w = frame0_info_r[17:16];
            assign frame0_stamp_us_w = frame0_info_r[15:12];
            assign frame0_byte_num_w = frame0_info_r[11:00];
            assign frame3_stamp_ms_w = frame3_info_r[17:16];
            assign frame3_stamp_us_w = frame3_info_r[15:12];
            assign frame3_byte_num_w = frame3_info_r[11:00];
            assign frame_info_o      = frame_info_output_r;
    // Basic function module
        // state machine
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    state_r <= IDLE;                
                end
                else begin
                    case(state_r)
                        IDLE:   begin
                            if (Byte_Synch_i == 1'b1) begin
                                state_r <= BUFF;
                            end
                            else begin
                                state_r <= IDLE;
                            end
                        end
                        BUFF:   begin
                            state_r <= PARR;
                        end
                        PARR:   begin
                            state_r <= CHCK;
                        end
                        CHCK:   begin
                            state_r <= FIFO;
                        end
                        FIFO:   begin
                            state_r <= IDLE;
                        end
                        default: begin
                            state_r <= IDLE;
                        end
                    endcase
                end
            end
        // byte_r buffer fresh module
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    // reset
                    byte_r <= 12'h000;
                end
                else if (Byte_Synch_i == 1'b1) begin
                    byte_r <= byte_i;
                end
                else begin
                    byte_r <= byte_r;
                end
            end
        // parity trigger sig register
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    parity_trig_r <= 1'b0;              
                end
                else if ((state_r == BUFF) && (p_ParityEnable_i == ENABLE)) begin
                    parity_trig_r <= 1'b1;
                end 
                else begin
                    parity_trig_r <= 1'b0;
                end
            end
        // fifo data output register fresh
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    fifo_data_r <= 8'd0;                
                end
                else if (state_r == PARR) begin
                    if (p_BigEnd_i == BIGEND) begin
                        fifo_data_r <= big_end_data_w;
                    end
                    else begin
                        fifo_data_r <= little_end_data_w;
                    end
                end
                else begin
                    fifo_data_r <= fifo_data_r;
                end
            end
        // parity results register
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    parity_result_r <= {PAR_TRUE,PAR_TRUE,PAR_TRUE};                
                end
                else if ((state_r == CHCK) && (p_ParityEnable_i == ENABLE)) begin
                    parity_result_r <= {
                        ParityResult_i ^ ~parity_bit_w,
                        ParityResult_i ^ ~parity_bit_w,
                        ParityResult_i ^ ~parity_bit_w
                    };
                end
                else if (p_ParityEnable_i == DISABLE) begin
                    parity_result_r <= {PAR_TRUE,PAR_TRUE,PAR_TRUE};
                end
                else begin
                    parity_result_r <= parity_result_r;
                end
            end
        // frame error detect register
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    frame_error_r <= {FRM_TRUE, FRM_TRUE, FRM_TRUE};                  
                end
                else if (state_r == CHCK) begin
                    frame_error_r <= {~stop_bit_w,~stop_bit_w,~stop_bit_w};   // if the stop bit != 1, error generate
                end 
                else begin
                    frame_error_r <= {frame_error_w,frame_error_w,frame_error_w};
                end
            end
        // FIFO operation
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    n_we_r <= 1'b1;             
                end
                else if ((state_r == FIFO) && (parity_result_w == PAR_TRUE) && (frame_error_w == FRM_TRUE)) begin
                    n_we_r <= 1'b0;
                end
                else begin
                    n_we_r <= 1'b1;
                end
            end
    // Advanced function module
        // Time stample 
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    t0_s_stamp_r        <= 32'd0;
                    t0_ms_stamp_r       <= 12'd0;
                    t0_100us_stamp_r    <= 4'd0;            
                end
                else if (Byte_Synch_i == 1'b1) begin
                    t0_s_stamp_r        <= second_stamp_i;
                    t0_ms_stamp_r       <= millisecond_stamp_i;
                    t0_100us_stamp_r    <= acqurate_stamp_i;
                end
                else begin
                    t0_s_stamp_r        <= t0_s_stamp_r;
                    t0_ms_stamp_r       <= t0_ms_stamp_r;
                    t0_100us_stamp_r    <= t0_100us_stamp_r;
                end
            end
        // Byte interval counter
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    byte_interval_cnt_r <= MAX_CNT_NUM;             
                end
                else if (Byte_Synch_i == 1'b1) begin
                    byte_interval_cnt_r <= 8'h00;
                end
                else if (BaudSig_i == 1'b1) begin
                    if (byte_interval_cnt_r == MAX_CNT_NUM) begin
                        byte_interval_cnt_r <= byte_interval_cnt_r;
                    end
                    else begin
                        byte_interval_cnt_r <= byte_interval_cnt_r + 1'b1;
                    end
                end
                else begin
                    byte_interval_cnt_r <= byte_interval_cnt_r;
                end
            end
        // frame recognize
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    new_frame_sig_r <= NOT_FINISH;              
                end
                else if (BaudSig_i == 1'b1) begin
                    if (byte_interval_cnt_r >= FRAME_BYTE_INTERVAL) begin
                        new_frame_sig_r <= NEW_FRAME;
                    end
                    else begin
                        new_frame_sig_r <= NOT_FINISH;
                    end
                end
                else begin
                    new_frame_sig_r <= new_frame_sig_r;
                end
            end         
        // byte number counter
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    byte_num_cnt_r <= 8'd0;     
                end
                else if (state_r == IDLE) begin
                    if (new_frame_sig_r == NEW_FRAME) begin
                        byte_num_cnt_r <= 8'd0;
                    end
                    else begin
                        byte_num_cnt_r <= byte_num_cnt_r;
                    end
                end
                else if (state_r == FIFO) begin
                    if (parity_result_w == PAR_TRUE) begin
                        byte_num_cnt_r <= byte_num_cnt_r + 1'b1;
                    end
                    else begin
                        byte_num_cnt_r <= byte_num_cnt_r;
                    end
                end
                else begin
                    byte_num_cnt_r <= byte_num_cnt_r;
                end
            end
        // shift register of n_rd_frame_fifo_i
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    rd_frame_fifo_shift_r <= 3'b111;                
                end
                else begin
                    rd_frame_fifo_shift_r <= {rd_frame_fifo_shift_r[1:0] , n_rd_frame_fifo_i};
                end
            end
        // n_rd_frame_fifo_r fresh
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    n_rd_frame_fifo_r <= 1'b1;              
                end
                else if (falling_edge_rd_fifo_w == 1'b1) begin
                    n_rd_frame_fifo_r <= 1'b0;
                end
                else begin
                    if (state_r != FIFO) begin  // FIFO state the rd sig is locked 
                        n_rd_frame_fifo_r <= 1'b1;
                    end
                    else begin
                        n_rd_frame_fifo_r <= n_rd_frame_fifo_r;
                    end
                end
            end
        // frame number counter 
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    frame_num_cnt_r <= 4'd0;                
                end
                else if (state_r == IDLE) begin
                    if ((new_frame_sig_r == NEW_FRAME) && (byte_num_cnt_r != 8'd0)) begin  //
                        if (frame_num_cnt_r >= 4'd4) begin
                            frame_num_cnt_r <= 4'd4;
                        end
                        else begin
                            frame_num_cnt_r <= frame_num_cnt_r + 1'b1;
                        end
                    end
                    else if ((n_rd_frame_fifo_r == 1'b0) && (frame_num_cnt_r != 4'd0)) begin
                        frame_num_cnt_r <= frame_num_cnt_r - 1'b1;
                    end
                    else begin
                        frame_num_cnt_r <= frame_num_cnt_r;
                    end
                end
                else begin
                    if ((n_rd_frame_fifo_r == 1'b0) && (frame_num_cnt_r != 4'd0)) begin
                        frame_num_cnt_r <= frame_num_cnt_r - 1'b1;
                    end
                    else begin
                        frame_num_cnt_r <= frame_num_cnt_r;
                    end
                end
            end
        // fram information buffer fresh
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    frame0_info_r <= 28'd0;
                    frame1_info_r <= 28'd0;
                    frame2_info_r <= 28'd0;
                    frame3_info_r <= 28'd0;     
                end
                else if (state_r == IDLE) begin  // in IDLE state the system finds the byte interval over the limit
                    if ((new_frame_sig_r == NEW_FRAME) && (byte_num_cnt_r != 8'd0)) begin
                        if (frame_num_cnt_r == 4'd0) begin
                            frame0_info_r <= {t0_100us_stamp_r,t0_ms_stamp_r,byte_num_cnt_r};
                            frame1_info_r <= 28'd0;
                            frame2_info_r <= 28'd0;
                            frame3_info_r <= 28'd0; 
                        end
                        else if (frame_num_cnt_r == 4'd1) begin
                            frame0_info_r <= frame0_info_r;
                            frame1_info_r <= {t0_100us_stamp_r,t0_ms_stamp_r,byte_num_cnt_r};
                            frame2_info_r <= 28'd0;
                            frame3_info_r <= 28'd0; 
                        end
                        else if (frame_num_cnt_r == 4'd2) begin
                            frame0_info_r <= frame0_info_r;
                            frame1_info_r <= frame1_info_r;
                            frame2_info_r <= {t0_100us_stamp_r,t0_ms_stamp_r,byte_num_cnt_r};
                            frame3_info_r <= 28'd0; 
                        end
                        else if (frame_num_cnt_r == 4'd3) begin // fifo is not full
                            frame0_info_r <= frame0_info_r;
                            frame1_info_r <= frame1_info_r;
                            frame2_info_r <= frame2_info_r;
                            frame3_info_r <= {t0_100us_stamp_r,t0_ms_stamp_r,byte_num_cnt_r};   
                        end
                        else begin   // when fifo if full
                            frame0_info_r <= frame1_info_r;
                            frame1_info_r <= frame2_info_r;
                            frame2_info_r <= frame3_info_r;
                            frame3_info_r <= {t0_100us_stamp_r,t0_ms_stamp_r,byte_num_cnt_r};
                        end
                    end
                    else if ((n_rd_frame_fifo_r == 1'b0) && (frame_num_cnt_r != 4'd0)) begin  // ouput frame info
                        frame0_info_r <= frame1_info_r;
                        frame1_info_r <= frame2_info_r;
                        frame2_info_r <= frame3_info_r;
                        frame3_info_r <= 28'd0;                     
                    end
                    else begin
                        frame0_info_r <= frame0_info_r;
                        frame1_info_r <= frame1_info_r;
                        frame2_info_r <= frame2_info_r;
                        frame3_info_r <= frame3_info_r;
                    end
                end
                else begin
                    if ((n_rd_frame_fifo_i == 1'b0) && (frame_num_cnt_r != 4'd0)) begin
                        frame0_info_r <= frame1_info_r;
                        frame1_info_r <= frame2_info_r;
                        frame2_info_r <= frame3_info_r;
                        frame3_info_r <= 28'd0;
                    end
                    else begin
                        frame0_info_r <= frame0_info_r;
                        frame1_info_r <= frame1_info_r;
                        frame2_info_r <= frame2_info_r;
                        frame3_info_r <= frame3_info_r;
                    end
                end
            end
        // frame_info_output_r frame info fifo output port
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    frame_info_output_r <= 28'd0;               
                end
                else if (state_r == IDLE) begin
                    if ((new_frame_sig_r == NEW_FRAME) && (byte_num_cnt_r != 8'd0)) begin  //
                        frame_info_output_r <= frame_info_output_r;
                    end
                    else if ((n_rd_frame_fifo_r == 1'b0) && (frame_num_cnt_r != 4'd0)) begin
                        frame_info_output_r <= frame0_info_r;
                    end
                    else begin
                        frame_info_output_r <= frame_info_output_r;
                    end
                end
                else begin
                    if ((n_rd_frame_fifo_r == 1'b0) && (frame_num_cnt_r != 4'd0)) begin
                        frame_info_output_r <= frame0_info_r;
                    end
                    else begin
                        frame_info_output_r <= frame_info_output_r;
                    end
                end
            end
        // parity error number counter
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    parity_error_num_r <= 8'd0;             
                end
                else if ((state_r == FIFO) && (parity_result_w == PAR_FALSE)) begin
                    parity_error_num_r <= parity_error_num_r + 1'b1;
                end
                else begin
                    parity_error_num_r <= parity_error_num_r;
                end
            end
endmodule