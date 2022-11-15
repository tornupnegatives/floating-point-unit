VC=iverilog
VC_FLAGS=-g2012
BUILD_DIR=build

test_operands: src/operands.sv test/test_operands.sv
	@mkdir -p $(BUILD_DIR)
	$(VC) $(VC_FLAGS) -o $(BUILD_DIR)/$@ $^
	./$(BUILD_DIR)/$@

test_adder: src/operands.sv src/adder.sv test/test_adder.sv
	@mkdir -p $(BUILD_DIR)
	$(VC) $(VC_FLAGS) -o $(BUILD_DIR)/$@ $^
	./$(BUILD_DIR)/$@

test_multiplier: src/operands.sv src/multiplier.sv test/test_multiplier.sv
	@mkdir -p $(BUILD_DIR)
	$(VC) $(VC_FLAGS) -o $(BUILD_DIR)/$@ $^
	./$(BUILD_DIR)/$@

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f *.vcd
