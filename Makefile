source = main.asm
program = out/a

FSUAE = ~/projects/vscode-amiga-debug/bin/darwin/fs-uae/fs-uae
VASM = ~/amiga/bin/vasmm68k_mot

VASMFLAGS = -m68000 -x -opt-size -Fhunkexe -kick1hunks -nosym -pic
UAEFLAGS = --amiga_model=A500 --floppy_drive_0_sounds=off

exe: $(program).exe

run: exe
	$(FSUAE) $(UAEFLAGS) --hard_drive_1=./out

$(program).d: $(source)
	$(info Building dependencies for $<)
	$(VASM) $(VASMFLAGS) -depend=make -quiet -o $(program).elf $< > $@
	$(VASM) $(VASMFLAGS) -depend=make -quiet -o $(program).bb $<

$(program).exe: $(source)
	$(VASM) $< $(VASMFLAGS) -o $@

-include $(program).d

clean:
	$(info Cleaning...)
	$(RM) out/*.*

.PHONY: rundist dist run exe clean