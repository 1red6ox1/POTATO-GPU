onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /hdmi_tb/DUT/clk_pixel_x5
add wave -noupdate /hdmi_tb/DUT/clk_pixel
add wave -noupdate /hdmi_tb/DUT/clk_audio
add wave -noupdate /hdmi_tb/DUT/tmds_clock
add wave -noupdate /hdmi_tb/DUT/tmds
add wave -noupdate /hdmi_tb/DUT/screen_width
add wave -noupdate /hdmi_tb/DUT/screen_height
add wave -noupdate /hdmi_tb/DUT/rgb
add wave -noupdate /hdmi_tb/DUT/reset
add wave -noupdate /hdmi_tb/DUT/frame_width
add wave -noupdate /hdmi_tb/DUT/frame_height
add wave -noupdate /hdmi_tb/DUT/cy
add wave -noupdate /hdmi_tb/DUT/cx
add wave -noupdate /hdmi_tb/DUT/audio_sample_word
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 fs} 0}
quietly wave cursor active 0
configure wave -namecolwidth 306
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
WaveRestoreZoom {2868099999050 fs} {2868099999950 fs}
