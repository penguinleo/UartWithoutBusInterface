// -----------------------------------------------------------------------------
// Copyright (c) 2014-2019 All rights reserved
// -----------------------------------------------------------------------------
// Author : Javen   penguinleo@163.com
// File   : BaudrateModule_Simplified.v
// Create : 2019-12-31 18:54:53
// Revise : 2019-12-31 18:54:53
// Editor : sublime text3, tab size (4)
// Comment: this module is designed to generate the baudrate signal and acquisition signal
//          which consider the bit width error compensation and ignore the byte compensat-
//          -ion. The byte compensation will be introduced into the system in next version.
//          The acquisition time in a bit period is the sum of PosCompensation_i[7:4] and 
//          PosCompensation_i[3:0].
//          The error of the BaudSig signal should be equal than 1 system clk.
//          The compensation method as below.
//          To be honest, the simplest way to implement a serial communication core in the 
//          system is choosing an appropriate crystal for the serial communication core. But
//          this method would reduce the flexibility of the module. 
//          In this proj, we try to implement the serial communication core with the system 
//          clock, and try to compensate the error to 1 system clock.
//          Principle I: For 1 baudrate signal generate, the most acqurate way is using a reg
//                      counting from zero to the limitation(the limitation is defined by the
//                      divide relationship between the system clock frequency and the required
//                      baudrate frequency).
//              For example:    40MHz system clock, 
//                              115200bps baudrate.
//                          The bit time of the baudrate signal is about 8.680556us
//                          while the time of the system clock is 25ns.
//                          So when the count limit is 347, the error would be -5.556ns.
//                          when the count limit is 348, the error would be 19.444ns.
//          We using the AcqSig to improve the reliablity of the rx core. The AcqSig would be
//          2 times of the BaudSig or more. The maximum time is 16 time.
//              So the example should be:   40MHz system clock, 
//                                          115200bps baudrate, 
//                                          16x acquisite frequency.
//                                          The bit time is about 8.680556us;
//                                          The system clock is 25ns;
//                                          The acquisition period is 542.5347ns;
//                                          For the acquisition period, the counter limit result:
//                                              22, the actual period is 550ns(round up), error 7.4653ns;
//                                              21, the actual period is 525ns(round down), error ‭-17.5347‬ns;
//                                          Then the baudrate signal would be the accumulative error of
//                                          the 16 times acquisition period error.
//                          acq index |00|01|02|03|04|05|06|07|08|09|10|11|12|13|14|15| 
//              acq period Method 1   |22|22|22|22|22|22|22|22|22|22|22|22|22|22|22|22| baud period error ‭‭119.4448‬ns Up:Down=16:0
//              acq period Method 2   |21|21|21|21|21|21|21|21|21|21|21|21|21|21|21|21| baud period error ‭-280.5552‬ns Up:Down=0:16
//              acq period Method 3   |22|22|22|22|22|22|22|21|22|21|22|21|22|21|22|21| baud period error 5.5559ns Up:Down=11:5
//              acq period Method 4   |22|22|22|22|22|21|22|21|22|21|22|21|22|21|22|21| baud period error -30.5532ns Up:Down=10:6
//              Thus, the Method 3 is the best choice. Up:Down = 11:5
//          Up module:
//              UartCore
//          Sub module:
//              None
// Input Signal List:
//      1   |   clk                     :   clock signal
//      2   |   rst                     :   reset signal, negative enable.
//      3   |   AcqPeriod_i[11:0]       :   The acquisition signal period counting on the system
//                                          clock signal.
//      4   |   BitCompensation_i[7:0]  :   Bit compensation give out the compensate method. The 
//                                          high 4 bits control the number of the period with the 
//                                          round up counting limit; while the low 4 bits control 
//                                          the number of the period with the round down counting 
//                                          limit.
// Output Signal List:
//      1   |   AcqSig_o                :   The acquisite signal generated for the RX core;
//      2   |   BaudSig_o               :   The baudrate signal generated for the TX core;
// Note:  
// 
// -----------------------------------------------------------------------------   
module BaudrateModule_ver2(
        input               clk,            //System input clock signal
        input               rst,            //System reset signal
    // The Acquisition Parameter definition
        input   [15:0]  AcqPeriod_i,        //The acquisition period base on the system clk
    // The relationship between Acq and Baudrate
        input   [7:0]   BitCompensation_i,  //The compensation method, which result in bit width over limit, just put the minimum width error method! 
    // The input and output control signal
        output          AcqSig_o,    //Rx port acquisite signal
        output          BaudSig_o    //Tx port singal frequency
    );
    // Register definition
        // input buffer
            reg     [15:0]  acq_period_down_r;              // the data is come from the AcqPeriod_i   
            reg     [15:0]  acq_period_up_r;                // the data is equal with AcqPeriod_i + 1
            reg     [3:0]   acq_up_time_limit_r;            // the period round up times, it is the PosCompensation_i[7:4]
            reg     [3:0]   acq_down_time_limit_r;          // the period round down times,it is the PosCompensation_i[3:0]
        // divider to generate the baudrate signal from the acquisition signal, the baud_divider_r = acq_num_counter_r + comp_num_counter_r
            reg     [15:0]  acq_period_limit_r;             // it is choosen from the acq_period_down_r and acq_period_up_r
            reg     [15:0]  acq_period_counter_r;           // the counter for the period 
            reg     [3:0]   acq_down_time_cnt_r;            // the divider for the baud sig, count the normal acq signal, Note this counter count down from the limit to zero 
            reg     [3:0]   acq_up_time_cnt_r;              // the divider for the baud sig, count the compensated acq signal,Note this counter count down from the limit to zero    
            reg             acqsig_r;                       // the register of acquisition signal, which only last 1 clock
            reg             baudsig_r;                      // the register of the baudrate signal, which only last 1 clock
        // Acquisition signal and Baudrate signal trigger
    // Wire logic definition
        // state logic 
            wire        Time2Reload_w;                  // the state machine trigger condition
        // the comparation of the acq_up_time_cnt_r and acq_down_time_cnt_r for the compensate algorithm
            wire        AcqUpNumberReachLimit_w;            // the acq_up_time_cnt_r has decreased to zero
            wire        AcqDownNumberReachLimit_w;          // the acq_down_time_cnt_r has decreased to zero 
            wire        AcqUpNumberLeftMore_w;              // determin the acquisition period width after first period
            wire        AcqUpNumberInitMore_w;              // determin the first acquisition period width
        // Some State trigger signal    
            wire        AcqRising_w;                        // the acq_period_counter_r reach the limit
            wire        BaudRising_w;                       // when round up time and round down time reach the limit 
            wire        AcqTimeUpSelected_w;                // the acq_period_counter_r should gain to equal with the acq_period_up_r
            wire        AcqNumberReload_w;                  // the acq_up_time_cnt_r and acq_down_time_cnt_r should return to their limit
        // Testwire
            wire [4:0]  Divivder_Cnt_w;
        // the 
    // Parameter definition
        // Default parameter
            parameter       DEFAULT_PERIOD      = 16'd20;
            parameter       DEFAULT_UP_TIME     = 4'd10;
            parameter       DEFAULT_DOWN_TIME   = 4'd5;
        // Byte width
            parameter       BYTEWIDTH   = 4'd10;       // the second compensated method define a byte width 
        // Bit Type Definition
            parameter       POSITIVE    = 1'b1;        // the compensated method made the bit a little over time than required bit time(baudrate)
            parameter       NEGATIVE    = 1'b0;        // the compensated method made the bit a little shorter than required bit time(baudrate)
        // The Round Up period and Round Down period
            parameter       UP_PERIOD   = 1'b1;
            parameter       DOWN_PERIOD = 1'b0;
        // The output signal level definition
            parameter       INVALID     = 1'b0;
            parameter       ACTIVE      = 1'b1;
    // Assign
        // State machine 
            assign Time2Reload_w    =   (acq_period_counter_r == 16'd0);
        // the comparation of the acq_up_time_cnt_r and acq_down_time_cnt_r
            assign AcqUpNumberReachLimit_w    = (acq_up_time_cnt_r == 4'd0);      // the register decrease to zero 
            assign AcqDownNumberReachLimit_w  = (acq_down_time_cnt_r == 4'd0);    // the register decrease to zero 
            assign AcqUpNumberLeftMore_w      = (acq_up_time_cnt_r > acq_down_time_cnt_r);
            assign AcqUpNumberInitMore_w      = (acq_up_time_limit_r > acq_down_time_limit_r);
        // the judge result combination of the comparation result     
            assign AcqRising_w          = (acq_period_counter_r == 16'd0);
            assign BaudRising_w         = AcqRising_w & (acq_up_time_cnt_r == 4'd0) & (acq_down_time_cnt_r == 4'd0);
            assign AcqTimeUpSelected_w  = (AcqUpNumberReachLimit_w & AcqDownNumberReachLimit_w & AcqUpNumberInitMore_w) 
                                        | (~AcqUpNumberReachLimit_w& AcqDownNumberReachLimit_w ) 
                                        | (~AcqUpNumberReachLimit_w&~AcqDownNumberReachLimit_w & AcqUpNumberLeftMore_w);
            assign AcqNumberReload_w    = AcqUpNumberReachLimit_w & AcqDownNumberReachLimit_w;
        // output signal assign
            assign AcqSig_o     = acqsig_r;
            assign BaudSig_o    = baudsig_r;
        // Test 
            assign Divivder_Cnt_w = acq_up_time_cnt_r + acq_down_time_cnt_r;
    // input data buffer opperation all register only available when the baud_en_r is disabled
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                acq_period_down_r           <= DEFAULT_PERIOD;
                acq_period_up_r             <= DEFAULT_PERIOD + 1'b1;
                acq_up_time_limit_r         <= DEFAULT_UP_TIME;
                acq_down_time_limit_r       <= DEFAULT_DOWN_TIME;
            end
            else if (BaudRising_w == 1'b1) begin 
                acq_period_down_r           <= AcqPeriod_i;
                acq_period_up_r             <= AcqPeriod_i + 1'b1;
                acq_up_time_limit_r         <= BitCompensation_i[7:4];
                acq_down_time_limit_r       <= BitCompensation_i[3:0];
            end
            else begin
                acq_period_down_r           <= acq_period_down_r;                    
                acq_period_up_r             <= acq_period_up_r;      
                acq_up_time_limit_r         <= acq_up_time_limit_r;  
                acq_down_time_limit_r       <= acq_down_time_limit_r;                
            end
        end
    // the acquisition period coutner
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                acq_period_counter_r <= DEFAULT_PERIOD;
            end
            else if ((Time2Reload_w == 1'b1)) begin
                if (AcqTimeUpSelected_w == UP_PERIOD) begin
                    acq_period_counter_r <= acq_period_up_r;
                end
                else begin
                    acq_period_counter_r <= acq_period_down_r;
                end
            end
            else begin
                acq_period_counter_r <= acq_period_counter_r - 1'b1;
            end
        end 
    // the acq_up_time_cnt_r and acq_down_time_cnt_r fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                acq_up_time_cnt_r   <= DEFAULT_UP_TIME;
                acq_down_time_cnt_r <= DEFAULT_DOWN_TIME;
            end
            else if (Time2Reload_w == 1'b1) begin
                if (AcqNumberReload_w == 1'b1) begin
                    acq_up_time_cnt_r   <= acq_up_time_limit_r;
                    acq_down_time_cnt_r <= acq_down_time_limit_r;
                end 
                else if (AcqTimeUpSelected_w == UP_PERIOD) begin
                    acq_up_time_cnt_r   <= acq_up_time_cnt_r - 1'b1;
                    acq_down_time_cnt_r <= acq_down_time_cnt_r;
                end
                else begin
                    acq_up_time_cnt_r   <= acq_up_time_cnt_r;
                    acq_down_time_cnt_r <= acq_down_time_cnt_r - 1'b1;
                end
            end
            else begin
                acq_up_time_cnt_r   <= acq_up_time_cnt_r;                   
                acq_down_time_cnt_r <= acq_down_time_cnt_r;                 
            end
        end
    // output register fresh
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                acqsig_r <= INVALID;              
            end
            else if (AcqRising_w == 1'b1) begin
                acqsig_r <= ACTIVE;
            end
            else begin
                acqsig_r <= INVALID;
            end
        end
    // baudrate signal generate
        always @(posedge clk or negedge rst) begin
            if (!rst) begin
                baudsig_r <= INVALID;                
            end
            else if (BaudRising_w == 1'b1) begin
                baudsig_r <= ACTIVE;
            end
            else begin
                baudsig_r <= INVALID;
            end
        end
endmodule

