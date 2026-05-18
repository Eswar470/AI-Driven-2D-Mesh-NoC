module noc_tb;
    import noc_params::*;

    parameter MESH_X = 2;
    parameter MESH_Y = 3;

    logic clk, rst;
    initial clk = 0;
    always #5 clk = ~clk;

    flit_t [MESH_X-1:0][MESH_Y-1:0] data_i, data_o;
    logic [MESH_X-1:0][MESH_Y-1:0] is_valid_i, is_valid_o;
    logic [MESH_X-1:0][MESH_Y-1:0][VC_NUM-1:0] is_on_off_i, is_allocatable_i;
    logic [MESH_X-1:0][MESH_Y-1:0][VC_NUM-1:0] is_on_off_o, is_allocatable_o;
    // FIX: was logic [VC_NUM-1:0] error_o [...][PORT_NUM-1:0] — wrong type
    logic [1:0] error_o [0:MESH_X-1][0:MESH_Y-1][0:4];

    mesh #(.BUFFER_SIZE(8),.MESH_SIZE_X(MESH_X),.MESH_SIZE_Y(MESH_Y)) DUT (
        .clk(clk), .rst(rst), .error_o(error_o),
        .data_o(data_o), .is_valid_o(is_valid_o),
        .is_on_off_i(is_on_off_i), .is_allocatable_i(is_allocatable_i),
        .data_i(data_i), .is_valid_i(is_valid_i),
        .is_on_off_o(is_on_off_o), .is_allocatable_o(is_allocatable_o)
    );

    typedef struct { int id; time inject_time; } pkt_t;
    pkt_t pkt_store [2000];
    int pkt_id=0;
    time total_latency; int latency_count, total_packets;
    time start_time, end_time;
    real avg_latency, throughput;
    integer file;

    task reset_dut();
        rst=1; repeat(5) @(posedge clk); rst=0;
    endtask

    task send_packet_vc(int x, int y, int dest_x, int dest_y, int vc);
        @(posedge clk);
        data_i[x][y].flit_label=HEADTAIL; data_i[x][y].vc_id=vc;
        data_i[x][y].data.head_data.x_dest=dest_x;
        data_i[x][y].data.head_data.y_dest=dest_y;
        data_i[x][y].data.head_data.head_pl=pkt_id;
        is_valid_i[x][y]=1;
        pkt_store[pkt_id].id=pkt_id; pkt_store[pkt_id].inject_time=$time;
        pkt_id++;
        @(posedge clk); is_valid_i[x][y]=0;
    endtask

    task send_packet(int x, int y, int dest_x, int dest_y);
        send_packet_vc(x, y, dest_x, dest_y, 0);
    endtask

    task random_traffic(int num);
        int sx, sy, dx, dy, vc;
        for (int i=0; i<num; i++) begin
            sx=$urandom_range(0,MESH_X-1); sy=$urandom_range(0,MESH_Y-1);
            dx=$urandom_range(0,MESH_X-1); dy=$urandom_range(0,MESH_Y-1);
            vc=$urandom_range(0,VC_NUM-1);
            send_packet_vc(sx,sy,dx,dy,vc);
            repeat(1) @(posedge clk);
        end
    endtask

    int mon_id; time mon_latency;
    always @(posedge clk)
        for (int x=0; x<MESH_X; x++)
            for (int y=0; y<MESH_Y; y++)
                if (is_valid_o[x][y]) begin
                    mon_id=data_o[x][y].data.head_data.head_pl;
                    mon_latency=$time-pkt_store[mon_id].inject_time;
                    total_latency+=mon_latency; latency_count++; total_packets++;
                    $display("Packet %0d latency = %0t", mon_id, mon_latency);
                    $fwrite(file, "%0d,%0t\n", mon_id, mon_latency);
                end

    initial begin
        for (int x=0; x<MESH_X; x++)
            for (int y=0; y<MESH_Y; y++) begin
                is_valid_i[x][y]=0; is_on_off_i[x][y]='1; is_allocatable_i[x][y]='1;
            end
        total_latency=0; latency_count=0; total_packets=0;
        file=$fopen("latency.csv","w");
        reset_dut(); start_time=$time;
        send_packet(0,0,1,2); send_packet(1,1,0,0);
        random_traffic(49);
        repeat(100) @(posedge clk);
        end_time=$time;
        avg_latency=total_latency*1.0/latency_count;
        throughput=total_packets*1.0/(end_time-start_time);
        $display("\n==== NORMAL XY ROUTING RESULTS ====");
        $display("Packets        = %0d", total_packets);
        $display("Avg Latency    = %0f ns", avg_latency);
        $display("Throughput     = %0f packets/ns", throughput);
        $display("===================================\n");
        $fclose(file); #50; $finish;
    end
endmodule
