// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen   penguinleo@163.com
// File   : CtrlCore.v
// Create : 2019-12-17 15:19:59
// Revise : 2019-12-17 15:19:59
// Editor : sublime text3, tab size (4)
// Comment: this module is designed to control the UART port.
//          The UART module is designed a compensate method to implement an accurate bit width
//          I call this method acquisition period compensate method.
//          In further, the bit width compensate method would be introduced to reduce the accumulate
//          error in the last bit of a byte during transmitting.
//          Up module:
//              UartCore
//          Sub module:
//              None
// Input Signal List:
//      1   |   CLK                 :   clock signal
//      2   |   RST                 :   reset signal
//      3   |   p_We_i              :   control register write enable signal, positive effective.
//      4   |   CtrlReg1_i          :   Control parameter register,
//                                      Bit 7 controls the big end or little end format;
//                                      Bit 6 controls the parity function, 1-enable,0-disable;
//                                      Bit 5 choose the parity method, 0-even,1-odd;
//                                      Bit 4 reserved bit;
//                                      Bit 3 ~ 0 are the high 4 bits of acquisition period control reg;
//      6   |   BitCompensateMethod :   Compensation control register
//                                      Bit 7 ~ 4 are the number of round-up acquisition period in a bit time;
//                                      Bit 3 ~ 0 are the number of round-down period in a bit time;
//                                      The acquisition period control reg is the round-down period data.
// Output Signal List:      
//      1   |   BaudRateGen_o       :   The acquisition period control register output. This period is the round-down
//                                      period. This data is sent to the BaudGenerate module to generate the AcqSig
//      2   |   BitCompensation_o   :   The compensate control register, which would help the BaudGenerate module
//                                      reduce the bit width error less than a system clk;
//                                      Bit 7 ~ 4 are the number of round-up acquisition period in a bit time
//                                      Bit 3 ~ 0 are the number of round-down acquisition period in a bit time
//      3   |   AcqNumPerBit_o      :   The number to acquisition operation in a bit time. This data is the sum of
//                                      the BitCompensation_o[7:4] + BitCompensation_o[3:0]
//      4   |   p_ParityEnable_o    :   The parity enable signal output for other uart submodules, 1-enable,0-disable;
//      5   |   p_BigEnd_o          :   The format control signal output for other uart submodules, 0-even,1-odd;
//      6   |   ParityMethod_o      :   The parity method select signal output for other uart submodule, 0-even,1-odd;
// Register Map:
//    Address | DecAddr | ConfigEn | Dir |         Name          |                                       Bit Definition                                          | 
//   ---------|---------|----------|-----|-----------------------|-----B7----|-----B6----|-----B5----|-----B4----|-----B3----|-----B2----|-----B1----|-----B0----|
//    4'b0000 |    0    |     X    | R/W |      UartControl      | ConfigEn  | Reserved  |  Reserved |   ClkSel  |   RxEn    |    TxEn   |   RxRst   |   TxRst   |
//    4'b0001 |    1    |     X    |  R  |      UartStatus1      | Reserved  |   TNFUL   |   TTRIG   | Reserved  |  TACTIVE  |  RACTIVE  | Reserved  | Reserved  |
//    4'b0010 |    2    |     X    |  R  |      UartStatus2      | Reserved  | Reserved  | Reserved  |   TXFUL   |  TEMPTY   |   RFULL   |  REMPTY   |   RTRIG   |
//    4'b0011 |    3    |     X    |  R  |      RxDataPort       |     8-bit receive data read port                                                              |
//    4'b0011 |    3    |     X    |  W  |      TxDataPort       |     8-bit transmits data send port                                                            |
//   ---------|---------|----------|-----|-----------------------|-----B7----|-----B6----|-----B5----|-----B4----|-----B3----|-----B2----|-----B1----|-----B0----|
//    4'b0100 |    4    |     1    | R/W |       UartMode        |                   ModeSel                     |   EndSel  |   ParEn   |  ParSel   |  Reserved |
//    4'b0101 |    5    |     1    | R/W |   BaudGeneratorHigh   | High 8 bits of the Baudrate generator register, write access enabled when ConfigEn == 1       | 
//    4'b0110 |    6    |     1    | R/W |   BaudGeneratorLow    | Low 8 bits of the Baudrate generator register, write access enabled when ConfigEn == 1        |
//    4'b0111 |    7    |     1    | R/W |  BitCompensateMethod  |         Round Up Period number in a bit       |       Round Down Period number in a bit       |
//    4'b1000 |    8    |     1    |  W  |    InterrputEnable1   | Reserved  | Reserved  | Reserved  |    TOVR   |   TNFUL   |   TTRIG   | Reserved  |  TIMEOUT  |
//    4'b1001 |    9    |     1    |  W  |    InterrputEnable2   |    PARE   |   FRAME   |   ROVR    |    TFUL   |  TEMPTY   |   RFULL   |  REMPTY   |   RTRIG   | 
//    4'b1000 |    8    |     1    |  R  |    InterruptMask1     | Reserved  | Reserved  | Reserved  |    TOVR   |   TNFUL   |   TTRIG   | Reserved  |  TIMEOUT  |
//    4'b1001 |    9    |     1    |  R  |    InterruptMask2     |    PARE   |   FRAME   |   ROVR    |    TFUL   |  TEMPTY   |   RFULL   |  REMPTY   |   RTRIG   |
//    4'b1010 |    10   |     1    | R/W |    RxTrigLevelHigh    | High 8 bits of the rx fifo trigger level                                                      |      
//    4'b1011 |    11   |     1    | R/W |    RxTrigLevelLow     | Low 8 bits of the rx fifo trigger level                                                       |
//    4'b1100 |    12   |     1    | R/W |    TxTrigLevelHigh    | High 8 bits of the tx fifo trigger level                                                      |    
//    4'b1101 |    13   |     1    | R/W |    TxTrigLevelLow     | Low 8 bits of the tx fifo trigger level                                                       |
//    4'b1110 |    14   |     1    | R/W |   ReceiveTimeOutHigh  | Receive time out value                                                                        |
//    4'b1111 |    15   |     1    | R/W |   ReceiveTimeOutLow   | Receive time out value                                                                        |
//   ---------|---------|----------|-----|-----------------------|-----B7----|-----B6----|-----B5----|-----B4----|-----B3----|-----B2----|-----B1----|-----B0----|
//    4'b0100 |    4    |     0    | R/W |   InterruptStatus1    | Reserved  | Reserved  | Reserved  |    TOVR   |   TNFUL   |   TTRIG   | Reserved  |  TIMEOUT  |     
//    4'b0101 |    5    |     0    | R/W |   InterruptStatus2    |    PARE   |   FRAME   |   ROVR    |    TFUL   |  TEMPTY   |   RFULL   |  REMPTY   |   RTRIG   | 
//    4'b0110 |    6    |     0    |  R  | BytesNumberReceived1  |   High 8 bits of the bytes' number in receive fifo                                            |
//    4'b0111 |    7    |     0    |  R  | BytesNumberReceived2  |   Low 8 bits of the bytes' number in receive fifo                                             |
//    4'b1000 |    8    |     0    |  R  |    FrameFifoStatus    |     cmd                                                                                       |
//    4'b1001 |    9    |     0    |  R  |  FrameBytesNumberHigh | The frame bytes number of this frame                                                          |
//    4'b1010 |    10   |     0    |  R  |  FrameBytesNumberLow  | The frame bytes number of this frame                                                          |
//    4'b1011 |    11   |     0    |  R  |  FrameTimeStampInfo1  | Millisecond time stamp of this frame low 8 bits                                               |      
//    4'b1100 |    12   |     0    |  R  |  FrameTimeStampInfo2  | Millisecond time stamp high 4 bits            | MicroSecond time stamp 4 bits width           |
//    4'b1101 |    13   |     0    |  R  |   FrameAnsTimeInfo1   |                                                                                               |
//    4'b1110 |    14   |     0    |  R  |   FrameAnsTimeInfo2   |                                                                                               |
//    4'b1111 |    15   |     0    |  R  |     ReservedAddr3     |                                                                                               |  
// Note:  
// 2020-05-30  The Receive fifo operation should be careful. In my opinion, the data read operation in the bus may be delay a clk. Due to the delay of the fifo read
//              operation. It is better to think about it carefully and added into the datasheet
// -----------------------------------------------------------------------------   
module CtrlCore(
    input   clk,
    input   rst,
    // The bus interface
        input  [3:0]    AddrBus_i,                  // the input address bus
        input           n_ChipSelect_i,             // the chip select signal
        input           n_rd_i,                     // operation direction control signal read direction, negative enable
        input           n_we_i,                     // operation direction control signal write direction, negative enable
        input  [7:0]    DataBus_i,                  // data bus input direction write data into the registers
        output [7:0]    DataBus_o,                  // data bus output direction read data from the registers
        output          p_IrqSig_o,                 // the interrupt signal generated by the UART module
    // baudrate module interface
        output [15:0]   BaudRateGen_o,              // The divider data for the acquisition period
        output [3:0]    RoundUpNum_o,               // The compensate method high 4 bits, round up acquisition period
        output [3:0]    RoundDownNum_o,             // The compensate method low 4 bits, round down acquisition period
        output [3:0]    BaudDivider_o,              // The divider for the baudrate signal and the acquisition signal
    // tx module interface
        output          p_TxCoreEn_o,               // The Tx core enable signal. Positive effective 
        // fifo control signal
            output [7:0]    TxData_o,               // Tx Fifo write data port
            input           p_TxFIFO_Over_i,        // Tx Fifo overflow signal
            input           p_TxFIFO_Full_i,        // Tx Fifo full signal, positive the fifo full
            input           p_TxFIFO_NearFull_i,    // Tx Fifo near full signal
            input           p_TxFIFO_Empty_i,       // Tx Fifo empty signal
            output          n_TxFIFO_We_o,          // Tx Fifo write control singal, negative effective
            output          n_TxFIFO_Clr_o,         // Tx Fifo clear signal, negative effective
            input [15:0]    TxFIFO_Level_i,         // The bytes number in the Tx fifo          
    // rx module interface
        output          p_RxCoreEn_o,               //The Rx core enable signal. Positive effective
        // error signal
            input           p_RxParityErr_i,        // RX parity check fail, positive error occur
            input           p_RxFrameErr_i,         // Rx stop bit missing, positive error occur
        // fifo control signal
            input [7:0]     RxData_i,               // Rx Fifo read port
            input           p_RxFIFO_Empty_i,       // Rx Fifo empty, status signal, positive effective
            input           p_RxFIFO_Over_i,        // Rx Fifo overflow, status signal, positive effective
            input           p_RxFIFO_Full_i,        // Rx Fifp full, status signal, positive effective
            input           p_RxFIFO_NearFull_i,    // Rx Fifo near full, status signal, positive effective
            output          n_RxFIFO_Rd_o,          // Rx Fifo read control signal, negative effective
            output          n_RxFIFO_Clr_o,         // Rx Fifo clear signal
            output [15:0]   RxTimeOutSet_o,         // Rx time out value, count the AcqSig
            input           p_RxTimeOut_i,          // Rx time out flag, 1-time out occur, 0-no error
            input [15:0]    RxFIFO_Level_i,         // bytes number in the Rx fifo
        // extend function signal(Data link level)
            output          p_RxFrame_Func_En_o,    // Data link level protocol function enable control
            input [27:0]    RxFrameInfo_i,          // Data link level protocol function extension
            input [15:0]    AnsDelayTime_i,         // The interval between the last tx bit and the first rx bit, count the AcqSig
            input           p_RxFrame_Empty_i,      // No Received frame
            output          n_RxFrameInfo_Rd_o,     // Read frame informatoin control signal, negative enable     
    // Rx & Tx encode control control output
        output          p_ParityEnable_o,
        output          p_BigEnd_o,
        output          ParityMethod_o
    );
    // Register definition //trip-mode synthesis syn_preserve=1
        reg [2:0]   shift_rd_r1                 /*synthesis syn_preserve = 1*/;  // the shift register for the input bus control signal rd
        reg [7:0]   UartControl_r1              /*synthesis syn_preserve = 1*/;  // W module control
        reg         p_RxRst_r1                  /*synthesis syn_preserve = 1*/; 
        reg         p_TxRst_r1                  /*synthesis syn_preserve = 1*/; 
        reg [7:0]   UartMode_r1                 /*synthesis syn_preserve = 1*/;  // R/W mode  
        reg [15:0]  BaudGenerator_r1            /*synthesis syn_preserve = 1*/;  // R/W the acquisition signal divide from the the system clock signal
        reg [7:0]   BitCompensateMethod_r1      /*synthesis syn_preserve = 1*/;  // R/W round up and down acquisition period, the sum of this two is the divider of acquisition signal and baud signal    
        // reg [15:0]  InterrputEnable_r1       /*synthesis syn_preserve = 1*/;  // W   interrupt enable and disable control
        reg [15:0]  InterruptMask_r1            /*synthesis syn_preserve = 1*/;  // R the interrupt enable signal controlled 
        reg [15:0]  RxTrigLevel_r1              /*synthesis syn_preserve = 1*/;  // R/W the trigger level of the rx fifo
        reg [15:0]  TxTrigLevel_r1              /*synthesis syn_preserve = 1*/;  // R/W the trigger level of the tx fifo
        reg [15:0]  InterruptState_r1           /*synthesis syn_preserve = 1*/;  // R/W the interrupt signal and clear control register 
        reg [15:0]  UartState_r1                /*synthesis syn_preserve = 1*/;  // R the uart state register
        reg [3:0]   BaudDivider_r1              /*synthesis syn_preserve = 1*/;  // -- inner register calculated from the BitCompensateMethod_r1
        reg [2:0]   TxFIFO_We_r1                /*synthesis syn_preserve = 1*/;  // -- the write signal of the tx module 
        reg [7:0]   DataBus_r1                  /*synthesis syn_preserve = 1*/;  // R the data bus in output direction
        reg [15:0]  BytesNumberInRxFifo_r1      /*synthesis syn_preserve = 1*/;  // R the bytes number in the receive fifo 
        reg [15:0]  BytesNumberInTxFifo_r1      /*synthesis syn_preserve = 1*/;  // R the bytes number in the transmit fifo 
        reg [15:0]  ReceiveTimeOutLvl_r1        /*synthesis syn_preserve = 1*/;  // R/W the receive time out buffer, count the acquisition signal - AcqSig
        reg         p_IrqSig_r1                 /*synthesis syn_preserve = 1*/;  // Output interrupt signal 
        reg [2:0]   shift_TOVR_r1               /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal TOVR
        reg [2:0]   shift_TNFUL_r1              /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal TNFUL 
        reg [2:0]   shift_TTRIG_r1              /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal TTRIG
        reg [2:0]   shift_TIMEOUT_r1            /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal TIMEOUT
        reg [2:0]   shift_TFUL_r1               /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal TFUL
        reg [2:0]   shift_ParityErr_r1          /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal Parity Error
        reg [2:0]   shift_FrameErr_r1           /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal Frame Error  
        reg [2:0]   shift_ROVR_r1               /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal ROVR       
        reg [2:0]   shift_TEMPTY_r1             /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal TEMPTY
        reg [2:0]   shift_RFULL_r1              /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal RFULL
        reg [2:0]   shift_REMPTY_r1             /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal REMPTY
        reg [2:0]   shift_RTRIG_r1              /*synthesis syn_preserve = 1*/;  // the shift register for interrupt signal RTRIG
    // Logic definition
        // page control signal definition
            wire        ConfigEn_w;
            wire        IrqConfigEn_w;
            wire        IrqLvlEn_w;
        // control signal definition
            wire        ClkSel_w;
            wire        RxEn_w;
            wire        TxEn_w;
            wire [3:0]  ModeSel_w;
            wire        EndSel_w;
            wire        ParEn_w;
            wire        ParSel_w;
        // Interrupt signal logic definition
            wire        p_Irq_TOVR_w;
            wire        p_Irq_TNFUL_w;
            wire        p_Irq_TTRIG_w;
            wire        p_Irq_TIMEOUT_w;
            wire        p_Irq_PARE_w;
            wire        p_Irq_FRAME_w;
            wire        p_Irq_ROVR_w;
            wire        p_Irq_TFUL_w;
            wire        p_Irq_TEMPTY_w;
            wire        p_Irq_RFULL_w;
            wire        p_Irq_REMPTY_w;
            wire        p_Irq_RTRIG_w;
        // Bus control signal logic
            wire        FallingEdge_rd_w;       // the falling edge of the rd signal
            wire        ChipWriteAccess_w;      // The chip selected signal and write signal available together.
            wire        ChipReadAccess_w;       // The chip selected signal and read signal available together.
        // Register write access available
            wire        UartControl_Write_Access_w;
            wire        TxDataPort_Write_Access_w;
            wire        UartMode_Write_Access_w;
            wire        BaudGeneratorHigh_Write_Access_w;
            wire        BaudGeneratorLow_Write_Access_w;
            wire        BitCompensateMethod_Write_Access_w;
            wire        InterrputEnable1_Write_Access_w;
            wire        InterrputEnable2_Write_Access_w;
            wire        RxTrigLevelHigh_Write_Access_w;
            wire        RxTrigLevelLow_Write_Access_w;
            wire        TxTrigLevelHigh_Write_Access_w;
            wire        TxTrigLevelLow_Write_Access_w;
            wire        ReceiveTimeOutLvlHigh_Write_Access_w;
            wire        ReceiveTimeOutLvlLow_Write_Access_w;
            wire        InterruptStatus1_Write_Access_w;
            wire        InterruptStatus2_Write_Access_w;
        // Register read access available logic
            wire        UartControl_Read_Access_w;
            wire        UartStatus1_Read_Access_w;
            wire        UartStatus2_Read_Access_w;
            wire        RxDataPort_Read_Access_w;
            wire        UartMode_Read_Access_w;
            wire        BaudGeneratorHigh_Read_Access_w;
            wire        BaudGeneratorLow_Read_Access_w;
            wire        BitCompensateMethod_Read_Access_w;
            wire        InterruptMask1_Read_Access_w;
            wire        InterruptMask2_Read_Access_w;
            wire        RxTrigLevelHigh_Read_Access_w;
            wire        RxTrigLevelLow_Read_Access_w;
            wire        TxTrigLevelHigh_Read_Access_w;
            wire        TxTrigLevelLow_Read_Access_w;
            wire        ReceiveTimeOutLvlHigh_Read_Access_w;
            wire        ReceiveTimeOutLvlLow_Read_Access_w;
            wire        InterruptStatus1_Read_Access_w;
            wire        InterruptStatus2_Read_Access_w;
            wire        BytesNumberReceived1_Read_Access_w;
            wire        BytesNumberReceived2_Read_Access_w;
            wire        FrameFifoStatus_Read_Access_w;
            wire        FrameBytesNumberHigh_Read_Access_w;
            wire        FrameBytesNumberLow_Read_Access_w;
            wire        FrameTimeStampInfo1_Read_Access_w;
            wire        FrameTimeStampInfo2_Read_Access_w;
            wire        FrameAnsTimeInfo1_Read_Access_w;
            wire        FrameAnsTimeInfo2_Read_Access_w;
            wire        ReservedAddr3_Read_Access_w;
        // Rising edge detect logic
            wire        RisingEdge_TOVR_w;
            wire        RisingEdge_TNFUL_w;
            wire        RisingEdge_TTRIG_w;
            wire        RisingEdge_TIMEOUT_w;
            wire        RisingEdge_PARE_w;
            wire        RisingEdge_FRAME_w;
            wire        RisingEdge_ROVR_w;
            wire        RisingEdge_TFUL_w;
            wire        RisingEdge_TEMPTY_w;
            wire        RisingEdge_RFULL_w;
            wire        RisingEdge_REMPTY_w;
            wire        RisingEdge_RTRIG_w;
    // parameter
        // Address definition
            parameter   ADDR_UartControl                = 4'b0000;
            parameter   ADDR_UartStatus1                = 4'b0001;
            parameter   ADDR_UartStatus2                = 4'b0010;
            parameter   ADDR_RxDataPort                 = 4'b0011;
            parameter   ADDR_TxDataPort                 = 4'b0011;
            parameter   ADDR_UartMode                   = 4'b0100;
            parameter   ADDR_BaudGeneratorHigh          = 4'b0101;
            parameter   ADDR_BaudGeneratorLow           = 4'b0110;
            parameter   ADDR_BitCompensateMethod        = 4'b0111;
            parameter   ADDR_InterrputEnable1           = 4'b1000;
            parameter   ADDR_InterrputEnable2           = 4'b1001;
            parameter   ADDR_InterruptMask1             = 4'b1000;
            parameter   ADDR_InterruptMask2             = 4'b1001;
            parameter   ADDR_RxTrigLevelHigh            = 4'b1010;
            parameter   ADDR_RxTrigLevelLow             = 4'b1011;
            parameter   ADDR_TxTrigLevelHigh            = 4'b1100;
            parameter   ADDR_TxTrigLevelLow             = 4'b1101;
            parameter   ADDR_ReceiveTimeOutHigh         = 4'b1110;
            parameter   ADDR_ReceiveTimeOutLow          = 4'b1111;
            parameter   ADDR_InterruptStatus1           = 4'b0100;
            parameter   ADDR_InterruptStatus2           = 4'b0101;
            parameter   ADDR_BytesNumberReceived1       = 4'b0110;
            parameter   ADDR_BytesNumberReceived2       = 4'b0111;
            parameter   ADDR_FrameFifoStatus            = 4'b1000;
            parameter   ADDR_FrameBytesNumberHigh       = 4'b1001;
            parameter   ADDR_FrameBytesNumberLow        = 4'b1010;
            parameter   ADDR_FrameTimeStampInfo1        = 4'b1011;
            parameter   ADDR_FrameTimeStampInfo2        = 4'b1100;
            parameter   ADDR_FrameAnsTimeInfo1          = 4'b1101;
            parameter   ADDR_FrameAnsTimeInfo2          = 4'b1110;
            parameter   ADDR_ReservedAddr3              = 4'b1111;
        // Function definition
            parameter   ON      = 1'b1;
            parameter   OFF     = 1'b0;
            parameter   N_ON    = 1'b0;
            parameter   N_OFF   = 1'b1;
            // UartControl bit 
                // ConfigEN
                    parameter   UartControl_ConfigEn_ON     = 1'b1;   // In this state the cpu could access the uart port configuration register
                    parameter   UartControl_ConfigEn_OFF    = 1'b0;   // In this state the cpu access the uart port normal operation register
                // ClkSel
                    parameter   UartControl_ClkSel_Time1    = 1'b0;
                    parameter   UartControl_ClkSel_Time8    = 1'b1;
                // TxEn
                    parameter   UartControl_TxEn_ON         = 1'b1;
                    parameter   UartControl_TxEn_OFF        = 1'b0;
                // RxEn
                    parameter   UartControl_RxEn_On         = 1'b1;
                    parameter   UartControl_RxEn_OFF        = 1'b0;
            // UartMode bit definition
                // ModeSel  --UartMode Definition 
                    parameter   UartMode_NORMAL             = 4'b0001;    // Normal mode, tx port sends data and rx port receives data
                    parameter   UartMode_AUTO_ECHO          = 4'b0010;    // Automatic echo mode, rx port receives data and transfer to tx port
                    parameter   UartMode_LOCAL_LOOPBACK     = 4'b0100;    // Local loop-back mode, rx port connected to the tx port directly would not send out
                    parameter   UartMode_REMOTE_LOOPBACK    = 4'b1000;    // Remote loop-back mode, the input io and output io of uart was connected directly  
                // EndSel
                    parameter   UartMode_BIGEND             = 1'b1;
                    parameter   UartMode_LITTLEEND          = 1'b0;    
                // ParEn
                    parameter   UartMode_Parity_ENABLE      = 1'b1;
                    parameter   UartMode_Parity_DISABLE     = 1'b0;
                // ParSel
                    parameter   UartMode_ParSel_EVEN        = 1'b0;
                    parameter   UartMode_ParSel_ODD         = 1'b1;
            // Interrput bit definition
                // TOVR, Overflow interrupt of the tx fifo
                    parameter   IRQ_TOVR_ON                 = 1'b1;
                    parameter   IRQ_TOVR_OFF                = 1'b0;
                // TNFUL, Nearly Full Interrupt
                    parameter   IRQ_TNFUL_ON                = 1'b1;
                    parameter   IRQ_TNFUL_OFF               = 1'b0;
                // TTRIG, Trigger interrupt of the tx fifo
                    parameter   IRQ_TTRIG_ON                = 1'b1;
                    parameter   IRQ_TTRIG_OFF               = 1'b0;
                // TIMEOUT, Receiver Timeout Error Interrupt
                    parameter   IRQ_TIMEOUT_ON              = 1'b1;
                    parameter   IRQ_TIMEOUT_OFF             = 1'b0;
                // PARE, Receiver parity error interrupt 
                    parameter   IRQ_PARE_ON                 = 1'b1;
                    parameter   IRQ_PARE_OFF                = 1'b0;
                // FRAME, Receiver framing error interrupt, triggered whenever the receiver fails to detect a valid stop bit
                    parameter   IRQ_FRAME_ON                = 1'b1;
                    parameter   IRQ_FRAME_OFF               = 1'b0;
                // ROVR, Overflow interrupt of the rx fifo
                    parameter   IRQ_ROVR_ON                 = 1'b1;
                    parameter   IRQ_ROVR_OFF                = 1'b0;
                // TFUL, Full interrupt of the tx fifo
                    parameter   IRQ_TFUL_ON                 = 1'b1;
                    parameter   IRQ_TFUL_OFF                = 1'b0;
                // TEMPTY, Empty interrupt of the tx fifo
                    parameter   IRQ_TEMPTY_ON               = 1'b1;
                    parameter   IRQ_TEMPTY_OFF              = 1'b0;
                // RFULL, Full interrupt of the rx fifo
                    parameter   IRQ_RFULL_ON                = 1'b1;
                    parameter   IRQ_RFULL_OFF               = 1'b0;
                // REMPTY, Empty interrupt of the rx fifo
                    parameter   IRQ_REMPTY_ON               = 1'b1;
                    parameter   IRQ_REMPTY_OFF              = 1'b0;
                // RTRIG, Trigger interrupt of the rx fifo
                    parameter   IRQ_RTRIG_ON                = 1'b1;
                    parameter   IRQ_RTRIG_OFF               = 1'b0;
        // Default parameter -- BaudRateGen & BitCompensateMethod
            parameter       DEFAULT_PERIOD      = 16'd68;    // Best choice for the 115200bps
            parameter       DEFAULT_UP_TIME     = 4'd2;
            parameter       DEFAULT_DOWN_TIME   = 4'd3;
    // Logic assign definition
        // page control signal definition
            assign ConfigEn_w       = UartControl_r1[7];
        // control signal definition
            assign ClkSel_w         = UartControl_r1[4];
            assign RxEn_w           = UartControl_r1[3];
            assign TxEn_w           = UartControl_r1[2];
            assign ModeSel_w        = UartMode_r1[7:4];
            assign EndSel_w         = UartMode_r1[3];
            assign ParEn_w          = UartMode_r1[2];
            assign ParSel_w         = UartMode_r1[1];
        // Interrupt signal logic
            assign p_Irq_TOVR_w     = InterruptState_r1[12];
            assign p_Irq_TNFUL_w    = InterruptState_r1[11];
            assign p_Irq_TTRIG_w    = InterruptState_r1[10];
            assign p_Irq_TIMEOUT_w  = InterruptState_r1[8];
            assign p_Irq_PARE_w     = InterruptState_r1[7];
            assign p_Irq_FRAME_w    = InterruptState_r1[6];
            assign p_Irq_ROVR_w     = InterruptState_r1[5];
            assign p_Irq_TFUL_w     = InterruptState_r1[4];
            assign p_Irq_TEMPTY_w   = InterruptState_r1[3];
            assign p_Irq_RFULL_w    = InterruptState_r1[2];
            assign p_Irq_REMPTY_w   = InterruptState_r1[1];
            assign p_Irq_RTRIG_w    = InterruptState_r1[0];
        // Bus control signal logic 
            assign FallingEdge_rd_w                     = (n_ChipSelect_i == N_ON) && (shift_rd_r1[2] == N_OFF)&& (shift_rd_r1[1] == N_ON);     // the falling edge detect of the rd signal, 1~2 SYSCLK delay
            assign ChipWriteAccess_w                    = (n_ChipSelect_i == N_ON) && (n_we_i == N_ON);
            assign ChipReadAccess_w                     = (n_ChipSelect_i == N_ON) && (shift_rd_r1[2] == N_ON); // 2~3 SYSCLK delay
        // Register write access available logic definition
            assign UartControl_Write_Access_w           = ChipWriteAccess_w && (AddrBus_i == ADDR_UartControl           );
            assign TxDataPort_Write_Access_w            = ChipWriteAccess_w && (AddrBus_i == ADDR_TxDataPort            );
            assign UartMode_Write_Access_w              = ChipWriteAccess_w && (AddrBus_i == ADDR_UartMode              ) && (ConfigEn_w == ON  );
            assign BaudGeneratorHigh_Write_Access_w     = ChipWriteAccess_w && (AddrBus_i == ADDR_BaudGeneratorHigh     ) && (ConfigEn_w == ON  );
            assign BaudGeneratorLow_Write_Access_w      = ChipWriteAccess_w && (AddrBus_i == ADDR_BaudGeneratorLow      ) && (ConfigEn_w == ON  );
            assign BitCompensateMethod_Write_Access_w   = ChipWriteAccess_w && (AddrBus_i == ADDR_BitCompensateMethod   ) && (ConfigEn_w == ON  );
            assign InterrputEnable1_Write_Access_w      = ChipWriteAccess_w && (AddrBus_i == ADDR_InterrputEnable1      ) && (ConfigEn_w == ON  );
            assign InterrputEnable2_Write_Access_w      = ChipWriteAccess_w && (AddrBus_i == ADDR_InterrputEnable2      ) && (ConfigEn_w == ON  );
            assign RxTrigLevelHigh_Write_Access_w       = ChipWriteAccess_w && (AddrBus_i == ADDR_RxTrigLevelHigh       ) && (ConfigEn_w == ON  );
            assign RxTrigLevelLow_Write_Access_w        = ChipWriteAccess_w && (AddrBus_i == ADDR_RxTrigLevelLow        ) && (ConfigEn_w == ON  );
            assign TxTrigLevelHigh_Write_Access_w       = ChipWriteAccess_w && (AddrBus_i == ADDR_TxTrigLevelHigh       ) && (ConfigEn_w == ON  );
            assign TxTrigLevelLow_Write_Access_w        = ChipWriteAccess_w && (AddrBus_i == ADDR_TxTrigLevelLow        ) && (ConfigEn_w == ON  );
            assign ReceiveTimeOutLvlHigh_Write_Access_w = ChipWriteAccess_w && (AddrBus_i == ADDR_ReceiveTimeOutHigh    ) && (ConfigEn_w == ON  );
            assign ReceiveTimeOutLvlLow_Write_Access_w  = ChipWriteAccess_w && (AddrBus_i == ADDR_ReceiveTimeOutLow     ) && (ConfigEn_w == ON  );
            assign InterruptStatus1_Write_Access_w      = ChipWriteAccess_w && (AddrBus_i == ADDR_InterruptStatus1      ) && (ConfigEn_w == OFF );
            assign InterruptStatus2_Write_Access_w      = ChipWriteAccess_w && (AddrBus_i == ADDR_InterrputEnable2      ) && (ConfigEn_w == OFF );           
        // Register read access available logic definition
            assign UartControl_Read_Access_w            = ChipReadAccess_w  && (AddrBus_i == ADDR_UartControl           );
            assign UartStatus1_Read_Access_w            = ChipReadAccess_w  && (AddrBus_i == ADDR_UartStatus1           );
            assign UartStatus2_Read_Access_w            = ChipReadAccess_w  && (AddrBus_i == ADDR_UartStatus2           );
            assign RxDataPort_Read_Access_w             = ChipReadAccess_w  && (AddrBus_i == ADDR_RxDataPort            );
            assign UartMode_Read_Access_w               = ChipReadAccess_w  && (AddrBus_i == ADDR_UartMode              ) && (ConfigEn_w == ON  );
            assign BaudGeneratorHigh_Read_Access_w      = ChipReadAccess_w  && (AddrBus_i == ADDR_BaudGeneratorHigh     ) && (ConfigEn_w == ON  );
            assign BaudGeneratorLow_Read_Access_w       = ChipReadAccess_w  && (AddrBus_i == ADDR_BaudGeneratorLow      ) && (ConfigEn_w == ON  );
            assign BitCompensateMethod_Read_Access_w    = ChipReadAccess_w  && (AddrBus_i == ADDR_BitCompensateMethod   ) && (ConfigEn_w == ON  );
            assign InterruptMask1_Read_Access_w         = ChipReadAccess_w  && (AddrBus_i == ADDR_InterruptMask1        ) && (ConfigEn_w == ON  );
            assign InterruptMask2_Read_Access_w         = ChipReadAccess_w  && (AddrBus_i == ADDR_InterruptMask2        ) && (ConfigEn_w == ON  );
            assign RxTrigLevelHigh_Read_Access_w        = ChipReadAccess_w  && (AddrBus_i == ADDR_RxTrigLevelHigh       ) && (ConfigEn_w == ON  );
            assign RxTrigLevelLow_Read_Access_w         = ChipReadAccess_w  && (AddrBus_i == ADDR_RxTrigLevelLow        ) && (ConfigEn_w == ON  );
            assign TxTrigLevelHigh_Read_Access_w        = ChipReadAccess_w  && (AddrBus_i == ADDR_TxTrigLevelHigh       ) && (ConfigEn_w == ON  );
            assign TxTrigLevelLow_Read_Access_w         = ChipReadAccess_w  && (AddrBus_i == ADDR_TxTrigLevelLow        ) && (ConfigEn_w == ON  );
            assign ReceiveTimeOutLvlHigh_Read_Access_w  = ChipReadAccess_w  && (AddrBus_i == ADDR_ReceiveTimeOutHigh    ) && (ConfigEn_w == ON  );
            assign ReceiveTimeOutLvlLow_Read_Access_w   = ChipReadAccess_w  && (AddrBus_i == ADDR_ReceiveTimeOutLow     ) && (ConfigEn_w == ON  );
            assign InterruptStatus1_Read_Access_w       = ChipReadAccess_w  && (AddrBus_i == ADDR_InterruptStatus1      ) && (ConfigEn_w == OFF );
            assign InterruptStatus2_Read_Access_w       = ChipReadAccess_w  && (AddrBus_i == ADDR_InterruptStatus2      ) && (ConfigEn_w == OFF );
            assign BytesNumberReceived1_Read_Access_w   = ChipReadAccess_w  && (AddrBus_i == ADDR_BytesNumberReceived1  ) && (ConfigEn_w == OFF );
            assign BytesNumberReceived2_Read_Access_w   = ChipReadAccess_w  && (AddrBus_i == ADDR_BytesNumberReceived2  ) && (ConfigEn_w == OFF );
            assign FrameFifoStatus_Read_Access_w        = ChipReadAccess_w  && (AddrBus_i == ADDR_FrameFifoStatus       ) && (ConfigEn_w == OFF );
            assign FrameBytesNumberHigh_Read_Access_w   = ChipReadAccess_w  && (AddrBus_i == ADDR_FrameBytesNumberHigh  ) && (ConfigEn_w == OFF );
            assign FrameBytesNumberLow_Read_Access_w    = ChipReadAccess_w  && (AddrBus_i == ADDR_FrameBytesNumberLow   ) && (ConfigEn_w == OFF );
            assign FrameTimeStampInfo1_Read_Access_w    = ChipReadAccess_w  && (AddrBus_i == ADDR_FrameTimeStampInfo1   ) && (ConfigEn_w == OFF );
            assign FrameTimeStampInfo2_Read_Access_w    = ChipReadAccess_w  && (AddrBus_i == ADDR_FrameTimeStampInfo2   ) && (ConfigEn_w == OFF );
            assign FrameAnsTimeInfo1_Read_Access_w      = ChipReadAccess_w  && (AddrBus_i == ADDR_FrameAnsTimeInfo1     ) && (ConfigEn_w == OFF );
            assign FrameAnsTimeInfo2_Read_Access_w      = ChipReadAccess_w  && (AddrBus_i == ADDR_FrameAnsTimeInfo2     ) && (ConfigEn_w == OFF );
            assign ReservedAddr3_Read_Access_w          = ChipReadAccess_w  && (AddrBus_i == ADDR_ReservedAddr3         ) && (ConfigEn_w == OFF );            
        // output port logic definition
            assign DataBus_o            = DataBus_r1;
            assign p_TxCoreEn_o         = TxEn_w;
            assign TxData_o             = DataBus_i;
            assign n_TxFIFO_We_o        = ~((TxFIFO_We_r1[2] == N_OFF) && (TxFIFO_We_r1[1] == N_ON) && (AddrBus_i == ADDR_TxDataPort));     // falling edge of the TxDataPort_Write_Access_w trigger the write operation
            assign n_TxFIFO_Clr_o       = ~p_TxRst_r1; 
            assign p_RxCoreEn_o         = RxEn_w;
            assign n_RxFIFO_Rd_o        = ~((FallingEdge_rd_w == ON) && (AddrBus_i == ADDR_RxDataPort));    // the read signal is generated from the bus access 
            assign n_RxFIFO_Clr_o       = ~p_RxRst_r1;
            assign BaudRateGen_o        = BaudGenerator_r1;
            assign RoundUpNum_o         = BitCompensateMethod_r1[7:4];
            assign RoundDownNum_o       = BitCompensateMethod_r1[3:0];
            assign BaudDivider_o        = BaudDivider_r1;
            assign p_IrqSig_o           =       InterruptState_r1[12]       // TOVR
                                            |   InterruptState_r1[11]       // TNFUL
                                            |   InterruptState_r1[10]       // TTRIG
                                            |   InterruptState_r1[08]       // TIMEOUT
                                            |   InterruptState_r1[07]       // PARE
                                            |   InterruptState_r1[06]       // FRAME
                                            |   InterruptState_r1[05]       // ROVR
                                            |   InterruptState_r1[04]       // TFUL
                                            |   InterruptState_r1[03]       // TEMPTY
                                            |   InterruptState_r1[02]       // RFULL
                                            |   InterruptState_r1[01]       // REMPTY
                                            |   InterruptState_r1[00];      // RTRIG
            // assign p_RxFrame_Func_En_o  = ;
            // assign n_RxFrameInfo_Rd_o   = ;   // the read signal generated from the bus access
            assign p_ParityEnable_o     = ParEn_w;
            assign p_BigEnd_o           = EndSel_w;
            assign ParityMethod_o       = ParSel_w;
        // Rising edge detect logic
            assign RisingEdge_TOVR_w    = (shift_TOVR_r1[2]     == OFF) && (shift_TOVR_r1[1]     == ON);
            assign RisingEdge_TNFUL_w   = (shift_TNFUL_r1[2]    == OFF) && (shift_TNFUL_r1[1]    == ON);
            assign RisingEdge_TTRIG_w   = (shift_TTRIG_r1[2]    == OFF) && (shift_TTRIG_r1[1]    == ON);
            assign RisingEdge_TIMEOUT_w = (shift_TIMEOUT_r1[2]  == OFF) && (shift_TIMEOUT_r1[1]  == ON);
            assign RisingEdge_TFUL_w    = (shift_TFUL_r1[2]     == OFF) && (shift_TFUL_r1[1]     == ON);
            assign RisingEdge_PARE_w    = (shift_ParityErr_r1[2]== OFF) && (shift_ParityErr_r1[1]== ON);
            assign RisingEdge_ROVR_w    = (shift_ROVR_r1[2]     == OFF) && (shift_ROVR_r1[1]     == ON);
            assign RisingEdge_FRAME_w   = (shift_FrameErr_r1[2] == OFF) && (shift_FrameErr_r1[1] == ON);
            assign RisingEdge_TEMPTY_w  = (shift_TEMPTY_r1[2]   == OFF) && (shift_TEMPTY_r1[1]   == ON);
            assign RisingEdge_RFULL_w   = (shift_RFULL_r1[2]    == OFF) && (shift_RFULL_r1[1]    == ON);
            assign RisingEdge_REMPTY_w  = (shift_REMPTY_r1[2]   == OFF) && (shift_REMPTY_r1[1]   == ON);
            assign RisingEdge_RTRIG_w   = (shift_RTRIG_r1[2]    == OFF) && (shift_RTRIG_r1[1]    == ON);
    // n_rd_i shift register detect
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                shift_rd_r1 <= 3'b111;
            end
            else begin
                shift_rd_r1 <= {shift_rd_r1[1:0],n_rd_i};
            end
        end
    // UartControl register fresh 
        always @(posedge clk or negedge rst) begin
            if (!rst) begin    // Initial state
                UartControl_r1  <= {    UartControl_ConfigEn_ON,    OFF,                    OFF,    UartControl_ClkSel_Time1,
                                        UartControl_RxEn_OFF,       UartControl_TxEn_OFF,   OFF,    OFF
                                    };
                p_RxRst_r1      <= OFF;
                p_TxRst_r1      <= OFF;                              
            end
            else if (UartControl_Write_Access_w == ON ) begin
                UartControl_r1  <= {DataBus_i[7:2],2'b00};
                p_RxRst_r1      <= DataBus_i[1];
                p_TxRst_r1      <= DataBus_i[0];  
            end
            else begin
                UartControl_r1  <= UartControl_r1;
                p_RxRst_r1      <= OFF;
                p_TxRst_r1      <= OFF; 
            end
        end
    // UartMode register fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin   // Initial state
                UartMode_r1     <= {UartMode_LOCAL_LOOPBACK,    UartMode_BIGEND,
                                    UartMode_Parity_DISABLE,    UartMode_ParSel_EVEN,
                                    1'b0};                
            end
            else if (UartMode_Write_Access_w == ON ) begin
                UartMode_r1     <= DataBus_i;
            end
            else begin
                UartMode_r1     <= UartMode_r1;
            end
        end
    // BaudGenerator register fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                BaudGenerator_r1[15:8] <= DEFAULT_PERIOD[15:8];
            end
            else if (BaudGeneratorHigh_Write_Access_w == ON ) begin
                BaudGenerator_r1[15:8] <= DataBus_i;
            end
            else begin
                BaudGenerator_r1[15:8] <= BaudGenerator_r1[15:8];
            end
        end
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                BaudGenerator_r1[7:0]  <= DEFAULT_PERIOD[7:0];
            end
            else if (BaudGeneratorLow_Write_Access_w == ON ) begin
                BaudGenerator_r1[7:0]  <= DataBus_i;
            end
            else begin
                BaudGenerator_r1[7:0]  <= BaudGenerator_r1[7:0];
            end
        end
    // BitCompensateMethod register fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                BitCompensateMethod_r1 <= {DEFAULT_UP_TIME, DEFAULT_DOWN_TIME};
                BaudDivider_r1         <= DEFAULT_UP_TIME + DEFAULT_DOWN_TIME;
            end
            else if (BitCompensateMethod_Write_Access_w == ON ) begin
                BitCompensateMethod_r1 <= DataBus_i;
                BaudDivider_r1         <= DataBus_i[7:4] + DataBus_i[3:0];
            end
            else begin
                BitCompensateMethod_r1 <= BitCompensateMethod_r1;
                BaudDivider_r1         <= BaudDivider_r1;
            end
        end
    // InterrputEnable1/InterruptMask_r1 register fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                InterruptMask_r1[15:8] <= {
                    1'b0,           1'b0,           1'b0,   IRQ_TOVR_OFF,
                    IRQ_TNFUL_OFF,  IRQ_TTRIG_OFF,  1'b0,   IRQ_TIMEOUT_OFF
                };    
            end
            else if (InterrputEnable1_Write_Access_w == ON ) begin
                InterruptMask_r1[15:8] <= DataBus_i;
            end
            else begin
                InterruptMask_r1[15:8] <= InterruptMask_r1[15:8];
            end
        end
    // InterrputEnable2/InterruptMask_r1 register fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                InterruptMask_r1[7:0] <= {
                    IRQ_PARE_OFF,   IRQ_FRAME_OFF,  IRQ_ROVR_OFF,   IRQ_TFUL_OFF,
                    IRQ_TEMPTY_OFF, IRQ_RFULL_OFF,  IRQ_REMPTY_OFF, IRQ_RTRIG_OFF
                };    
            end
            else if (InterrputEnable2_Write_Access_w == ON ) begin
                InterruptMask_r1[7:0] <= DataBus_i;
            end
            else begin
                InterruptMask_r1[7:0] <= InterruptMask_r1[7:0];
            end
        end
    // RxTrigLevel_r1 register  fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                RxTrigLevel_r1[15:8] <= 8'h00;
            end
            else if (RxTrigLevelHigh_Write_Access_w == ON ) begin
                RxTrigLevel_r1[15:8] <= DataBus_i;
            end
            else begin
                RxTrigLevel_r1[15:8] <=  RxTrigLevel_r1[15:8];
            end
        end
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                RxTrigLevel_r1[7:0] <= 8'h00;
            end
            else if (RxTrigLevelLow_Write_Access_w == ON ) begin
                RxTrigLevel_r1[7:0] <= DataBus_i;
            end
            else begin
                RxTrigLevel_r1[7:0] <= RxTrigLevel_r1[7:0];
            end
        end
    // Transmit register fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                TxTrigLevel_r1[15:8] <= 8'h00;
            end
            else if (TxTrigLevelHigh_Write_Access_w == ON ) begin
                TxTrigLevel_r1[15:8] <= DataBus_i;
            end
            else begin
                TxTrigLevel_r1[15:8] <= TxTrigLevel_r1[15:8];
            end
        end
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                TxTrigLevel_r1[7:0] <= 8'h00;                
            end
            else if (TxTrigLevelLow_Write_Access_w == ON ) begin
                TxTrigLevel_r1[7:0] <= DataBus_i;
            end
            else begin
                TxTrigLevel_r1[7:0] <= TxTrigLevel_r1[7:0];
            end
        end
    // TxData fresh, generate the TX FIFO WR signal
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                TxFIFO_We_r1   <= {N_OFF, N_OFF, N_OFF};
            end
            else if (TxDataPort_Write_Access_w == ON) begin
                TxFIFO_We_r1   <= {TxFIFO_We_r1[1:0], N_ON};
            end
            else begin
                TxFIFO_We_r1   <= {TxFIFO_We_r1[1:0], N_OFF};
            end
        end
    // Bytes number in fifo fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                BytesNumberInRxFifo_r1 <= 16'd0;              
            end
            else if (RxEn_w == ON ) begin
                BytesNumberInRxFifo_r1 <= RxFIFO_Level_i;
            end
            else begin
                BytesNumberInRxFifo_r1 <= 16'd0;
            end
        end
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                BytesNumberInTxFifo_r1 <= 16'd0; 
            end
            else if (TxEn_w == ON ) begin
                BytesNumberInTxFifo_r1 <= TxFIFO_Level_i;
            end
            else begin
                BytesNumberInTxFifo_r1 <= 16'd0;
            end
        end
    // Receive Time Out buffer fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                ReceiveTimeOutLvl_r1[15:8] <= 8'd0;
            end
            else if (ReceiveTimeOutLvlHigh_Write_Access_w == ON ) begin
                ReceiveTimeOutLvl_r1[15:8] <= DataBus_i;
            end
            else begin
                ReceiveTimeOutLvl_r1[15:8] <= ReceiveTimeOutLvl_r1[15:8];
            end
        end
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                ReceiveTimeOutLvl_r1[7:0] <= 8'd0;
            end
            else if (ReceiveTimeOutLvlLow_Write_Access_w == ON ) begin
                ReceiveTimeOutLvl_r1[7:0] <= DataBus_i;
            end
            else begin
                ReceiveTimeOutLvl_r1[7:0] <= ReceiveTimeOutLvl_r1[7:0];
            end
        end
    // Bus Read data operation 
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                DataBus_r1 <= 8'hff;              
            end
            else if (UartControl_Read_Access_w == ON) begin
                DataBus_r1 <= UartControl_r1;
            end
            else if (UartStatus1_Read_Access_w == ON ) begin
                DataBus_r1 <= UartState_r1[15:8];
            end
            else if (UartStatus2_Read_Access_w == ON ) begin
                DataBus_r1 <= UartState_r1[7:0];
            end
            else if (RxDataPort_Read_Access_w == ON) begin
                // think about the 
            end
            else if (UartMode_Read_Access_w == ON ) begin
                DataBus_r1 <= UartMode_r1;
            end
            else if (BaudGeneratorHigh_Read_Access_w == ON ) begin
                DataBus_r1 <= BaudGenerator_r1[15:8];
            end
            else if (BaudGeneratorLow_Read_Access_w == ON ) begin
                DataBus_r1 <= BaudGenerator_r1[7:0];
            end
            else if (BitCompensateMethod_Read_Access_w == ON ) begin
                DataBus_r1 <= BitCompensateMethod_r1;
            end
            else if (InterruptMask1_Read_Access_w == ON ) begin
                DataBus_r1 <= InterruptMask_r1[15:8];
            end
            else if (InterruptMask2_Read_Access_w == ON ) begin
                DataBus_r1 <= InterruptMask_r1[7:0];
            end
            else if (RxTrigLevelHigh_Read_Access_w == ON ) begin
                DataBus_r1 <= RxTrigLevel_r1[15:8];
            end
            else if (RxTrigLevelLow_Read_Access_w == ON ) begin
                DataBus_r1 <= RxTrigLevel_r1[7:0];
            end
            else if (TxTrigLevelHigh_Read_Access_w == ON ) begin
                DataBus_r1 <= TxTrigLevel_r1[15:8];
            end
            else if (TxTrigLevelLow_Read_Access_w == ON ) begin
                DataBus_r1 <= TxTrigLevel_r1[7:0];
            end
            else if (ReceiveTimeOutLvlHigh_Read_Access_w == ON ) begin
                DataBus_r1 <= ReceiveTimeOutLvl_r1[15:8];
            end
            else if (ReceiveTimeOutLvlLow_Read_Access_w == ON ) begin
                DataBus_r1 <= ReceiveTimeOutLvl_r1[7:0];
            end
            else if (InterruptStatus1_Read_Access_w == ON ) begin
                DataBus_r1 <= InterruptState_r1[15:8];
            end
            else if (InterruptStatus2_Read_Access_w == ON ) begin
                DataBus_r1 <= InterruptState_r1[7:0];
            end
            else if (BytesNumberReceived1_Read_Access_w == ON ) begin
                DataBus_r1 <= BytesNumberInRxFifo_r1[15:8];
            end
            else if (BytesNumberReceived2_Read_Access_w == ON ) begin
                DataBus_r1 <= BytesNumberInRxFifo_r1[7:0];
            end
            else if (FrameFifoStatus_Read_Access_w == ON ) begin
                // Think about it 
            end
            else if (FrameBytesNumberHigh_Read_Access_w == ON ) begin
                // Think about it 
            end
            else if (FrameBytesNumberLow_Read_Access_w == ON ) begin
                // Think about the fifo operation
            end
            else if (FrameTimeStampInfo1_Read_Access_w == ON ) begin
                // Think about the fifo operation
            end
            else if (FrameTimeStampInfo2_Read_Access_w == ON ) begin
                // Think about the fifo operation
            end
            else if (FrameAnsTimeInfo1_Read_Access_w == ON ) begin
                DataBus_r1 <= AnsDelayTime_i[15:8];
            end
            else if (FrameAnsTimeInfo2_Read_Access_w == ON ) begin
                DataBus_r1 <= AnsDelayTime_i[7:0];
            end
            else if (ReservedAddr3_Read_Access_w == ON ) begin
                // Think about the fifo operation
            end
            
         end 
    // Interrupt Status and Signal generator, the status register is sticky.
        // port input interrupt signal detect, shift register 
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    shift_TOVR_r1       <= 3'b0;
                    shift_TNFUL_r1      <= 3'b0;
                    shift_TTRIG_r1      <= 3'b0;
                    shift_TIMEOUT_r1    <= 3'b0;
                    shift_ParityErr_r1  <= 3'b0;
                    shift_FrameErr_r1   <= 3'b0;
                    shift_TFUL_r1       <= 3'b0;
                    shift_TEMPTY_r1     <= 3'b0;
                    shift_RFULL_r1      <= 3'b0;
                    shift_REMPTY_r1     <= 3'b0;
                end
                else begin
                    shift_TOVR_r1       <= {shift_TOVR_r1[1:0],         p_TxFIFO_Over_i};
                    shift_TNFUL_r1      <= {shift_TNFUL_r1[1:0],        p_TxFIFO_NearFull_i};
                    shift_TTRIG_r1      <= {shift_TTRIG_r1[1:0],        ((BytesNumberInRxFifo_r1 >= TxTrigLevel_r1)&(TxTrigLevel_r1!=16'd0))}; // bytes number in fifo over the level and the level is not 0!
                    shift_TIMEOUT_r1    <= {shift_TIMEOUT_r1[1:0],      p_RxTimeOut_i};
                    shift_ParityErr_r1  <= {shift_ParityErr_r1[1:0],    p_RxParityErr_i};
                    shift_FrameErr_r1   <= {shift_FrameErr_r1[1:0],     p_RxFrameErr_i};
                    shift_TFUL_r1       <= {shift_TFUL_r1[1:0],         p_TxFIFO_Full_i};
                    shift_TEMPTY_r1     <= {shift_TEMPTY_r1[1:0],       p_TxFIFO_Empty_i};
                    shift_RFULL_r1      <= {shift_TFUL_r1[1:0],         p_RxFIFO_Full_i};
                    shift_REMPTY_r1     <= {shift_REMPTY_r1[1:0],       p_RxFIFO_Empty_i};
                end
            end
        // TOVR, transmission fifo overflow interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[12] <= IRQ_TOVR_OFF;   // no interrupt generate
                end
                else if (RisingEdge_TOVR_w == ON) begin // the overflow of the tx fifo occurs
                    InterruptState_r1[12] <= IRQ_TOVR_ON && InterruptMask_r1[12];   // the interrupt state established
                end
                else if (InterruptStatus1_Write_Access_w == ON) begin  // write "1" to clear the bit
                    InterruptState_r1[12] <= DataBus_i[4]?IRQ_TOVR_OFF:InterruptState_r1[12];
                end
                else begin
                    InterruptState_r1[12] <= InterruptState_r1[12];
                end
            end
        // TNFUL, transmission fifo near full interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[11] <= IRQ_TNFUL_OFF; // initial state                    
                end
                else if (RisingEdge_TNFUL_w == ON) begin   // the tx fifo near full interrupt occurs
                    InterruptState_r1[11] <= IRQ_TNFUL_ON && InterruptMask_r1[11];
                end
                else if (InterruptStatus1_Write_Access_w == ON) begin // clear the tx fifo near full interrupt
                    InterruptState_r1[11] <= DataBus_i[3]?IRQ_TNFUL_OFF:InterruptState_r1[11];
                end
                else begin
                    InterruptState_r1[11] <= InterruptState_r1[11];
                end
            end
        // TTRIG, transmission fifo trigger interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[10] <= IRQ_TTRIG_OFF;
                end
                else if (RisingEdge_TTRIG_w == ON) begin // Transmission fifo bytes number great than the level, and the level is not 0
                    InterruptState_r1[10] <= IRQ_TTRIG_ON && InterruptMask_r1[10];
                end
                else if (InterruptStatus1_Write_Access_w == ON ) begin  // clear the interrupt
                    InterruptState_r1[10] <= DataBus_i[2]?IRQ_TTRIG_OFF:InterruptState_r1[10];
                end
                else begin
                    InterruptState_r1[10] <= InterruptState_r1[10];
                end
            end
        // TIMEOUT, receive module receive interval time out
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[8] <= IRQ_TIMEOUT_OFF;                   
                end
                else if (RisingEdge_TIMEOUT_w ==  ON ) begin // Time out interrupt occur
                    InterruptState_r1[8] <= IRQ_TIMEOUT_ON && InterruptMask_r1[8];
                end
                else if (InterruptStatus1_Write_Access_w == ON ) begin // clear the interrupt
                    InterruptState_r1[8] <= DataBus_i[0]?IRQ_TIMEOUT_OFF:InterruptState_r1[8];
                end
                else begin
                    InterruptState_r1[8] <= InterruptState_r1[8];
                end
            end
        // PARE, receive module parity check fail interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[7] <= IRQ_PARE_OFF;
                end
                else if (RisingEdge_PARE_w == ON ) begin  // the parity error interrupt occur
                    InterruptState_r1[7] <= IRQ_PARE_ON && InterruptMask_r1[7];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin // clear the interrupt
                    InterruptState_r1[7] <= DataBus_i[7]?IRQ_PARE_OFF:InterruptState_r1[7];
                end
                else begin
                    InterruptState_r1[7] <= InterruptState_r1[7];
                end
            end
        // FRAME, receive module frame error, stop bit missing
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[6] <= IRQ_FRAME_OFF;
                end
                else if (RisingEdge_FRAME_w == ON) begin // Byte missing the stop bit occur
                    InterruptState_r1[6] <= IRQ_FRAME_ON && InterruptMask_r1[6];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin // clear the interrupt
                    InterruptState_r1[6] <= DataBus_i[6]?IRQ_FRAME_OFF:InterruptState_r1[6];
                end
                else begin
                    InterruptState_r1[6] <= InterruptState_r1[6];
                end
            end
        // ROVR, receive fifo overflow interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[5] <= IRQ_ROVR_OFF;                  
                end
                else if (RisingEdge_ROVR_w == ON ) begin // receive fifo overflow interrupt occur
                    InterruptState_r1[5] <= IRQ_ROVR_ON && InterruptMask_r1[5];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin // clear the interrupt
                    InterruptState_r1[5] <= DataBus_i[5]?IRQ_ROVR_OFF:InterruptState_r1[5];
                end
                else begin
                    InterruptState_r1[5] <= InterruptState_r1[5];
                end
            end
        // TFUL, transmit fifo full interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[4] <= IRQ_TFUL_OFF;
                end
                else if (RisingEdge_TFUL_w == ON ) begin // transmit fifo full interrupt occur
                    InterruptState_r1[4] <= IRQ_TFUL_ON && InterruptMask_r1[4];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin // clear interrupt
                    InterruptState_r1[4] <= DataBus_i[4]?IRQ_TFUL_OFF:InterruptState_r1[4];
                end
                else begin
                    InterruptState_r1[4] <= InterruptState_r1[4];
                end
            end
        // TEMPTY, transmit fifo empty interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[3] <= IRQ_TEMPTY_OFF;                    
                end
                else if (RisingEdge_TEMPTY_w == ON ) begin
                    InterruptState_r1[3] <= IRQ_TEMPTY_ON && InterruptMask_r1[3];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin
                    InterruptState_r1[3] <= DataBus_i[3]?IRQ_TEMPTY_OFF:InterruptState_r1[3];
                end
                else begin
                    InterruptState_r1[3] <= InterruptState_r1[3];
                end
            end
        // RFULL, receive fifo full interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[2] <= IRQ_RFULL_OFF;
                end
                else if (RisingEdge_RFULL_w == ON ) begin
                    InterruptState_r1[2] <= IRQ_RFULL_ON && InterruptMask_r1[2];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin
                    InterruptState_r1[2] <= DataBus_i[2]?IRQ_RFULL_OFF:InterruptState_r1[2];
                end
                else begin
                    InterruptState_r1[2] <= InterruptState_r1[2];
                end
            end
        // REMPTY, receive fifo empty interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[1] <= IRQ_REMPTY_OFF;
                end
                else if (RisingEdge_REMPTY_w == ON ) begin
                    InterruptState_r1[1] <= IRQ_REMPTY_ON && InterruptMask_r1[1];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin
                    InterruptState_r1[1] <= DataBus_i[2]?IRQ_REMPTY_OFF:InterruptState_r1[1];
                end
                else begin
                    InterruptState_r1[1] <= InterruptState_r1[1];
                end
            end
        // RTRIG, receive bytes number trigger interrupt
            always @(posedge clk or negedge rst) begin
                if (!rst) begin
                    InterruptState_r1[0] <= IRQ_RTRIG_OFF;                    
                end
                else if (RisingEdge_RTRIG_w == ON ) begin
                    InterruptState_r1[0] <= IRQ_RTRIG_ON && InterruptMask_r1[0];
                end
                else if (InterruptStatus2_Write_Access_w == ON ) begin
                    InterruptState_r1[0] <= DataBus_i[0]?IRQ_RTRIG_ON:InterruptState_r1[0];
                end
                else begin
                    InterruptState_r1[0] <= InterruptState_r1[0];
                end
            end
endmodule
