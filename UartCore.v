// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen   penguinleo@163.com
// File   : UartCore.v
// Create : 2019-12-17 15:17:15
// Revise : 2019-12-17 15:17:15
// Editor : sublime text3, tab size (4)
// Comment: this module is designed as the top module of the UART module. The module 
//          is built up by its submodules.
//          To realize the high precision of the bit width(baudrate), the bit compensation
//          method was introduced into the uart port. The accuracy of the bit width which 
//          send out by the module could be reduced under 1 system clock!
//          By the way, the uart core should work with the 40MHz system clock.
//          Up module:
//              ----
//          Sub module:
//              CtrlCore.v
//              TxCore.v
//              RxCore.v
// Input Signal List:
//      1   |   clk         :   clock signal
//      2   |   rst         :   reset signal
//      3   |   p_We_i      :   The control signal that the control parameters should enabled
//      4   |   CtrlReg1_i  :   The control register for the uart core. In this byte there are
//                              Bit7: the BigEnd or SmallEnd control bit, 1-Big End; 0-Small End.
//                              Bit6: the Parity Enable control bit, 1-Enable the parity function; 0-Disabled.
//                              Bit5: the Parity Method control bit, 0-EVEN parity; 1-ODD parity
//                              Bit4: Reserved
//                              Bit3~0: The high 4 bits for the acquisition signal cycle congtrol
//      5   |   CtrlReg2_i  :   The low 8 bits for the acquisition signal cycle control 
//      6   |   CtrlReg3_i  :   The compensation method for the baudrate signal.
//                              Bit7~4: The round up acquisition signal cycle numbers.
//                              Bit3:0: The round down acquisition signal cycle number.
//      7   |   n_rd_i      :   The read signal of the reveice fifo, which is better to be triggled 
//                              by the read access from the bus.
//      8   |   data_i      :   The write port of the transimit fifo.
//      9   |   n_we_i      :   The write signal of the transimit fifo, which is better to be triggled 
//                              by the write access from the bus.
//      10  |   Rx_i        :   The rx signal from the FPGA pin.
// Output Signal List:
//      1   |   data_o      :   The receive fifo output.
//      2   |   p_empty_o   :   The receive fifo empty flag, 1-empty, 0-something in the fifo to be read
//      3   |   p_full_o    :   The transimite fifo is full, 1-full, 0-not full.      
//      4   |   Tx_o        :   The tx output signal through the FPGA pin.
// Note:  
// 
// -----------------------------------------------------------------------------   
module UartCore(
    input   clk,
    input   rst,
    // The bus interface
        input  [3:0]    AddrBus_i,     
        input           n_ChipSelect_i,
        input           n_rd_i,        
        input           n_we_i,        
        input  [7:0]    DataBus_i,     
        output [7:0]    DataBus_o,     
        output          p_IrqSig_o, 
    // the time stamp input
        input [3:0]     acqurate_stamp_i,
        input [11:0]    millisecond_stamp_i,
        input [31:0]    second_stamp_i,
    // Uart port
        input           Rx_i,
        output          Tx_o
    );
    wire [15:0] AcqPeriod_w;
    wire [7:0]  BitCompensation_w;
    wire [3:0]  RoundUpNum_w;
    wire [3:0]  RoundDownNum_w;
    wire [3:0]  AcqNumPerBit_w;
    wire [15:0] RxFIFO_Level_w;
    wire [15:0] RxTimeOutSet_w;
    wire [15:0] RxTimeCnt_w;
    wire [27:0] RxFrameInfo_w;
    wire [3:0]  ModeSel_w;
    wire [7:0]  TxData_w;
    wire [7:0]  RxData_w;
    wire [15:0] TxFIFO_Level_w;
    wire [7:0]  ParityErrorNum_w;    // put it in the control core // del when added
    wire        p_RxFrame_Func_En_w;
    wire        p_ParityEnable_w;
    wire        p_BigEnd_w;
    wire        ParityMethod_w; 
    wire        AcqSig_w;
    wire        BaudSig_w;
    wire        p_SendFinished_w;
    wire        p_DataReceived_w;
    wire        p_RxTimeOut_w;
    // logic definition
        assign BitCompensation_w = {RoundUpNum_w, RoundDownNum_w};
    CtrlCore ControlCore(
        .clk(clk),
        .rst(rst),
        // the bus interface 
            .AddrBus_i(AddrBus_i),
            .n_ChipSelect_i(n_ChipSelect_i),
            .n_rd_i(n_rd_i),
            .n_we_i(n_we_i),
            .DataBus_i(DataBus_i),
            .DataBus_o(DataBus_o),
            .p_IrqSig_o(p_IrqSig_o),
        // baudrate module interface
            .BaudRateGen_o(AcqPeriod_w),
            .RoundUpNum_o(RoundUpNum_w),
            .RoundDownNum_o(RoundDownNum_w),
            .BaudDivider_o(AcqNumPerBit_w), 
        // model select module interface
            .ModeSel_o(ModeSel_w),
        // tx module interface
            .p_TxCoreEn_o(p_TxCoreEn_w),
            .TxData_o(TxData_w),
            .p_TxFIFO_Over_i(p_TxFIFO_Over_w),
            .p_TxFIFO_Full_i(p_TxFIFO_Full_w),
            .p_TxFIFO_NearFull_i(p_TxFIFO_NearFull_w),
            .p_TxFIFO_Empty_i(p_TxFIFO_Empty_w),
            .n_TxFIFO_We_o(n_TxFIFO_We_w),
            .n_TxFIFO_Clr_o(n_TxFIFO_Clr_w),
            .TxFIFO_Level_i(TxFIFO_Level_w),            
        // rx module interface
            .p_RxCoreEn_o(p_RxCoreEn_w),
            .p_RxParityErr_i(p_RxParityErr_w),
            .p_RxFrameErr_i(p_RxFrameErr_w),
            .RxData_i(RxData_w),
            .p_RxFIFO_Empty_i(p_RxFIFO_Empty_w),
            .p_RxFIFO_Over_i(p_RxFIFO_Over_w),
            .p_RxFIFO_Full_i(p_RxFIFO_Full_w),
            .p_RxFIFO_NearFull_i(p_RxFIFO_NearFull_w),
            .n_RxFIFO_Rd_o(n_RxFIFO_Rd_w),
            .n_RxFIFO_Clr_o(n_RxFIFO_Clr_w),
            .RxTimeOutSet_o(RxTimeOutSet_w),
            .p_RxTimeOut_i(p_RxTimeOut_w),
            .RxFIFO_Level_i(RxFIFO_Level_w),
            .p_RxFrame_Func_En_o(p_RxFrame_Func_En_w),
            .RxFrameInfo_i(RxFrameInfo_w),
            .AnsDelayTime_i(RxTimeCnt_w),
            .p_RxFrame_Empty_i(p_RxFrame_Empty_w),
            .n_RxFrameInfo_Rd_o(n_RxFrameInfo_Rd_w),
        // Rx & Tx encode control output
            .p_ParityEnable_o(p_ParityEnable_w),
            .p_BigEnd_o(p_BigEnd_w),
            .ParityMethod_o(ParityMethod_w)
    );

    BaudrateModule_ver2 BaudGen(
        .clk(clk),
        .rst(rst),
        .AcqPeriod_i(AcqPeriod_w),
        .BitCompensation_i(BitCompensation_w),
        .AcqSig_o(AcqSig_w),
        .BaudSig_o(BaudSig_w)
    );

    RxCore RxCore(
        .clk(clk),
        .rst(rst),
        // fifo control signal
            .Data_o(RxData_w),
            .n_Rd_i(n_RxFIFO_Rd_w),
            .n_Clr_i(n_RxFIFO_Clr_w),
            .p_Enable_i(p_RxCoreEn_w),
            .p_FrameFunctionEnable_i(p_RxFrame_Func_En_w),
            .n_RxFrameInfo_Rd_i(n_RxFrameInfo_Rd_w),
        // fifo status signal
            .p_Empty_o(p_RxFIFO_Empty_w),
            .p_NearFull_o(p_RxFIFO_NearFull_w),
            .p_Full_o(p_RxFIFO_Full_w),
            .p_Over_o(p_RxFIFO_Over_w),
            .RxFifoLevel_o(RxFIFO_Level_w),
            .RxFrameInfo(RxFrameInfo_w),
            .p_RxFrame_Empty_o(p_RxFrame_Empty_w),
            .p_RxParityErr_o(p_RxParityErr_w),
            .p_RxFrameErr_o(p_RxFrameErr_w),
        // Rx and Tx encode control output
            .p_ParityEnable_i(p_ParityEnable_w),
            .p_BigEnd_i(p_BigEnd_w),
            .ParityMethod_i(ParityMethod_w),
        // Rx Time control and flag
            .RxTimeOutSet_i(RxTimeOutSet_w),
            .p_RxTimeOut_o(p_RxTimeOut_w),
            .RxDlyTime_o(RxTimeCnt_w),
            .p_TimeCntStartSig_i(p_TxFIFO_Empty_w),
            .p_TimeCntResetSig_i(1'b0),   // this signal should be controlled by the control module
        // Baudrate generate module
            .AcqSig_i(AcqSig_w),
            .BaudSig_i(BaudSig_w),
            .AcqNumPerBit_i(AcqNumPerBit_w),
        // time stamp module
            .acqurate_stamp_i(acqurate_stamp_i),
            .millisecond_stamp_i(millisecond_stamp_i),
            .second_stamp_i(second_stamp_i),
        // error counter
            .ParityErrorNum_o(ParityErrorNum_w),
        // the receive signal
        .Rx_i(Rx_i)
    );

    TxCore TxCore(
        .clk(clk),
        .rst(rst),
        // fifo control signal
            .Data_i(TxData_w),
            .n_We_i(n_TxFIFO_We_w),
            .n_Clr_i(n_TxFIFO_Clr_w),
            .p_Enable_i(p_TxCoreEn_w),
        // fifo status signal
            .p_Full_o(p_TxFIFO_Full_w),
            .p_Over_o(p_TxFIFO_Over_w),
            .p_NearFull_o(p_TxFIFO_NearFull_w),
            .p_Empty_o(p_TxFIFO_Empty_w),
            .bytes_in_fifo_o(TxFIFO_Level_w),
        // baudrate signal
            .p_BaudSig_i(BaudSig_w),
        // control sognal
            .p_ParityEnable_i(p_ParityEnable_w),
            .p_BigEnd_i(p_BigEnd_w),
            .ParityMethod_i(ParityMethod_w),
        // .p_SendFinished_o(p_SendFinished_w),
        .Tx_o(Tx_o) 
    );

    // AnsDelayTimeMeasure AnsDlyMea(
    //     .clk(clk),
    //     .rst(rst),
    //     .p_SendFinished_i(p_SendFinished_w),
    //     .p_DataReceived_i(p_DataReceived_w),
    //     .p_sig_10MHz_i(p_sig_10MHz_i),
    //     .n_rd_i(n_rd_frame_fifo_i),
    //     .n_clr_i(n_clr_i),
    //     .ans_delay_o(ans_delay_o)
    // );


endmodule
