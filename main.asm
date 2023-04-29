		incdir	"include"
		include	"hw.i"

; Use a fixed address for screen buffer
; this doubles as color01
Screen = $71bc

SIN_LEN = 256
SPEED = 2

; Display window:
DIW_W = 320
DIW_H = 256
BPLS = 1
SCROLL = 1							; enable playfield scroll?
INTERLEAVED = 0
DPF = 0								; enable dual playfield?

; Screen buffer:
SCREEN_W = DIW_W+64
SCREEN_H = DIW_H+16

;-------------------------------------------------------------------------------
; Derived

COLORS = 1<<BPLS
SCREEN_BW = SCREEN_W/16*2					; byte-width of 1 bitplane line
		ifne	INTERLEAVED
SCREEN_MOD = SCREEN_BW*(BPLS-1)					; modulo (interleaved)
SCREEN_BPL = SCREEN_BW						; bitplane offset (interleaved)
		else
SCREEN_MOD = 0							; modulo (non-interleaved)
SCREEN_BPL = SCREEN_BW*SCREEN_H					; bitplane offset (non-interleaved)
		endc
SCREEN_SIZE = SCREEN_BW*SCREEN_H*BPLS				; byte size of screen buffer
DIW_BW = DIW_W/16*2
DIW_MOD = SCREEN_BW-DIW_BW+SCREEN_MOD-SCROLL*2
DIW_SIZE = DIW_BW*DIW_H*BPLS
DIW_XSTRT = ($242-DIW_W)/2
DIW_YSTRT = ($158-DIW_H)/2
DIW_XSTOP = DIW_XSTRT+DIW_W
DIW_YSTOP = DIW_YSTRT+DIW_H
DIW_STRT = (DIW_YSTRT<<8)!DIW_XSTRT
DIW_STOP = ((DIW_YSTOP-256)<<8)!(DIW_XSTOP-256)
DDF_STRT = ((DIW_XSTRT-17)>>1)&$00fc-SCROLL*8
DDF_STOP = ((DIW_XSTRT-17+(((DIW_W>>4)-1)<<4))>>1)&$00fc


********************************************************************************
		code_c
********************************************************************************

		lea	Data(pc),a5
		lea	custom+diwstrt,a6

		move.l	#DIW_STRT<<16!DIW_STOP,(a6)+
		move.l	#DDF_STRT<<16!DDF_STOP,(a6)+
		move.w	#DMAF_AUDIO!DMAB_DISK!DMAF_SPRITE!DMAB_BLITTER,(a6) ; Disable DMA

; Init copper:
		lea	Cop(pc),a0
		move.l	a0,cop1lc-dmacon(a6)

; Init sin table:
		lea	Data+Sin(pc),a0
		moveq	#0,d0
		move.w	#SIN_LEN/2+1,a1
.sin		subq.l	#2,a1
		move.l	d0,d1
		asr.l	#6,d1
		move.w	d1,(a0)+
		neg.w	d1
		move.w	d1,SIN_LEN-2(a0)
		add.l	a1,d0
		bne.b	.sin

; Clear initial screen:
; This should leave a4 at the start of the screen buffer
		lea	Screen+SCREEN_SIZE,a4
		move.w	#SCREEN_SIZE/4-1,d0
.cl		clr.l	-(a4)
		dbf	d0,.cl

; Palette:
; use d0 (currently -1) for color00
; use screen address for color01
		movem.w	d0/a4,color00-dmacon(a6)

;-------------------------------------------------------------------------------
.mainLoop:
; Increment and read frame:
		addq.l	#SPEED,(a5)
		move.l	(a5),d3					; d3 = frame

; Scroll screen left by frame count indefinitely...
; We'll run out of space eventually but hopefully no one sticks around that long!
		; byte offset
		move.w	d3,d7
		lsr.w	#4,d7
		add.w	d7,d7
		lea	(a4,d7),a0				; a0 = screen
		move.w	a0,CopBplPt-Data+2(a5)
		; px shift
		moveq	#15,d6
		and.w	d3,d6
		not.w	d6					; d6 = shift (need this later for plot offset)
		move.w	d6,CopScroll-Data+2(a5)

; Clear word on right of buffer to stop data looping back round:
		move.w	#SCREEN_H-1,d1
.cw		lea	SCREEN_BW-2(a0),a0
		clr.w	(a0)+
		dbf	d1,.cw

; Now we're going to draw a dot spiral...

		; Offset a0 to center/right of screen:
		sub.w	#14+140*SCREEN_BW,a0

		; scale = sin(frame)
		move.w	#SIN_LEN*2-2,d4				; d4 = sin table mask
		and.w	d4,d3
		move.w	Sin(a5,d3.w),d2				; d2 = scale

		; Use screen byte offset for dot count
		and.w	d4,d7
		lsr	#2,d7
.dot
		; y = sin(a)*scale
		move.w	d3,d5
		and.w	d4,d5
		move.w	Sin(a5,d5.w),d1
		muls	d2,d1
		asr.w	#6,d1

		; x = cos(a)*scale/2
		add.w	#SIN_LEN/2,d5				; offset for cos
		and.w	d4,d5
		move.w	Sin(a5,d5.w),d0
		muls	d2,d0
		asr.w	#7,d0					; half x for some kind of perspective
		sub.w	d6,d0					; adjust for bplcon0 scroll

		; Plot point:
		mulu	#SCREEN_BW,d1
		move.w	d0,d5
		not.w	d5
		asr.w	#3,d0
		add.w	d1,d0
		bset	d5,(a0,d0.w)

		addq	#8,d3					; increment angle
		subq	#1,d2					; decrment scale (this creates the sprial)
		dbf	d7,.dot

; Wait EOF
.sync		cmp.b	vhposr-dmacon(a6),d7
		bne.s	.sync

		bra.s	.mainLoop

;-------------------------------------------------------------------------------
; Copper list:
; Some sacrifices have to be made here!
Cop:
		dc.w	bpl1mod,DIW_MOD
		dc.w	bplcon0,BPLS<<(12+DPF)!DPF<<10!$200
		; dc.w	bpl0pt,Screen>>16
CopScroll:	dc.w	bplcon1,0
CopBplPt:	dc.w	bpl0ptl,0
		; dc.l	-2


;-------------------------------------------------------------------------------
; Treat space after code as BSS
; We don't exit anyway so trash all the things!
Data:
		rsreset
Frame:		rs.l	1
Sin:		rs.w	SIN_LEN
