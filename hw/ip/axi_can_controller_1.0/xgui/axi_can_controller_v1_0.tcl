# Definitional proc to organize widgets for parameters.
proc init_gui { IPINST } {
  ipgui::add_param $IPINST -name "Component_Name"
  #Adding Page
  set Page_0 [ipgui::add_page $IPINST -name "Page 0"]
  set C_BIT_RATE [ipgui::add_param $IPINST -name "C_BIT_RATE" -parent ${Page_0}]
  set_property tooltip {S_AXI_ACLK / (bit rate * tq per bit) must be an integer within 0.5 %} ${C_BIT_RATE}
  set C_CLOCK_FREQUENCY [ipgui::add_param $IPINST -name "C_CLOCK_FREQUENCY" -parent ${Page_0}]
  set_property tooltip {Must match the clock connected to S_AXI_ACLK (IPI does not propagate it)} ${C_CLOCK_FREQUENCY}
  set C_FILTERS [ipgui::add_param $IPINST -name "C_FILTERS" -parent ${Page_0}]
  set_property tooltip {ID / mask filters, 1 to 32} ${C_FILTERS}
  set C_PHASE_SEG2 [ipgui::add_param $IPINST -name "C_PHASE_SEG2" -parent ${Page_0}]
  set_property tooltip {tq after the sample point; sample point = (tq per bit - phase seg 2) / tq per bit} ${C_PHASE_SEG2}
  set C_RX_FIFO_DEPTH [ipgui::add_param $IPINST -name "C_RX_FIFO_DEPTH" -parent ${Page_0}]
  set_property tooltip {0 = no FIFO (one frame in the output register)} ${C_RX_FIFO_DEPTH}
  set C_SJW [ipgui::add_param $IPINST -name "C_SJW" -parent ${Page_0}]
  set_property tooltip {1 to 4, not larger than either phase segment} ${C_SJW}
  set C_TQ_PER_BIT [ipgui::add_param $IPINST -name "C_TQ_PER_BIT" -parent ${Page_0}]
  set_property tooltip {8 to 25} ${C_TQ_PER_BIT}
  set C_TX_BUFFERS [ipgui::add_param $IPINST -name "C_TX_BUFFERS" -parent ${Page_0}]
  set_property tooltip {frames that can wait to be sent, sent by bus priority} ${C_TX_BUFFERS}


}

proc update_PARAM_VALUE.C_BIT_RATE { PARAM_VALUE.C_BIT_RATE } {
	# Procedure called to update C_BIT_RATE when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_BIT_RATE { PARAM_VALUE.C_BIT_RATE } {
	# Procedure called to validate C_BIT_RATE
	return true
}

proc update_PARAM_VALUE.C_CLOCK_FREQUENCY { PARAM_VALUE.C_CLOCK_FREQUENCY } {
	# Procedure called to update C_CLOCK_FREQUENCY when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_CLOCK_FREQUENCY { PARAM_VALUE.C_CLOCK_FREQUENCY } {
	# Procedure called to validate C_CLOCK_FREQUENCY
	return true
}

proc update_PARAM_VALUE.C_FILTERS { PARAM_VALUE.C_FILTERS } {
	# Procedure called to update C_FILTERS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_FILTERS { PARAM_VALUE.C_FILTERS } {
	# Procedure called to validate C_FILTERS
	return true
}

proc update_PARAM_VALUE.C_PHASE_SEG2 { PARAM_VALUE.C_PHASE_SEG2 } {
	# Procedure called to update C_PHASE_SEG2 when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_PHASE_SEG2 { PARAM_VALUE.C_PHASE_SEG2 } {
	# Procedure called to validate C_PHASE_SEG2
	return true
}

proc update_PARAM_VALUE.C_RX_FIFO_DEPTH { PARAM_VALUE.C_RX_FIFO_DEPTH } {
	# Procedure called to update C_RX_FIFO_DEPTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_RX_FIFO_DEPTH { PARAM_VALUE.C_RX_FIFO_DEPTH } {
	# Procedure called to validate C_RX_FIFO_DEPTH
	return true
}

proc update_PARAM_VALUE.C_SJW { PARAM_VALUE.C_SJW } {
	# Procedure called to update C_SJW when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_SJW { PARAM_VALUE.C_SJW } {
	# Procedure called to validate C_SJW
	return true
}

proc update_PARAM_VALUE.C_S_AXI_ADDR_WIDTH { PARAM_VALUE.C_S_AXI_ADDR_WIDTH } {
	# Procedure called to update C_S_AXI_ADDR_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S_AXI_ADDR_WIDTH { PARAM_VALUE.C_S_AXI_ADDR_WIDTH } {
	# Procedure called to validate C_S_AXI_ADDR_WIDTH
	return true
}

proc update_PARAM_VALUE.C_S_AXI_DATA_WIDTH { PARAM_VALUE.C_S_AXI_DATA_WIDTH } {
	# Procedure called to update C_S_AXI_DATA_WIDTH when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_S_AXI_DATA_WIDTH { PARAM_VALUE.C_S_AXI_DATA_WIDTH } {
	# Procedure called to validate C_S_AXI_DATA_WIDTH
	return true
}

proc update_PARAM_VALUE.C_TQ_PER_BIT { PARAM_VALUE.C_TQ_PER_BIT } {
	# Procedure called to update C_TQ_PER_BIT when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_TQ_PER_BIT { PARAM_VALUE.C_TQ_PER_BIT } {
	# Procedure called to validate C_TQ_PER_BIT
	return true
}

proc update_PARAM_VALUE.C_TX_BUFFERS { PARAM_VALUE.C_TX_BUFFERS } {
	# Procedure called to update C_TX_BUFFERS when any of the dependent parameters in the arguments change
}

proc validate_PARAM_VALUE.C_TX_BUFFERS { PARAM_VALUE.C_TX_BUFFERS } {
	# Procedure called to validate C_TX_BUFFERS
	return true
}


proc update_MODELPARAM_VALUE.C_CLOCK_FREQUENCY { MODELPARAM_VALUE.C_CLOCK_FREQUENCY PARAM_VALUE.C_CLOCK_FREQUENCY } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_CLOCK_FREQUENCY}] ${MODELPARAM_VALUE.C_CLOCK_FREQUENCY}
}

proc update_MODELPARAM_VALUE.C_BIT_RATE { MODELPARAM_VALUE.C_BIT_RATE PARAM_VALUE.C_BIT_RATE } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_BIT_RATE}] ${MODELPARAM_VALUE.C_BIT_RATE}
}

proc update_MODELPARAM_VALUE.C_TQ_PER_BIT { MODELPARAM_VALUE.C_TQ_PER_BIT PARAM_VALUE.C_TQ_PER_BIT } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_TQ_PER_BIT}] ${MODELPARAM_VALUE.C_TQ_PER_BIT}
}

proc update_MODELPARAM_VALUE.C_PHASE_SEG2 { MODELPARAM_VALUE.C_PHASE_SEG2 PARAM_VALUE.C_PHASE_SEG2 } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_PHASE_SEG2}] ${MODELPARAM_VALUE.C_PHASE_SEG2}
}

proc update_MODELPARAM_VALUE.C_SJW { MODELPARAM_VALUE.C_SJW PARAM_VALUE.C_SJW } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_SJW}] ${MODELPARAM_VALUE.C_SJW}
}

proc update_MODELPARAM_VALUE.C_RX_FIFO_DEPTH { MODELPARAM_VALUE.C_RX_FIFO_DEPTH PARAM_VALUE.C_RX_FIFO_DEPTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_RX_FIFO_DEPTH}] ${MODELPARAM_VALUE.C_RX_FIFO_DEPTH}
}

proc update_MODELPARAM_VALUE.C_TX_BUFFERS { MODELPARAM_VALUE.C_TX_BUFFERS PARAM_VALUE.C_TX_BUFFERS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_TX_BUFFERS}] ${MODELPARAM_VALUE.C_TX_BUFFERS}
}

proc update_MODELPARAM_VALUE.C_FILTERS { MODELPARAM_VALUE.C_FILTERS PARAM_VALUE.C_FILTERS } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_FILTERS}] ${MODELPARAM_VALUE.C_FILTERS}
}

proc update_MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH { MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH PARAM_VALUE.C_S_AXI_DATA_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S_AXI_DATA_WIDTH}] ${MODELPARAM_VALUE.C_S_AXI_DATA_WIDTH}
}

proc update_MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH { MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH PARAM_VALUE.C_S_AXI_ADDR_WIDTH } {
	# Procedure called to set VHDL generic/Verilog parameter value(s) based on TCL parameter value
	set_property value [get_property value ${PARAM_VALUE.C_S_AXI_ADDR_WIDTH}] ${MODELPARAM_VALUE.C_S_AXI_ADDR_WIDTH}
}

