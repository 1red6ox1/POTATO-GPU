package rasterizer_pkg;

	localparam int unsigned FRAME_WIDTH  = 1920;
	localparam int unsigned FRAME_HEIGHT = 1080;
	localparam int unsigned TILE_WIDTH   = 32;
	localparam int unsigned TILE_HEIGHT  = 8;

	localparam int unsigned COORD_WIDTH = 16;
	localparam int unsigned EDGE_WIDTH  = 2 * COORD_WIDTH;
	localparam int unsigned DEPTH_WIDTH = 16;
	localparam int unsigned DEPTH_FRAC_WIDTH = 12;
	localparam int unsigned DEPTH_INTERP_WIDTH = DEPTH_WIDTH + DEPTH_FRAC_WIDTH + 1;
	localparam int unsigned UVQ_WIDTH = 32;
	localparam int unsigned UVQ_FRAC_WIDTH = 24;
	localparam int unsigned DELTA_WIDTH = 12;
	localparam int unsigned UVQ_NUM_WIDTH = UVQ_WIDTH + DELTA_WIDTH + 1;

	typedef struct packed {
		logic [1:0] fbid_color;
		logic [1:0] fbid_depth;

		logic signed [COORD_WIDTH-1:0] ax;
		logic signed [COORD_WIDTH-1:0] ay;
		logic        [DEPTH_WIDTH-1:0] az;
		logic signed [UVQ_WIDTH-1:0] auq;
		logic signed [UVQ_WIDTH-1:0] avq;
		logic signed [UVQ_WIDTH-1:0] aq;

		logic signed [COORD_WIDTH-1:0] bx;
		logic signed [COORD_WIDTH-1:0] by;
		logic        [DEPTH_WIDTH-1:0] bz;
		logic signed [UVQ_WIDTH-1:0] buq;
		logic signed [UVQ_WIDTH-1:0] bvq;
		logic signed [UVQ_WIDTH-1:0] bq;
		
		logic signed [COORD_WIDTH-1:0] cx;
		logic signed [COORD_WIDTH-1:0] cy;
		logic        [DEPTH_WIDTH-1:0] cz;
		logic signed [UVQ_WIDTH-1:0] cuq;
		logic signed [UVQ_WIDTH-1:0] cvq;
		logic signed [UVQ_WIDTH-1:0] cq;
	} triangle2d_t;

	typedef struct packed {
		logic [1:0] fbid_color;
		logic [1:0] fbid_depth;

		logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] bbox_min_x;
		logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] bbox_max_x;
		logic [$clog2(FRAME_HEIGHT / TILE_HEIGHT)-1:0] bbox_min_y;
		logic [$clog2(FRAME_HEIGHT / TILE_HEIGHT)-1:0] bbox_max_y;

		logic signed [COORD_WIDTH-1:0] dx1;
		logic signed [COORD_WIDTH-1:0] dx2;
		logic signed [COORD_WIDTH-1:0] dx3;
		logic signed [COORD_WIDTH-1:0] dy1;
		logic signed [COORD_WIDTH-1:0] dy2;
		logic signed [COORD_WIDTH-1:0] dy3;
		logic signed [EDGE_WIDTH-1:0] e1;
		logic signed [EDGE_WIDTH-1:0] e2;
		logic signed [EDGE_WIDTH-1:0] e3;

		logic signed [DEPTH_INTERP_WIDTH-1:0] z;
		logic signed [DEPTH_INTERP_WIDTH-1:0] dz_dx;
		logic signed [DEPTH_INTERP_WIDTH-1:0] dz_dy;

		logic signed [UVQ_WIDTH-1:0] uq;
		logic signed [UVQ_WIDTH-1:0] duq_dx;
		logic signed [UVQ_WIDTH-1:0] duq_dy;

		logic signed [UVQ_WIDTH-1:0] vq;
		logic signed [UVQ_WIDTH-1:0] dvq_dx;
		logic signed [UVQ_WIDTH-1:0] dvq_dy;

		logic signed [UVQ_WIDTH-1:0] q;
		logic signed [UVQ_WIDTH-1:0] dq_dx;
		logic signed [UVQ_WIDTH-1:0] dq_dy;
	} rasterization_param_t;

	typedef struct packed {
		logic [1:0] fbid_color;
		logic [1:0] fbid_depth;
		logic [$clog2(FRAME_WIDTH / TILE_WIDTH)-1:0] tile_x;
		logic [$clog2(FRAME_HEIGHT)-1:0] y;
	} chunk_id_t;

endpackage
