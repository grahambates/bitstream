		incdir	"include"
		include	"hw.i"

********************************************************************************
* Constants:
********************************************************************************

C = bltsize
Screen = $d0000
SIN_LEN = 256
R = 64

; Display window:
DIW_W = 320
DIW_H = 256
BPLS = 1
SCROLL = 1							; enable playfield scroll
INTERLEAVED = 0
DPF = 0								; enable dual playfield

; Screen buffer:
SCREEN_W = DIW_W+16
SCREEN_H = DIW_H

DMASET = DMAF_SETCLR!DMAF_RASTER!DMAF_COPPER!DMAF_BLITTER

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

		rsreset
VBlank:		rs.l	1
Sin:		rs.w	SIN_LEN

********************************************************************************
		code_c
********************************************************************************

; Minimal startup:
		lea	custom+C,a6
		; move.w	#$7fff,d2				;clear all bits
		; move.w	d2,dmacon-C(a6)				;in DMACON,
		; move.w	d2,intena-C(a6)				;INTENA,
		; move.w	d2,intreq-C(a6)				;and INTREQ

; Init copper:
		lea	Cop(pc),a0
		move.l	a0,cop1lc-C(a6)
		; move.w	#DMASET,dmacon-C(a6)

********************************************************************************
; Populate sin table
;-------------------------------------------------------------------------------
		lea	Data+Sin(pc),a0
		moveq	#0,d0					; amp=16384, length=1024
		move.w	#SIN_LEN/2+1,a1
.l0		subq.l	#2,a1
		move.l	d0,d1
		asr.l	#6,d1
		move.w	d1,(a0)+
		neg.w	d1
		move.w	d1,SIN_LEN-2(a0)
		add.l	a1,d0
		bne.b	.l0

;-------------------------------------------------------------------------------
.mainLoop:
		; get and increment frame
		lea	Data(pc),a5				; a5 = data
		addq.l	#2,VBlank(a5)
		move.l	VBlank(a5),d3

; Scroll:
		move.w	d3,d0
		moveq	#15,d6
		and.w	d0,d6
		not.w	d6
		lsr.w	#4,d0
		add.w	d0,d0
		lea	Screen,a0				; a0 = screen
		lea	-2(a0,d0.w),a0

		move.w	d6,a3					; a3 = pixel offset - need this for plot

		; Update copper for scroll
		move.w	d6,CopScroll-Data+2(a5)
		move.w	a0,CopBplPt-Data+2(a5)

; Clear rhs word:
		moveq	#DIW_BW,d0
		add.w	d0,a0
		move.w	d0,bltdmod-C(a6)
		move.w	#$100,bltcon0-C(a6)
		move.l	a0,bltdpt-C(a6)
		move.w	#300*BPLS*64+1,bltsize-C(a6)

; Draw:
		; Center draw screen ptr
		lea	32+(110*SCREEN_BW)(a0),a0

		; Get scale:
		move.w	#SIN_LEN*2-2,d4
		and.w	d4,d3
		move.w	Sin(a5,d3.w),d2

		add.w	#$80,d2
		; add.w	d0,d2

		move.w	#R-1,d7					; d7 = iterator
.l
; circle coords
		move.w	d3,d5
		and.w	d4,d5
		move.w	Sin(a5,d5.w),d1				; d1 = y

		add.w	#SIN_LEN/2,d5				; offset for cos
		and.w	d4,d5
		move.w	Sin(a5,d5.w),d0				; d0 = x
; scale
		muls	d2,d1
		asr.w	#7,d1
		muls	d2,d0
		asr.w	#8,d0
		sub.w	a3,d0					; adjust for scroll

; Plot
		mulu	#SCREEN_BW,d1
		move.w	d0,d6
		not.w	d6
		asr.w	#3,d0
		add.w	d1,d0
		bset	d6,(a0,d0.w)

		addq	#SIN_LEN*2/R,d3				; rotate
		subq	#2,d2
		dbf	d7,.l

; Wait eof
.sync
		cmp.b	vhposr-C(a6),d7
		bne.s	.sync
		bra	.mainLoop

Cop:
		dc.w	dmacon,DMAF_SPRITE
		;dc.w	dmacon,DMASET
		; dc.w	fmode,0
		dc.w	diwstrt,DIW_STRT
		; dc.w	diwstop,DIW_STOP
		dc.w	ddfstrt,DDF_STRT
		; dc.w	ddfstop,DDF_STOP
		; dc.w	bpl1mod,DIW_MOD
		; dc.w	bpl2mod,DIW_MOD

CopPal:
		dc.w	color00,$314
		; dc.w	color01,$ffc
		dc.w	bplcon0,BPLS<<(12+DPF)!DPF<<10!$200
		dc.w	bpl0pt,Screen>>16
CopScroll:	dc.w	bplcon1,0
CopBplPt:	dc.w	bpl0ptl,0
		; dc.l	-2

Data:
