// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen   penguinleo@163.com
// File   : FIFO_ver2.v
// Create : 2020-06-22 17:06:18
// Revise : 2020-06-22 17:06:18
// Editor : sublime text3, tab size (4)
// Comment  :   this fifo was built in the module the interface is similar with the 
//              IP core from the Xilinx Zynq
// 
// Input Signal List:
//      1   :   clk,    the system input clock signal, the frequency is greater than 40MHz
//      2   :   rst,    the system reset signal, the module should be reset asynchronously,
//                      and must be released synchronously with the clock;
//      3   :   data_i, the data input 
//      4   :   n_we_i, write signal
//      5   :   n_re_i, read signal
//      6   :   n_clr_i,the fifo clear signal, it is a synchronouse signal.
// Output Signal List:
//      1   :   data_o, the data output
//      2   :   empty_o,  the fifo empty signal
//      3   :   full_o, the fifo full signal
// -----------------------------------------------------------------------------

module  FIFO_ver2
#(
    parameter DATA_WIDTH = 8,   // the data width of the fifo
    parameter DEPTH = 4096      // the number of data in the fifo
    )
(
    input           clk,
    input           rst,
    input [7:0]     data_i,
    input           n_we_i,
    input           n_re_i,
    input           n_clr_i,
    output [7:0]    data_o,
    output [15:0]   bytes_in_fifo_o,
    output          p_over_o,
    output          p_full_o,
    output          p_nearfull_o,        
    output          p_empty_o         
    );
    // for code generation
        function integer WidthCal(input integer InputDepth);
        begin
            if (InputDepth == 0) 
                WidthCal = 1;
            else if (InputDepth != 0)
                for(WidthCal=0;InputDepth>0;WidthCal=WidthCal+1)
                    InputDepth = InputDepth >> 1;
        end
        endfunction
    // parameter definition
        parameter   WIDTH               = WidthCal(DEPTH) - 1;  // this width is the pointer data width
        parameter   NEAR_FULL_LEVEL     = (DEPTH>>2) * 3;
        parameter   MAX_INDEX           = DEPTH - 1;    // if Depth is 4096, then the maximum index number is 4095
    // register definition
            reg [DATA_WIDTH-1:0]   memory [WIDTH-1:0];     // the memory definition
        // pointer 1
            reg [WIDTH-1:0]     pointer_wr_r1/*synthesis syn_preserve = 1*/;           // the memory pointer for write
            reg [WIDTH-1:0]     pointer_rd_r1/*synthesis syn_preserve = 1*/;           // the memory pointer for read
        // pointer 2
            reg [WIDTH-1:0]     pointer_wr_r2/*synthesis syn_preserve = 1*/;           // the memory pointer for write
            reg [WIDTH-1:0]     pointer_rd_r2/*synthesis syn_preserve = 1*/;           // the memory pointer for read
        // pointer 3
            reg [WIDTH-1:0]     pointer_wr_r3/*synthesis syn_preserve = 1*/;           // the memory pointer for write
            reg [WIDTH-1:0]     pointer_rd_r3/*synthesis syn_preserve = 1*/;           // the memory pointer for read
        // FIFO status register
            reg [2:0]           p_empty_r/*synthesis syn_preserve = 1*/;
            reg [2:0]           p_full_r/*synthesis syn_preserve = 1*/;
            reg [2:0]           p_nearfull_r/*synthesis syn_preserve = 1*/;
            reg [2:0]           p_over_r/*synthesis syn_preserve = 1*/;
            reg [7:0]           output_data_r;
            reg [WIDTH-1:0]     bytes_in_fifo_r;        // the number of the bytes in fifo
    // wire definition
        wire [WIDTH-1:0] pointer_wr_w;
        wire [WIDTH-1:0] pointer_rd_w;
        wire        p_full_w;
        wire        p_empty_w;
        wire        p_nearfull_w;
        wire        p_over_w;
        wire        p_full_condition_w;
        wire        p_empty_condition_w;
        wire        p_nearfull_condition_w;
    // assign
        assign pointer_wr_w             = (pointer_wr_r1 && pointer_wr_r2)||(pointer_wr_r2 && pointer_wr_r3)||(pointer_wr_r3 && pointer_wr_r1);
        assign pointer_rd_w             = (pointer_rd_r1 && pointer_rd_r2)||(pointer_rd_r2 && pointer_rd_r3)||(pointer_rd_r3 && pointer_rd_r1);
        assign p_empty_condition_w      = (pointer_wr_w == pointer_rd_w);
        assign p_full_condition_w       = ((pointer_wr_w + 1'b1) == pointer_rd_w);
        assign p_nearfull_condition_w   = (bytes_in_fifo_r >= NEAR_FULL_LEVEL);
        assign p_empty_w                = (p_empty_r[0]&&p_empty_r[1])||(p_empty_r[1]&&p_empty_r[2])||(p_empty_r[2]&&p_empty_r[0]);
        assign p_full_w                 = (p_full_r[0] &&p_full_r[1]) ||(p_full_r[1]&& p_full_r[2]) ||(p_full_r[2]&& p_full_r[0]);
        assign p_nearfull_w             = (p_nearfull_r[0]&&p_nearfull_r[1])||(p_nearfull_r[1]&&p_nearfull_r[2])||(p_nearfull_r[2]&&p_nearfull_r[0]);
        assign p_over_w                 = (p_over_r[0]&&p_over_r[1])||(p_over_r[1]&&p_over_r[2])||(p_over_r[2]&&p_over_r[0]);
        assign p_empty_o                = p_empty_w;
        assign p_full_o                 = p_full_w;
        assign p_nearfull_o             = p_nearfull_w;
        assign p_over_o                 = p_over_w;
        assign data_o                   = output_data_r;
        assign bytes_in_fifo_o          = bytes_in_fifo_r;
    // the write pointer update, pointer_wr_rx
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                pointer_wr_r1 <= 0;
                pointer_wr_r2 <= 0;
                pointer_wr_r3 <= 0;              
            end
            else if (!n_clr_i) begin
                pointer_wr_r1 <= 0;
                pointer_wr_r2 <= 0;
                pointer_wr_r3 <= 0;
            end
            else if (n_we_i == 1'b0) begin
                pointer_wr_r1 <= pointer_wr_w + 1'b1;
                pointer_wr_r2 <= pointer_wr_w + 1'b1;
                pointer_wr_r3 <= pointer_wr_w + 1'b1;
            end
            else begin
                pointer_wr_r1 <= pointer_wr_w;
                pointer_wr_r2 <= pointer_wr_w;
                pointer_wr_r3 <= pointer_wr_w;
            end
        end
    // the read pointer update, pointer_rd_rx
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                pointer_rd_r1 <= 0;
                pointer_rd_r2 <= 0;
                pointer_rd_r3 <= 0;                
            end
            else if(!n_clr_i) begin
                pointer_rd_r1 <= 0;
                pointer_rd_r2 <= 0;
                pointer_rd_r3 <= 0;   
            end
            else if ((n_re_i == 1'b0) && (p_empty_w == 1'b0) || (n_we_i == 1'b0) && (p_full_w == 1'b1)) begin
                pointer_rd_r1 <= pointer_rd_w + 1'b1;
                pointer_rd_r2 <= pointer_rd_w + 1'b1;
                pointer_rd_r3 <= pointer_rd_w + 1'b1;

            end
            else begin
                pointer_rd_r1 <= pointer_rd_w;
                pointer_rd_r2 <= pointer_rd_w;
                pointer_rd_r3 <= pointer_rd_w;
            end
        end
    // the fifo status register update, p_empty_r and p_full_r
        always @(posedge clk or negedge rst) begin  
            if (!rst) begin
                p_empty_r   <= 3'b111;
                p_full_r    <= 3'b000;   
                p_nearfull_r<= 3'b000;  
            end
            else if (!n_clr_i) begin
                p_empty_r   <= 3'b111;
                p_full_r    <= 3'b000;   
                p_nearfull_r<= 3'b000;
            end
            else begin
                p_empty_r   <= {p_empty_condition_w,p_empty_condition_w,p_empty_condition_w};
                p_full_r    <= {p_full_condition_w,p_full_condition_w,p_full_condition_w};
                p_nearfull_r<= {p_nearfull_condition_w,p_nearfull_condition_w,p_nearfull_condition_w};
            end
        end
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                p_over_r <= 3'b000;
            end
            else if (!n_clr_i) begin
                p_over_r <= 3'b000;
            end
            else if ((p_full_w == 1'b1)&&(n_we_i == 1'b0)&&(n_re_i == 1'b1)) begin
                p_over_r <= 3'b111;
            end
            else if (p_full_w == 1'b0) begin
                p_over_r <= 3'b000;
            end
            else begin
                p_over_r <= {p_over_w,p_over_w,p_over_w};
            end
        end
    // the bytes in fifo register update
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                bytes_in_fifo_r <= 0;              
            end
            else if (!n_clr_i) begin
                bytes_in_fifo_r <= 0;
            end
            else if (p_full_w == 1'b1) begin
                bytes_in_fifo_r <= MAX_INDEX;
            end
            else if (p_empty_w == 1'b1) begin
                bytes_in_fifo_r <= 0;
            end
            else if (pointer_wr_w < pointer_rd_w) begin
                bytes_in_fifo_r <= pointer_wr_w + ~pointer_rd_w;           
            end
            else begin
                bytes_in_fifo_r <= pointer_wr_w - pointer_rd_w;
            end
        end
    // Memory update
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                // it is too complex to initial the memory array                
            end
            else if (n_we_i == 1'b0) begin        // The data would keep be written into the fifo when even the fifo is full
                memory[pointer_wr_w] <= data_i;
            end
            // else if ((n_we_i == 1'b0) && (p_full_w == 1'b0)) begin   // The data would not be written into the fifo when the fifo is full
            //     memory[pointer_wr_w] <= data_i;
            // end
        end
    // output buffer
        always @(posedge clk or negedge rst) begin
            if (!rst || !n_clr_i) begin
                output_data_r <= 8'd0;                
            end
            else if ((n_re_i == 1'b0) && (p_empty_w == 1'b0)) begin
                output_data_r <= memory[pointer_rd_w];
            end
            else begin
                output_data_r <= output_data_r;
            end
        end
endmodule
