module demo_top (mac_clk_in, 
		core_clk_in, 
		cpu_clk_in,
		rst, 
		clr, 
		din, 
		we, 
		we_1,
                cpu_addr,
                cs,
		cpu_data,
                init_done_in,
		hdrin,
		full, 
		full_1, 
		pass, 
		pass_valid,
                crc_16,
                rx_payload_en,
                rx_masked_data,
 		rx_mask_en,
                rx_pass,
                rx_check,
                scan_mode,
                scan_clk
              ); 
 
input			mac_clk_in, core_clk_in, cpu_clk_in, rst, clr;
input	[7:0]	din;
input			we;
input			we_1;
input	[7:0]	hdrin;

input	[1:0]	cpu_addr;
input			cs;   // x0in assert_timer -max 8 -clock cpu_clk
input 	[15:0]	cpu_data;
input 			init_done_in;
input			scan_mode, scan_clk;


output			full; 
output			full_1; 
output 			pass;
reg 			pass;
output 			pass_valid;
reg			pass_valid;
output [15:0] 	crc_16;
output			rx_payload_en;
output  [7:0]   rx_masked_data;
output 			rx_mask_en;
output			rx_pass;
output 			rx_check;	

reg			re_1;
reg			re;

wire	[7:0]	dout_1;
wire			empty_1;
wire	[1:0]		wr_level_1;
wire	[1:0]		rd_level_1;

wire	[7:0]	dout;
wire			empty;
wire	[1:0]		wr_level;
wire	[1:0]		rd_level;


reg	[7:0]	data;
reg	[7:0]	header;

// Internal clocks

wire 		cpu_clk, core_clk, mac_clk;

// Mode control

reg	[7:0]	err_thrs;
reg	[1:0]	pass_en;
reg	[15:0]	crc_seed;
reg	[7:0] 	fstp;
reg 		init_done;

// Flow control

reg	           tx_en; 
reg                tx_eop;
reg                tx_sop;
reg [7:0]          tx_mask;
reg                tx_mask_valid;
reg [7:0]         tx_wcnt;

// Configuration registers

always @ (posedge cpu_clk or negedge rst)
 if (!rst)
  begin
   err_thrs <= 8'h00;
   pass_en <= 2'b11;
   crc_seed <= 16'h0000;
   fstp <= 8'h00; 
   init_done <= 1'b0;
  end
 else
  begin
  init_done <= init_done_in;
  if (cs)
   case (cpu_addr)
    0: err_thrs <= cpu_data[7:0]; 
    1: pass_en <= cpu_data[1:0];
    2: crc_seed <= cpu_data[15:0];
    3: fstp <= cpu_data[7:0];
   endcase
  end 

wire check_en = pass_en[1] || (err_thrs == 8'h00);

// Syncer for init_done
reg init_done_r1,init_done_r2; 

always @ (posedge mac_clk)
  begin
    init_done_r1 <= init_done;
    init_done_r2 <= init_done_r1;
 end

//ADD MISSING SYNC HERE
// Data path

always @ (posedge core_clk or negedge rst)
 if (!rst)
  begin
     data <= 8'h00;
     header <= 8'h00;
  end
 else
  begin
     data <= din;//FIXME
     header <= hdrin;
  end    
   

// x0in mcfifo -enq we_1 -deq re_1 -enq_clock core_clk -deq_clock mac_clk -depth 16


generic_fifo_dc_gray fifo_1_d (	mac_clk, core_clk, rst, clr, data, we_1,
		dout_1, re_1, full_1, empty_1, wr_level_1, rd_level_1 );

// x0in mcfifo -enq we -deq re -enq_clock core_clk -deq_clock mac_clk -depth 16

generic_fifo_dc_gray fifo_0_h (	mac_clk, core_clk, rst, clr, header, we,
		dout, re, full, empty, wr_level, rd_level );

always @ (empty)
 if (!empty)
   re = 1'b1;
 else 
   re = 1'b0; 


always @ (posedge mac_clk or negedge rst)
 if (!rst)
   pass_valid <= 1'b0;
 else
   pass_valid <= re_1 || re;//Bug

always @ (empty_1)
 if (!empty_1)
   re_1 = 1'b1;
 else 
   re_1 = 1'b0; 

always @ (pass_valid or dout or dout_1)
  if (pass_valid) 
   begin
    if (dout == dout_1)
     pass = 1'b1;
    else
     pass = 1'b0;
   end
  else
   begin
    pass = 1'b0;
   end 
 

// x0in assert -var $0in_delay(!empty && !empty_1) -active pass_valid -clock mac_clk

crc_16_calc crc_1 (mac_clk, rst, crc_seed, dout_1, init_done_r2, fstp, crc_16);

// TX control FSM

reg [2:0] tx_state,
          next_tx_state;
 
reg [7:0]  next_tx_wcnt;
reg [7:0]  next_tx_mask;
reg [7:0]  tx_mask_d;

reg 		next_tx_en;
reg 		next_tx_sop;
reg 		next_tx_eop;
reg 		next_tx_mask_valid;

parameter [1:0] IDLE = 0,
                EN   = 1, 
                SOP  = 2,
                EOP  = 3;

always @ (posedge core_clk or negedge rst)
 if (!rst)
  begin
   tx_state <= IDLE;
   tx_wcnt <= 8'h00;
   tx_mask <= 8'h00;
   tx_mask_d <= 8'h00;
   tx_sop <= 1'b0;
   tx_eop <= 1'b0;
   tx_mask_valid <= 1'b0;
   tx_en <= 1'b0;
  end
 else
  begin
   tx_state <= next_tx_state;
   tx_wcnt <= next_tx_wcnt;
   if (tx_state == EN)
      tx_mask <= next_tx_mask;
   tx_mask_d <= tx_mask;
   tx_sop <= next_tx_sop;
   tx_eop <= next_tx_eop;
   tx_mask_valid <= next_tx_mask_valid;
   tx_en <= next_tx_en;
  end




always @ (tx_state or data or we_1 or init_done or tx_wcnt or header)
 begin
   // defaults
   next_tx_state = IDLE;
   next_tx_en = 1'b0; 
   next_tx_eop = 1'b0;
   next_tx_sop = 1'b0;
   next_tx_mask_valid = 1'b0;
   next_tx_wcnt = 8'h00;
   next_tx_mask = 8'h00;
   
   case(tx_state)
    IDLE: if (init_done)//ADD SYNC SIGNAL HERE
            if (we_1)
              begin
               next_tx_state = EN;
               next_tx_en = 1'b1;
               next_tx_mask_valid = 1'b1; 
              end
    
    EN: begin 
         next_tx_en = 1'b0;
         next_tx_state = SOP;
         next_tx_sop = 1'b1;
         next_tx_wcnt = header;
         next_tx_mask = data;
         next_tx_mask_valid = 1'b1; 
        end

    SOP:
            if ( tx_wcnt == 0) 
               next_tx_state = EOP;
            else
              begin
               next_tx_wcnt = tx_wcnt - 1'b1;
               next_tx_state = SOP;
              end

    EOP: begin
           next_tx_eop = 1'b1;
           next_tx_state = IDLE;
         end

   endcase
 end
             



// pulse syncer for tx_en

reg tx_en_r1, tx_en_r2, tx_en_r3;

always @ (posedge mac_clk)
  begin
    tx_en_r1 <= tx_en;
    tx_en_r2 <= tx_en_r1;
    tx_en_r3 <= tx_en_r2;
  end

//wire mask_pulse = tx_en_r2 ^ tx_en_r3;
wire mask_pulse = tx_en_r2 && !tx_en_r3;

// syncer for tx_mask_valid

reg tx_mask_valid_r1, tx_mask_valid_r2;

always @ (posedge mac_clk)
  begin
    tx_mask_valid_r1 <= tx_mask_valid;
    tx_mask_valid_r2 <= tx_mask_valid_r1;
 end


// 2-DFF syncer for pass_en[0]

reg pass_en0_r1, rx_pass;

always @ (posedge mac_clk)
  begin
    pass_en0_r1 <= pass_en[0];
    rx_pass <= pass_en0_r1;
 end

// 2-DFF syncer for check_en

reg check_en_r1, rx_check;

always @ (posedge mac_clk)
  begin
    check_en_r1 <= check_en; 
    rx_check <= check_en_r1;
 end


// DMUX syncer for tx_mask


reg [7:0] mask;
reg		mask_pass;
reg		mask_check;


always @ (posedge mac_clk or negedge rst)
 if (!rst)
  begin
    mask <= 8'h00;
    mask_pass <= 1'b1;
    mask_check <= 1'b1;
  end
 else
  begin
    mask_pass <= rx_pass; 
    mask_check <= rx_check;
    if (mask_pass)
      if (tx_mask_valid_r2)
//        if (!rx_check)
          mask <= tx_mask_d;
  end

// syncer for tx_sop

reg tx_sop_r1, tx_sop_r2;

always @ (posedge mac_clk)
  begin
    tx_sop_r1 <= tx_sop;
    tx_sop_r2 <= tx_sop_r1;
  end

    
// syncer for tx_eop

reg tx_eop_r1, tx_eop_r2;

always @ (posedge mac_clk)
  begin
    tx_eop_r1 <= tx_eop;
    tx_eop_r2 <= tx_eop_r1;
  end

// RX control logic

reg 		rx_payload_en;
reg [7:0] 	rx_masked_data;
reg 		rx_mask_en;


always @ (posedge mac_clk or negedge rst)
 if (!rst)
  begin
   rx_payload_en <= 1'b0;
   rx_masked_data <= 8'h00;
   rx_mask_en <= 1'b0;
  end
 else
  begin
   rx_payload_en <= !tx_sop_r2 && !tx_eop_r2;
   rx_mask_en <= mask_pulse;
   if (tx_eop_r2)  // mask used on last word for incomplete fill
    rx_masked_data <=  dout_1 && mask;
   else
    rx_masked_data <=  dout_1 ;
   // rx_masked_data <=  dout_1 || 4'b0; // Uncomment this for incremental run. 
  end



// Clock muxing for scan

assign cpu_clk = scan_mode ? scan_clk : cpu_clk_in;
assign mac_clk = scan_mode ? scan_clk : mac_clk_in;
assign core_clk = scan_mode ? scan_clk : core_clk_in;



endmodule




module crc_16_calc     (clk,
               		rst,
			seed,
			data,
			init_done,
			fstp,
			crc_16);

input 			clk,rst;
input 	[15:0] seed;
input	[7:0] data;	
input 			init_done;
input   [7:0] fstp;
output  [15:0] crc_16;


reg [15:0] crc_16;
reg [7:0] scramble;

wire [15:0] p = {data[7:0], (data[7:0]^fstp)};

always @ (posedge clk or negedge rst)
 if (!rst) 
   scramble <= 8'h00;
 else
   if (init_done) 
     begin
       scramble[7] <= p[5]^p[6]^p[7]^p[8]^p[9]^p[10]^p[14];
       scramble[6] <= p[4]^p[5]^p[6]^p[7]^p[8]^p[9]^p[13];
       scramble[5] <= p[3]^p[4]^p[5]^p[6]^p[7]^p[11]^p[12];
       scramble[4] <= p[2]^p[3]^p[4]^p[5]^p[6]^p[7]^p[8]^p[9]^p[11]^p[13];
       scramble[3] <= p[2]^p[3]^p[5]^p[6]^p[7]^p[8]^p[9]^p[10]^p[12]^p[14];
       scramble[2] <= p[1]^p[2]^p[6]^p[7]^p[8]^p[10]^p[12];
       scramble[1] <= p[1]^p[2]^p[3]^p[4]^p[6]^p[11]^p[13];
       scramble[0] <= p[1]^p[3]^p[6]^p[7]^p[9]^p[12]^p[15];
    end

wire [15:0] q = {scramble[7:0], (scramble[7:0]^seed[7:0])};

always @ (posedge clk or negedge rst)
 if (!rst)
   crc_16 <= 16'h0000;
 else
   begin
       crc_16[15] <= q[5]^q[6]^q[7]^q[8]^q[9]^q[10]^q[14];
       crc_16[14] <= q[4]^q[5]^q[6]^q[7]^q[8]^q[9]^q[13];
       crc_16[13] <= q[3]^q[4]^q[5]^q[6]^q[7]^q[11]^q[12];
       crc_16[12] <= q[2]^q[3]^q[4]^q[5]^q[6]^q[7]^q[8]^q[9]^q[11]^q[13];
       crc_16[11] <= q[2]^q[3]^q[5]^q[6]^q[7]^q[8]^q[9]^q[10]^q[12]^q[14];
       crc_16[10] <= q[1]^q[2]^q[6]^q[7]^q[8]^q[10]^q[12];
       crc_16[9] <= q[1]^q[2]^q[3]^q[4]^q[6]^q[11]^q[13];
       crc_16[8] <= q[1]^q[3]^q[6]^q[7]^q[9]^q[12]^q[15];
       crc_16[7] <= q[5]^q[6]^q[7]^q[8]^q[9]^q[10]^q[14];
       crc_16[6] <= q[4]^q[5]^q[6]^q[7]^q[8]^q[9]^q[13];
       crc_16[5] <= q[3]^q[4]^q[5]^q[6]^q[7]^q[11]^q[12];
       crc_16[4] <= q[2]^q[3]^q[4]^q[5]^q[6]^q[7]^q[8]^q[9]^q[11]^q[13];
       crc_16[3] <= q[2]^q[3]^q[5]^q[6]^q[7]^q[8]^q[9]^q[10]^q[12]^q[14];
       crc_16[2] <= q[1]^q[2]^q[6]^q[7]^q[8]^q[10]^q[12];
       crc_16[1] <= q[1]^q[2]^q[3]^q[4]^q[6]^q[11]^q[13];
       crc_16[0] <= q[1]^q[3]^q[6]^q[7]^q[9]^q[12]^q[15];
  end

endmodule
