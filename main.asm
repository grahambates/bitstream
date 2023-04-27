		incdir	"include"
		include	"hw.i"

C = vhposr							; At least one of our custom reg writes can be (An) rather than (d,An)
Screen = $1000							; Use a fixed address for screen buffer
SIN_LEN = 256
DOTS = 64
SPEED = 2

; Display window:
DIW_W = 320
DIW_H = 256
BPLS = 1
SCROLL = 1							; enable playfield scroll?
INTERLEAVED = 0
DPF = 0								; enable dual playfield?

; Screen buffer:
SCREEN_W = DIW_W+16
SCREEN_H = DIW_H+16

DMASET = DMAF_SETCLR!DMAF_MASTER!DMAF_RASTER!DMAF_COPPER

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
		lea	custom+C,a6

; No space for this ¯\_(ツ)_/¯
		; move.w	#$7fff,d2				;clear all bits
		; move.w	d2,dmacon-C(a6)				;in DMACON,
		; move.w	d2,intena-C(a6)				;INTENA,
		; move.w	d2,intreq-C(a6)				;and INTREQ

; Use custom offset for some kind of palette!
		move.l	a6,color00-C(a6)

; Init copper:
		lea	Cop(pc),a0
		move.l	a0,cop1lc-C(a6)

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

;-------------------------------------------------------------------------------
.mainLoop:
; Increment and read frame:
		addq.l	#SPEED,(a5)
		move.l	(a5),d3

; Scroll screen left by frame count indefinitely...
; We'll run out of space eventually but hopefully no one sticks around that long!
		; byte offset
		move.w	d3,d0
		lsr.w	#4,d0
		add.w	d0,d0
		lea	(a4,d0),a0				; a0 = screen
		move.w	a0,CopBplPt-Data+2(a5)
		; px shift
		moveq	#15,d1
		and.w	d3,d1
		not.w	d1
		move.w	d1,CopScroll-Data+2(a5)
		; store in a spare register - need this later for plot offset
		move.w	d1,a3

; Clear word on right of buffer to stop data looping back round:
		move.w	#SCREEN_H-1,d1
.cw		lea	DIW_BW(a0),a0
		clr.w	(a0)+
		dbf	d1,.cw

; Now we're going to draw a dot spiral...

		; Offset a0 to center of screen:
		sub.w	#11+140*SCREEN_BW,a0

		; scale = sin(frame)
		move.w	#SIN_LEN*2-2,d4				; d4 = sin table mask
		and.w	d4,d3
		move.w	Sin(a5,d3.w),d2				; d2 = scale

		; Use frame*3 as start angle for rotation.
		; This gives more variation than if it used the same period as scale.
		mulu	#3,d3					; d3 = angle

		move.w	#DOTS-1,d7				; d7 = iterator
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
		sub.w	a3,d0					; adjust for bplcon0 scroll

		; Plot point:
		mulu	#SCREEN_BW,d1
		move.w	d0,d6
		not.w	d6
		asr.w	#3,d0
		add.w	d1,d0
		bset	d6,(a0,d0.w)

		addq	#SIN_LEN*2/DOTS,d3			; increment angle
		subq	#1,d2					; decrment scale (this creates the sprial)
		dbf	d7,.dot

; Wait EOF
.sync		cmp.b	vhposr-C(a6),d7
		bne.s	.sync

		bra.s	.mainLoop

;-------------------------------------------------------------------------------
; Copper list:
; Some sacrafices have to be made here!
Cop:
		dc.w	dmacon,DMAF_SPRITE ; Disable sprite DMA
		; dc.w 	dmacon,DMASET
		dc.w	diwstrt,DIW_STRT
		; dc.w	diwstop,DIW_STOP
		dc.w	ddfstrt,DDF_STRT
		dc.w	ddfstop,DDF_STOP
		dc.w	bpl1mod,DIW_MOD
		; dc.w	color00,$341
		; dc.w	color01,$fcf
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
