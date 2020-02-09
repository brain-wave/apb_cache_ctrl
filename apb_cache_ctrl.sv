/* 
 * Description: Small APB-wrapper around cache controller.
 */
 
module apb_cache_ctrl
#(
    parameter APB_ADDR_WIDTH = 12,  //APB slaves are 4KB by default
    parameter NUM_CORES      = 1
)
(
    input  logic                      HCLK,
    input  logic                      HRESETn,
    input  logic [APB_ADDR_WIDTH-1:0] PADDR,
    input  logic               [31:0] PWDATA,
    input  logic                      PWRITE,
    input  logic                      PSEL,
    input  logic                      PENABLE,
    output logic               [31:0] PRDATA,
    output logic                      PREADY,
    output logic                      PSLVERR,
    
    PRI_ICACHE_CTRL_UNIT_BUS.Master   IC_ctrl_unit_master_if[1] // for some reason this doesnt work: [NUM_CORES]
);

    XBAR_PERIPH_BUS    speriph();    
    logic [NUM_CORES:0] r_id;
    logic              r_opc;
    
    // Interface binding (APB to XBAR_PERIPH_BUS)
    assign PREADY                               = (PSEL && PENABLE && !PWRITE) ? speriph.r_valid : speriph.gnt;
    assign speriph.req                          = PSEL && PENABLE;
    assign speriph.add                          = PADDR;
    assign speriph.wen                          = ~PWRITE;
    assign speriph.wdata                        = PWDATA;
    assign speriph.be                           = 4'b0; // not used
    assign speriph.id                           = {NUM_CORES+1{1'b0}}; // used for some kind of ID reflection
    assign r_opc                                = speriph.r_opc; // not used
    assign r_id                                 = speriph.r_id; // reflected id; unused...
    assign PRDATA                               = speriph.r_rdata;
    
    // not supporting transfare failure
    assign PSLVERR = 1'b0;
    
    // Instantiate module
    pri_icache_ctrl_unit
      #(
        .NB_CACHE_BANKS(NUM_CORES), // might be wrong...
        .NB_CORES(NUM_CORES),
        .ID_WIDTH(NUM_CORES+1)
      )
    ictrl_inst
      (
        .clk_i(HCLK),
        .rst_ni(HRESETn),
        
        .IC_ctrl_unit_master_if(IC_ctrl_unit_master_if),
        .speriph_slave(speriph)
      );

endmodule
