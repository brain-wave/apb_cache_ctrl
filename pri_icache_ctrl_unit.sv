// Copyright 2014-2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// ============================================================================= //
// Company:        Multitherman Laboratory @ DEIS - University of Bologna        //
//                    Viale Risorgimento 2 40136                                 //
//                    Bologna - fax 0512093785 -                                 //
//                                                                               //
// Engineer:       Igor Loi - igor.loi@unibo.it                                  //
//                                                                               //
// Additional contributions by:                                                  //
//                                                                               //
// Create Date:    18/08/2014                                                    // 
// Design Name:    icache_ctrl_unit                                              // 
// Module Name:    icache_ctrl_unit                                              //
// Project Name:   PULP                                                          //
// Language:       SystemVerilog                                                 //
//                                                                               //
// Description:    ICACHE control Unit, used to enable/disable icache banks      //
//                 flush operations, and to debug the status og cache banks      //
//                                                                               //
// Revision:                                                                     //
// Revision v0.1 - File Created                                                  //
//                                                                               //
// ============================================================================= //


`define ENABLE_ICACHE 6'b00_0000
`define FLUSH_ICACHE  6'b00_0001
`ifdef FEATURE_ICACHE_STAT  //TO BE TESTED DEEPLY
`define CLEAR_CNTS    6'b00_0011 
`define ENABLE_CNTS   6'b00_0100
`endif


//-----------------------------------//


module pri_icache_ctrl_unit
#(
    parameter  NB_CACHE_BANKS = 8,
    parameter  NB_CORES       = 8,
    parameter  ID_WIDTH       = 5
)
(
    input logic                                 clk_i,
    input logic                                 rst_ni,

    XBAR_PERIPH_BUS.Slave                       speriph_slave,
    PRI_ICACHE_CTRL_UNIT_BUS.Master             IC_ctrl_unit_master_if[NB_CORES]
);

   int unsigned                             i,j,k,x,y;
   genvar index;


`ifdef FEATURE_ICACHE_STAT
    localparam                          NUM_REGS       = 6;
`else
    localparam                          NUM_REGS       = 2;
`endif



    logic [NB_CORES-1:0]                 icache_bypass_req_o;
    logic [NB_CORES-1:0]                 icache_bypass_ack_i;

    logic [NB_CORES-1:0]                 icache_flush_req_o;
    logic [NB_CORES-1:0]                 icache_flush_ack_i;

    logic [31:0]                ICACHE_CTRL_REGS[NUM_REGS];

    // State of the main FSM
`ifdef FEATURE_ICACHE_STAT
    enum logic [2:0] { IDLE, ENABLE_ICACHE, DISABLE_ICACHE, FLUSH_ICACHE_CHECK, CLEAR_STAT_REGS, ENABLE_STAT_REGS } CS, NS;
`else
    enum logic [2:0] { IDLE, ENABLE_ICACHE, DISABLE_ICACHE, FLUSH_ICACHE_CHECK } CS, NS;
`endif

    // Exploded Interface --> PERIPHERAL INTERFACE
    logic                req;
    logic [31:0]         addr;
    logic                wen;
    logic [31:0]         wdata;
    logic [3:0]          be;
    logic                gnt;
    logic [ID_WIDTH-1:0] id;
    logic                r_valid;
    logic                r_opc;
    logic [ID_WIDTH-1:0] r_id;
    logic [31:0]         r_rdata;


    // Internal FSM signals --> responses
    logic                                       r_valid_int;
    logic [31:0]                                r_rdata_int;

`ifdef FEATURE_ICACHE_STAT
    logic [NB_CORES-1:0] [31:0]                 hit_count;
    logic [NB_CORES-1:0] [31:0]                 trans_count;
    logic [NB_CORES-1:0] [31:0]                 miss_count;
    logic [NB_CORES-1:0]                        clear_regs;
    logic [NB_CORES-1:0]                        enable_regs;

    logic [31:0]                                global_hit_count;
    logic [31:0]                                global_trans_count;
    logic [31:0]                                global_miss_count;

`endif

    logic                                       is_read;
    logic                                       is_write;
    logic                                       deliver_response;


    logic                                       listen_ack_enable;
    logic                                       clear_ack_enable;
    logic [NB_CORES-1:0]                        sampled_ack_enable;

    logic                                       listen_ack_disable;
    logic                                       clear_ack_disable;
    logic [NB_CORES-1:0]                        sampled_ack_disable;

    logic                                       listen_ack_flush;
    logic                                       clear_ack_flush;
    logic [NB_CORES-1:0]                        sampled_ack_flush;


    // Interface binding
    assign speriph_slave.gnt                    = gnt;
    assign req                                  = speriph_slave.req;
    assign addr                                 = speriph_slave.add;
    assign wen                                  = speriph_slave.wen;
    assign wdata                                = speriph_slave.wdata;
    assign be                                   = speriph_slave.be;
    assign id                                   = speriph_slave.id;
    assign speriph_slave.r_valid                = r_valid;
    assign speriph_slave.r_opc                  = r_opc;
    assign speriph_slave.r_id                   = r_id;
    assign speriph_slave.r_rdata                = r_rdata;








generate
  for(index=0;index<NB_CORES;index++)
  begin
        assign IC_ctrl_unit_master_if[index].bypass_req         = icache_bypass_req_o[index];
        assign icache_bypass_ack_i[index]                       = IC_ctrl_unit_master_if[index].bypass_ack;
        assign IC_ctrl_unit_master_if[index].flush_req          = icache_flush_req_o[index];
        assign icache_flush_ack_i[index]                        = IC_ctrl_unit_master_if[index].flush_ack;

`ifdef FEATURE_ICACHE_STAT
        assign IC_ctrl_unit_master_if[index].ctrl_clear_regs    = clear_regs[index];
        assign IC_ctrl_unit_master_if[index].ctrl_enable_regs   = enable_regs[index];
  end

  for(index=0;index<NB_CORES;index++)
  begin
    assign hit_count[index]                           = IC_ctrl_unit_master_if[index].ctrl_hit_count;
    assign trans_count[index]                         = IC_ctrl_unit_master_if[index].ctrl_trans_count; 
    assign miss_count[index]                          = IC_ctrl_unit_master_if[index].ctrl_miss_count; 
`endif
  end
endgenerate

 
   always_comb
   begin : REGISTER_BIND_OUT
      icache_bypass_req_o  =  ~ICACHE_CTRL_REGS[`ENABLE_ICACHE][NB_CORES-1:0];
      icache_flush_req_o   =   ICACHE_CTRL_REGS[`FLUSH_ICACHE][NB_CORES-1:0];
`ifdef FEATURE_ICACHE_STAT
      enable_regs =   ICACHE_CTRL_REGS[`ENABLE_CNTS][NB_CORES-1:0];
`endif      
   end


`ifdef FEATURE_ICACHE_STAT
   always_comb
   begin
      global_hit_count   = '0;
      global_trans_count = '0;
      global_miss_count  = '0;

      for(i=0; i<NB_CORES; i++)
      begin
         global_hit_count   = global_hit_count   + hit_count[i];
         global_trans_count = global_trans_count + trans_count[i];
         global_miss_count  = global_miss_count  + miss_count[i];
      end
   end
`endif




   always_ff @(posedge clk_i, negedge rst_ni)
   begin : SEQ_PROC
      if(rst_ni == 1'b0)
      begin
         CS                  <= IDLE;
         r_id                <= '0;

         r_valid             <= 1'b0;
         r_rdata             <= '0;
         r_opc               <= '0;

         sampled_ack_flush <= '0;
         sampled_ack_enable  <= '0;
         sampled_ack_disable <= '0;

         for(j=0;j<NUM_REGS;j++)
            ICACHE_CTRL_REGS[j] <= '0;
      end
      else
      begin

        CS                  <= NS;




        // Track Enable icache acknow
        if(listen_ack_enable)
        begin
          for(j=0; j<NB_CORES; j++)
          begin
              if(icache_bypass_ack_i[j] == 1'b0)
                  sampled_ack_enable[j] <= 1'b1;
          end
        end
        else
        begin
          if(clear_ack_enable)
          for(j=0; j<NB_CORES; j++)
          begin
                  sampled_ack_enable[j] <= 1'b0;
          end
        end



        // Track Enable icache acknow
        if(listen_ack_disable)
        begin
          for(j=0; j<NB_CORES; j++)
          begin
              if(icache_bypass_ack_i[j] == 1'b1)
                  sampled_ack_disable[j] <= 1'b1;
          end
        end
        else
        begin
          if(clear_ack_disable)
          for(j=0; j<NB_CORES; j++)
          begin
                  sampled_ack_disable[j] <= 1'b0;
          end
        end







        // Track Flush icache acknow
        if(listen_ack_flush)
        begin
          for(j=0; j<NB_CORES; j++)
          begin
              if(icache_flush_ack_i[j])
                  sampled_ack_flush[j] <= 1'b1;
          end
        end
        else
        begin
          if(clear_ack_flush)
          for(j=0; j<NB_CORES; j++)
          begin
                  sampled_ack_flush[j] <= 1'b0;
                  ICACHE_CTRL_REGS[`FLUSH_ICACHE][j] <= 1'b0;
          end
        end



        if(is_write)
        begin
          case(addr[7:0])
              8'h00: // ENABLE-DISABLE
              begin
                ICACHE_CTRL_REGS[`ENABLE_ICACHE] <=  wdata;
              end

              8'h04: // FLUSH
              begin
                ICACHE_CTRL_REGS[`FLUSH_ICACHE] <= wdata;
              end


    `ifdef FEATURE_ICACHE_STAT
              8'h0C: // CLEAR
              begin
                ICACHE_CTRL_REGS[`CLEAR_CNTS] <= wdata;
              end

              8'h10: // ENABLE-DISABLE STAT REGS
              begin
                ICACHE_CTRL_REGS[`ENABLE_CNTS] <= wdata;
              end
    `endif
          endcase
        end

        // sample the ID
        if(req & gnt)
        begin
          r_id    <= id;
        end


        //Handle register read
        if(is_read == 1'b1)
        begin
                r_valid <= 1'b1;

                case(addr[7:2])
                0:   begin r_rdata <= ICACHE_CTRL_REGS[`ENABLE_ICACHE]; end
                1:   begin r_rdata <= ICACHE_CTRL_REGS[`FLUSH_ICACHE];  end
                2:   begin r_rdata <= 32'hBADD_A555;  end  

          `ifdef FEATURE_ICACHE_STAT
                // Clear and start
                3:   begin r_rdata  <= ICACHE_CTRL_REGS[`CLEAR_CNTS];   end
                4:   begin r_rdata  <= ICACHE_CTRL_REGS[`ENABLE_CNTS];  end

                5:   begin r_rdata  <= global_hit_count;                end
                6:   begin r_rdata  <= global_trans_count;              end
                7:   begin r_rdata  <= global_miss_count;               end
                8:   begin r_rdata  <= 32'hFFFF_FFFF;                   end

                9:   begin r_rdata  <= hit_count   [0];  end  
                10:  begin r_rdata  <= trans_count [0];  end
                11:  begin r_rdata  <= miss_count  [0];  end
          `endif
                default : begin r_rdata <= 32'hDEAD_A555; end
                endcase
      
                r_opc   <= 1'b0;
          end
          else //no read --> IS WRITE
          begin
                if(deliver_response)
                begin
                    r_rdata <= '0;
                    r_valid <= 1'b1;
                    r_opc   <= 1'b0;
                end
                else
                begin
                    r_valid <= 1'b0;
                    r_rdata <= 'X;
                    r_opc   <= 1'b0;
                end
          end

      end
   end




   always_comb
   begin
        is_read                = 1'b0;
        is_write               = 1'b0;
        deliver_response       = 1'b0;
        gnt                    = 1'b0;

        listen_ack_enable      = 1'b0;
        listen_ack_disable     = 1'b0;
        listen_ack_flush       = 1'b0;

        clear_ack_flush        = 1'b0;
        clear_ack_enable       = 1'b0;
        clear_ack_disable      = 1'b0;

`ifdef FEATURE_ICACHE_STAT
        clear_regs             = '0;
`endif

        case(CS)

          IDLE:
          begin
              gnt = 1'b1;

              if(req)
              begin
                if(wen == 1'b1) // read
                begin
                      is_read          = 1'b1;
                      NS               = IDLE;
                      deliver_response = 1'b1;
                end
                else // Write registers
                begin

                      is_write = 1'b1;

                      case(addr[7:2])
                        `ENABLE_ICACHE: // Enable - Disable register
                        begin
                          if(wdata == 0)
                             NS = DISABLE_ICACHE;
                           else
                             NS = ENABLE_ICACHE;
                        end //~2'b00

                        `FLUSH_ICACHE:
                        begin
                          NS = FLUSH_ICACHE_CHECK;
                        end


                    `ifdef FEATURE_ICACHE_STAT
                        `CLEAR_CNTS: // CLEAR
                        begin
                          NS = CLEAR_STAT_REGS;
                        end

                        `ENABLE_CNTS: // START
                        begin
                          NS = ENABLE_STAT_REGS;
                        end
                    `endif


                        default: begin
                          NS = IDLE;
                        end
                      endcase

                end

              end
              else // no request
              begin
                  NS = IDLE;
              end

          end //~IDLE

`ifdef FEATURE_ICACHE_STAT
          CLEAR_STAT_REGS:
          begin
             for(x=0; x<NB_CACHE_BANKS; x++)
             begin
                clear_regs[x]  =   ICACHE_CTRL_REGS[`CLEAR_CNTS][x];
             end

             deliver_response = 1'b1;
             NS = IDLE;
          end //~ CLEAR_STAT_REGS


          ENABLE_STAT_REGS:
          begin

             deliver_response = 1'b1;
             NS = IDLE;
          end //~ENABLE_STAT_REGS
`endif


          ENABLE_ICACHE: 
          begin
            gnt                    = 1'b0;
            listen_ack_enable      = 1'b1;
            
            if( &(sampled_ack_enable[NB_CORES-1:0]) )
            begin
              NS = IDLE;
              deliver_response = 1'b1;
              clear_ack_enable = 1'b1;
            end
            else
            begin
              NS = ENABLE_ICACHE;
            end
          end //~ENABLE_ICACHE


          DISABLE_ICACHE: 
          begin
            gnt                    = 1'b0;
            listen_ack_disable     = 1'b1;

            if( &(sampled_ack_disable[NB_CORES-1:0]) )
            begin
              NS = IDLE;
              deliver_response = 1'b1;
              clear_ack_disable = 1'b1;
            end
            else
            begin
              NS = DISABLE_ICACHE;
            end
          end //~DISABLE_ICACHE




          FLUSH_ICACHE_CHECK:
          begin
              gnt = 1'b0;

              if(&sampled_ack_flush[NB_CORES-1:0])
              begin
                NS = IDLE;
                deliver_response = 1'b1;
                clear_ack_flush  = 1'b1;
              end
              else
              begin
                NS = FLUSH_ICACHE_CHECK;
                listen_ack_flush = 1'b1;
              end
          end


        default :
        begin
                NS = IDLE;
        end
        endcase
   end


endmodule
