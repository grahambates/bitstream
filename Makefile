MODEL=A1200
BINDIR = ~/amiga/bin/
VASM = $(BINDIR)vasmm68k_mot
VASMFLAGS = -m68000 -x -opt-size -showopt -Fhunkexe -kick1hunks -nosym -pic
FSUAE = /Applications/FS-UAE-3.app/Contents/MacOS/fs-uae
UAEFLAGS = --amiga_model=$(MODEL) --floppy_drive_0_sounds=off --video_sync=1 --automatic_input_grab=0

source = main.asm
program = out/bitstream

adf: $(program).adf
exe: $(program).exe

$(program).adf: $(program).exe
	@$(BINDIR)adfcreate $@ || true
	@$(BINDIR)adfinst $@ || true
	@$(BINDIR)adfcopy $@ $< / || true
	@$(BINDIR)adfcopy $@ out/s / || true

run: exe
	$(FSUAE) $(UAEFLAGS) --hard_drive_1=./out

runadf: $(program).adf
	$(FSUAE) $(UAEFLAGS) $<

$(program).d: $(source)
	$(VASM) $(VASMFLAGS) -depend=make -quiet -o $(program).exe $< > $@

$(program).exe: $(source)
	$(VASM) $< $(VASMFLAGS) -o $@

-include $(program).d

clean:
	$(RM) out/*.*

.PHONY: rundist dist run exe clean