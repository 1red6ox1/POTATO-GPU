quietly WaveActivateNextPane {} 0

add wave -noupdate -divider {Clock and reset}
add wave -noupdate sim:/vertex_processor_tb/clk
add wave -noupdate sim:/vertex_processor_tb/rst_n

add wave -noupdate -divider {Output stream}
add wave -noupdate sim:/vertex_processor_tb/out_ready
add wave -noupdate sim:/vertex_processor_tb/out_valid
add wave -noupdate -radix unsigned sim:/vertex_processor_tb/out_id
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/out_vec[0]}
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/out_vec[1]}
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/out_vec[2]}
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/out_vec[3]}

add wave -noupdate -divider {Scene scan}
add wave -noupdate sim:/vertex_processor_tb/DUT/stored_triangle_valid_q
add wave -noupdate -radix unsigned sim:/vertex_processor_tb/DUT/last_stored_triangle_q
add wave -noupdate -radix unsigned sim:/vertex_processor_tb/DUT/launch_triangle_q
add wave -noupdate -radix unsigned sim:/vertex_processor_tb/DUT/launch_vertex_q
add wave -noupdate sim:/vertex_processor_tb/DUT/read_fire

add wave -noupdate -divider {DPRAM to matmul pipeline}
add wave -noupdate sim:/vertex_processor_tb/DUT/read_valid_q
add wave -noupdate sim:/vertex_processor_tb/DUT/read_first_vertex_q
add wave -noupdate -radix unsigned sim:/vertex_processor_tb/DUT/read_id_q
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/DUT/matmul_vec[0]}
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/DUT/matmul_vec[1]}
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/DUT/matmul_vec[2]}
add wave -noupdate -radix hexadecimal {sim:/vertex_processor_tb/DUT/matmul_vec[3]}
add wave -noupdate sim:/vertex_processor_tb/DUT/u_matmul/valid_shift
add wave -noupdate -radix unsigned {sim:/vertex_processor_tb/DUT/u_matmul/id_shift[0]}
add wave -noupdate -radix unsigned {sim:/vertex_processor_tb/DUT/u_matmul/id_shift[1]}

add wave -noupdate -divider {Vector memory writes}
add wave -noupdate sim:/vertex_processor_tb/DUT/vec_req
add wave -noupdate sim:/vertex_processor_tb/DUT/vec_we
add wave -noupdate -radix hexadecimal sim:/vertex_processor_tb/DUT/vec_sram_addr
add wave -noupdate -radix hexadecimal sim:/vertex_processor_tb/DUT/vec_wdata
add wave -noupdate -radix hexadecimal sim:/vertex_processor_tb/DUT/vec_wmask
add wave -noupdate -radix unsigned sim:/vertex_processor_tb/DUT/vec_triangle_id
add wave -noupdate sim:/vertex_processor_tb/DUT/triangle_write_complete

add wave -noupdate -divider {Configuration}
add wave -noupdate sim:/vertex_processor_tb/DUT/cfg_write_accept

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
configure wave -namecolwidth 260
configure wave -valuecolwidth 120
configure wave -timelineunits ns
update
