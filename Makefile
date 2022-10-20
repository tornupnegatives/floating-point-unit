VC=iverilog
VCFLAGS=-g2012
BUILD=build

test_operands: src/operands.sv test/test_operands.sv
	@mkdir -p build
	$(VC) $(VCFLAGS) -o $(BUILD)/test_operands src/operands.sv test/test_operands.sv
	./$(BUILD)/test_operands

clean:
	@rm -rf build
	@rm -rf *.vcd
