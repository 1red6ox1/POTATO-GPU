onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /ddr_mux_tb/N
add wave -noupdate /ddr_mux_tb/host_i
add wave -noupdate /ddr_mux_tb/host_o
add wave -noupdate /ddr_mux_tb/dev_o
add wave -noupdate /ddr_mux_tb/dev_i
add wave -noupdate -divider DUT
add wave -noupdate /ddr_mux_tb/dut/N
add wave -noupdate /ddr_mux_tb/dut/MAX_OUTSTANDING
add wave -noupdate /ddr_mux_tb/dut/LOGN
add wave -noupdate /ddr_mux_tb/dut/LOG_REQS
add wave -noupdate /ddr_mux_tb/dut/COUNT_WIDTH
add wave -noupdate /ddr_mux_tb/dut/clk_i
add wave -noupdate /ddr_mux_tb/dut/rst_ni
add wave -noupdate /ddr_mux_tb/dut/host_i
add wave -noupdate /ddr_mux_tb/dut/host_o
add wave -noupdate /ddr_mux_tb/dut/dev_o
add wave -noupdate /ddr_mux_tb/dut/dev_i
add wave -noupdate /ddr_mux_tb/dut/ancillary_mem
add wave -noupdate /ddr_mux_tb/dut/source_mem
add wave -noupdate /ddr_mux_tb/dut/rptr
add wave -noupdate /ddr_mux_tb/dut/wptr
add wave -noupdate /ddr_mux_tb/dut/outstanding_q
add wave -noupdate /ddr_mux_tb/dut/sel_host_h2d
add wave -noupdate /ddr_mux_tb/dut/sel_host_id
add wave -noupdate /ddr_mux_tb/dut/response_host_id
add wave -noupdate /ddr_mux_tb/dut/route_empty
add wave -noupdate /ddr_mux_tb/dut/route_full
add wave -noupdate /ddr_mux_tb/dut/request_fire
add wave -noupdate /ddr_mux_tb/dut/response_fire
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 fs} 0}
quietly wave cursor active 0
configure wave -namecolwidth 150
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
WaveRestoreZoom {64987487 fs} {65001712 fs}
