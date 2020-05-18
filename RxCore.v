// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen   penguinleo@163.com
// File   : RxCore.v
// Create : 2019-11-17 10:19:33
// Revise : 2019-11-17 10:19:34
// Editor : sublime text3, tab size (4)
// Comment: this module is designed to receive the serial data from rx wire and 
// 			save the data in the fifo. The module contains 5 submodules.
// 			the RxCore could adjust the acquisition time in one bit, the acquisite
// 			point is setted at the middle of the bit.
// 			The shift register and the byte analyse module are the most complex module.
//          Up module:
//              UartCore
//          Sub module:
//              ShiftRegister_Rx        Serial to byte module. This module acquisites the 
// 										signal on the rx wire. Acquisition frequency is controlled
// 										by the AcqSig signal, the acquisition time is defined
// 										by the AcqNumPerBit.
//              FIFO_Ver1               Fifo module
//              FSM_Rx                  State machine of rx core, the state definition is 
// 										based on the byte structure in the serial protocol.
// 										INTTERVAL, STARTBIT, DATABITS, PARITYBIT, STOPBIT.
// 				ParityGenerator 		The parity calculate module
// 				ByteAnalyseV2			This module get the data acquisited by the ShiftRegister_Rx
// 										and analyse the data, give out the timestamp, send the data 
// 										to the fifo.   
//          Input
//              clk 						:   clock signal
//              rst 						:   reset signal
// 				n_rd_i 						:	the fifo read signal, which is active low. The pulse width should be 1 system clk
//				n_clr_i 					: 	the control signal to clear the fifo.
// 				n_rd_frame_fifo_i 			:	the signal to read the frame info register which is active low. the pusle width should be
// 												1 system clk. When this signal is available, the fifo would fresh with 
// 												next frame.
// 				AcqSig_i 					: 	The acquisition signal from the baudrate generate module. This signal drive the shift re-
// 												-gister to acquisite the signal on the rx wire.
// 				BaudSig_i 					: 	The baudrate signal is generated from the baudrate generate module, which is synchronized
// 											    with the AcqSig_i signal.
// 				p_ParityEnable_i 			: 	The control signal from the CtrlCore. When this signal is high, the parity function in the 
// 												receive core is enabled, the byte analyse module would check the parity bit.
// 	  			p_BigEnd_i 					: 	Big end sending, When it is high, that means the bits in the byte would be sent on the tx 
// 												wire from bit 7 to bit 0, bit by bit. In contrast, the bits would be sent on the wire from 
// 												bit 0 to bit 7.
// 				ParityMethod_i 				:   Select the parity method, 0-even,1-odd.
// 				AcqNumPerBit_i[3:0] 		: 	This register define the divide relationshiop between the AcqSig ang BaudSig. This register 
// 												define the acquisite time in one bit.
// 				acqurate_stamp_i[3:0] 		: 	The time stamp(0.1ms) from other module. The equivalent of this data is 0.1ms. The range of 
// 												data is 0 ~ 9;
// 				millisecond_stamp_i[11:0] 	:	The time stamp(millisecond) from other module. The equivalent of this data is 1ms. The range
// 												of this data is 0 ~ 999;
//				second_stamp_i[31:0]		:   The time stamp(second) from other module. The equivalent of this data is sencond. The range 
// 												of this data is 0 ~ ‭4294967295‬
//  			Rx_i 						: 	The rx wire.
//          Output
// 				data_o[7:0]					: 	The output port of the receive fifo.
// 				p_empty_o 					:  	The receive fifo empty signal.
// 				frame_info_o[27:0]			: 	The time stamp of the frame information. Containing the frame bytes' number, the last byte
// 												millisecond_stamp and acqurate_stamp information.
// 				ParityErrorNum_o[7:0] 		:   Giving out the parit error number in this rx core. The data with parity error would not be 
// 												sent into the fifo, instead the number in this counter would increase.
//              
// -----------------------------------------------------------------------------
module RxCore(
    input   clk,
    input   rst,
    // fifo control signal
        output [7:0]    data_o,
        input           n_rd_i,     // the fifo read signal
        input           n_clr_i,	// empty the fifo
        output          p_empty_o,  // the fifo is empty
        output [15:0]   bytes_in_fifo_o,
    // frame info rd control
    	input 			n_rd_frame_fifo_i,
    	output [27:0]	frame_info_o,
    // the baudsig from the baudrate generate module
        input           AcqSig_i,   // acquistion signal
        input 			BaudSig_i,
    // the rx core control signal
        input           p_ParityEnable_i,
        input           p_BigEnd_i,
        input           ParityMethod_i,
        input [3:0]     AcqNumPerBit_i,
    // time stamp input
		input [3:0]		acqurate_stamp_i,
		input [11:0]	millisecond_stamp_i,
		input [31:0]	second_stamp_i,    	
    // the error flag signal
    	output  [7:0]   ParityErrorNum_o,
        // output           p_BaudrateError_o,  // the Baudrate error
        // output           p_ParityError_o,    // the Parity error
    // the interface with the AnsDelayTimeMeasure module
    	output 		   	p_DataReceived_o,
    // the rx signal
        input           Rx_i            
    );
    // register definition
        // NONE
    // wire definition
        wire        Rx_Synch_w;
        wire        Bit_Synch_w;
        wire 		Byte_Synch_w;
        wire        p_ParityCalTrigger_w;
        wire [4:0]  State_w;
        wire [3:0]  BitCounter_w;
        wire [3:0]  BitWidthCnt_w;
        wire        ParityResult_w;
        wire [11:0] Byte_w;
        wire [7:0]  Data_w;
        wire [7:0]	ParityData_w;
        wire        n_we_w;
        wire        p_full_w;
        wire 		p_DataReceived_w;
    // parameter
    	// state machine definition
        	parameter INTERVAL  = 5'b0_0001;
            parameter STARTBIT  = 5'b0_0010;
            parameter DATABITS  = 5'b0_0100;
            parameter PARITYBIT = 5'b0_1000;
            parameter STOPBIT   = 5'b1_0000;
    // logic definition
    	assign p_DataReceived_w = Byte_Synch_w;
    	assign p_DataReceived_o = p_DataReceived_w;
    FSM_Rx StateMachine(
        .clk(clk),
        .rst(rst),
        .Rx_Synch_i(Rx_Synch_w),
        .Bit_Synch_i(Bit_Synch_w),
        .AcqSig_i(AcqSig_i),
        .p_ParityEnable_i(p_ParityEnable_i),
        // .p_ParityCalTrigger_o(p_ParityCalTrigger_w),
        .State_o(State_w),
        .BitCounter_o(BitCounter_w)
        );

    ShiftRegister_Rx ShiftReg(
        .clk(clk),
        .rst(rst),
        .AcqSig_i(AcqSig_i),
        .AcqNumPerBit_i(AcqNumPerBit_i),
        .Rx_i(Rx_i),
        .State_i(State_w),
        .BitWidthCnt_o(BitWidthCnt_w),
        .Byte_o(Byte_w),
        .Bit_Synch_o(Bit_Synch_w),
        .Byte_Synch_o(Byte_Synch_w),
        .Rx_Synch_o(Rx_Synch_w)
        );

    ParityGenerator ParityGenerator(
        .clk(clk),
        .rst(rst),
        // .p_BaudSig_i(p_BaudSig_i),
        // .State_i(State_w),
        .p_ParityCalTrigger_i(p_ParityCalTrigger_w),
        // .BitCounter_i(BitCounter_w),
        .ParityMethod_i(ParityMethod_i),
        .Data_i(ParityData_w),          // Be Carefull, when trigger signal generate the byte data is low 8 bits
        .ParityResult_o(ParityResult_w)
        );

    ByteAnalyseV2 ByteAnalyse(
      	.clk(clk),
		.rst(rst),
		.n_we_o(n_we_w),
		.data_o(Data_w),
		.p_full_i(p_full_w),
		.BaudSig_i(BaudSig_i),
		.byte_i(Byte_w),
		.Bit_Synch_i(Bit_Synch_w),
		.Byte_Synch_i(Byte_Synch_w),
		.State_i(State_w),
		// .BitWidthCnt_i(BitWidthCnt_w),
		.acqurate_stamp_i(acqurate_stamp_i),
		.millisecond_stamp_i(millisecond_stamp_i),
		.second_stamp_i(second_stamp_i),
		.p_ParityEnable_i(p_ParityEnable_i),
		.p_BigEnd_i(p_BigEnd_i),
		.n_rd_frame_fifo_i(n_rd_frame_fifo_i),
		.frame_info_o(frame_info_o),
		.ParityCalData_o(ParityData_w),
		.p_ParityCalTrigger_o(p_ParityCalTrigger_w),
		.ParityResult_i(ParityResult_w),
		.ParityErrorNum_o(ParityErrorNum_o)
        );

    FIFO_ver1 #(.DEPTH(8'd128)) RxCoreFifo (
        .clk(clk),
        .rst(rst),
        .data_i(Data_w),
        .n_we_i(n_we_w),
        .n_re_i(n_rd_i),
        .n_clr_i(n_clr_i),
        .data_o(data_o),
        .bytes_in_fifo_o(bytes_in_fifo_o),
        .p_empty_o(p_empty_o),
        .p_full_o(p_full_w)
        );
    

endmodule