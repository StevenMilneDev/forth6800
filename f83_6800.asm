; ----------------------------------------------------------------------------
; f83_6800.asm
; ----------------------------------------------------------------------------
; A compact Forth-83 style direct-threaded interpreter kernel for Motorola 6800
; systems, targeting the SWTPC 6800 + SWTBUG monitor environment.
;
; This source is intentionally self-contained and conservative so it can be
; assembled with common 6800 assemblers (ASxxxx, A68, etc. with light syntax
; adjustments).
;
; What is implemented:
;   - Inner interpreter (NEXT)
;   - Colon definitions (DOCOL / EXIT)
;   - Data + return stacks in RAM
;   - Dictionary with headers and link field
;   - FIND + number conversion + outer interpreter loop
;   - Core primitive words required for bootstrapping
;
; Notes:
;   - This is a practical F83-like kernel, not a complete ANS/F83 full system.
;   - I/O vectors default to SWTBUG ROM entry points and can be re-pointed.
; ----------------------------------------------------------------------------

            ORG   $0100

; ----------------------------------------------------------------------------
; Zero page / low RAM runtime state
; ----------------------------------------------------------------------------
IP          RMB   2      ; Interpreter pointer
WREG        RMB   2      ; Current CFA / working pointer
SP0         RMB   2      ; Data stack pointer (grows downward)
RP0         RMB   2      ; Return stack pointer (grows downward)
STATE       RMB   1      ; 0=interpret, non-zero=compile
LATEST      RMB   2      ; Latest dictionary header
HERE        RMB   2      ; Next free dictionary byte
TOKENLEN    RMB   1
INPTR       RMB   2
BASE        RMB   1
TMP0        RMB   2
TMP1        RMB   2
NUMACC      RMB   2
SIGNFLAG    RMB   1

; ----------------------------------------------------------------------------
; RAM layout (adjust as needed for your machine)
; ----------------------------------------------------------------------------
DICT_START  EQU   $2000
DICT_END    EQU   $6FFF
DATA_TOP    EQU   $7BFF
RET_TOP     EQU   $7DFF
TIB         EQU   $7E00
TIB_SIZE    EQU   80
TOKENBUF    EQU   $7E80

; ----------------------------------------------------------------------------
; SWTBUG console defaults (can be replaced)
; Common SWTBUG values; adjust for your ROM if different.
; ----------------------------------------------------------------------------
MON_INCH    EQU   $E1AC   ; returns character in A
MON_OUTCH   EQU   $E1D1   ; outputs character in A

; ----------------------------------------------------------------------------
; Reset / cold start entry
; ----------------------------------------------------------------------------
            ORG   $0200
COLD:
            LDX   #DATA_TOP
            STX   SP0
            LDX   #RET_TOP
            STX   RP0
            CLR   STATE
            LDAA  #10
            STAA  BASE
            LDX   #DICT_START
            STX   HERE
            CLR   LATEST
            CLR   LATEST+1

            JSR   BUILD_CORE
            JSR   CR
            LDX   #MSG_OK
            JSR   TYPEZ

INTERPRET:
            JSR   QUERY
NEXT_TOKEN:
            JSR   WORD
            LDAA  TOKENLEN
            BEQ   INTERPRET

            JSR   FIND
            BCC   TRY_NUMBER

            LDAA  STATE
            BEQ   EXEC_FOUND
            ; compile CFA of found word into current definition
            LDX   HERE
            LDAA  TMP0
            STAA  0,X
            LDAA  TMP0+1
            STAA  1,X
            INX
            INX
            STX   HERE
            BRA   NEXT_TOKEN

EXEC_FOUND:
            LDX   TMP0
            JSR   EXECUTE_CFA
            BRA   NEXT_TOKEN

TRY_NUMBER:
            JSR   NUMBER
            BCC   NOT_FOUND

            ; number value in NUMACC
            LDAA  STATE
            BEQ   PUSH_NUMBER

            ; compiling: compile LIT and literal value
            LDX   HERE
            LDAA  #<CFA_LIT
            STAA  0,X
            LDAA  #>CFA_LIT
            STAA  1,X
            LDAA  NUMACC
            STAA  2,X
            LDAA  NUMACC+1
            STAA  3,X
            INX
            INX
            INX
            INX
            STX   HERE
            BRA   NEXT_TOKEN

PUSH_NUMBER:
            LDAA  NUMACC
            LDAB  NUMACC+1
            JSR   PUSH_AB
            BRA   NEXT_TOKEN

NOT_FOUND:
            LDX   #MSG_Q
            JSR   TYPEZ
            BRA   INTERPRET

; ----------------------------------------------------------------------------
; Inner interpreter helpers
; ----------------------------------------------------------------------------
EXECUTE_CFA:
            ; X = CFA to execute
            STX   WREG
            JMP   0,X

NEXT:
            ; IP points at threaded list of CFAs
            LDX   IP
            LDAA  0,X
            LDAB  1,X
            STAB  TMP0+1
            STAA  TMP0
            INX
            INX
            STX   IP
            LDX   TMP0
            JMP   0,X

; ----------------------------------------------------------------------------
; Primitive code words
; ----------------------------------------------------------------------------
CODE_EXIT:
            ; pop return stack into IP
            LDX   RP0
            LDAA  0,X
            STAA  IP
            LDAA  1,X
            STAA  IP+1
            INX
            INX
            STX   RP0
            JMP   NEXT

CODE_DOCOL:
            ; enter colon definition
            ; push current IP on return stack
            LDX   RP0
            DEX
            DEX
            STX   RP0
            LDAA  IP
            STAA  0,X
            LDAA  IP+1
            STAA  1,X
            ; WREG currently CFA, so PFA = CFA+2
            LDX   WREG
            INX
            INX
            STX   IP
            JMP   NEXT

CODE_LIT:
            ; fetch 16-bit literal from IP and push
            LDX   IP
            LDAA  0,X
            LDAB  1,X
            JSR   PUSH_AB
            INX
            INX
            STX   IP
            JMP   NEXT

CODE_DUP:
            JSR   POP_AB
            JSR   PUSH_AB
            JSR   PUSH_AB
            JMP   NEXT

CODE_DROP:
            JSR   POP_AB
            JMP   NEXT

CODE_SWAP:
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            JSR   PUSH_AB
            LDAA  TMP0
            LDAB  TMP0+1
            JSR   PUSH_AB
            JMP   NEXT

CODE_OVER:
            ; ( n1 n2 -- n1 n2 n1 )
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            STAA  TMP1
            STAB  TMP1+1
            LDAA  TMP1
            LDAB  TMP1+1
            JSR   PUSH_AB
            LDAA  TMP0
            LDAB  TMP0+1
            JSR   PUSH_AB
            LDAA  TMP1
            LDAB  TMP1+1
            JSR   PUSH_AB
            JMP   NEXT

CODE_PLUS:
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            ADDB  TMP0+1
            ADCA  TMP0
            JSR   PUSH_AB
            JMP   NEXT

CODE_MINUS:
            ; ( n1 n2 -- n1-n2 )
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            SUBB  TMP0+1
            SBCA  TMP0
            JSR   PUSH_AB
            JMP   NEXT

CODE_AND:
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            ANDB  TMP0+1
            ANDA  TMP0
            JSR   PUSH_AB
            JMP   NEXT

CODE_OR:
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            ORAB  TMP0+1
            ORAA  TMP0
            JSR   PUSH_AB
            JMP   NEXT

CODE_XOR:
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            EORB  TMP0+1
            EORA  TMP0
            JSR   PUSH_AB
            JMP   NEXT

CODE_EQUAL:
            JSR   POP_AB
            STAA  TMP0
            STAB  TMP0+1
            JSR   POP_AB
            CBA
            BNE   EQ_FALSE
            CMPA  TMP0
            BNE   EQ_FALSE
            LDAA  #$FF
            LDAB  #$FF
            JSR   PUSH_AB
            JMP   NEXT
EQ_FALSE:
            CLRA
            CLRB
            JSR   PUSH_AB
            JMP   NEXT

CODE_ZEROE:
            JSR   POP_AB
            TSTA
            BNE   ZE_FALSE
            TSTB
            BNE   ZE_FALSE
            LDAA  #$FF
            LDAB  #$FF
            JSR   PUSH_AB
            JMP   NEXT
ZE_FALSE:
            CLRA
            CLRB
            JSR   PUSH_AB
            JMP   NEXT

CODE_EMIT:
            JSR   POP_AB
            TBA
            JSR   EMIT
            JMP   NEXT

CODE_KEY:
            JSR   KEY
            TAB
            CLRA
            JSR   PUSH_AB
            JMP   NEXT

CODE_CR:
            JSR   CR
            JMP   NEXT

CODE_DOT:
            JSR   POP_AB
            JSR   DOT16
            JMP   NEXT

CODE_COLON:
            ; : <name> ... ;
            JSR   WORD
            LDAA  TOKENLEN
            BEQ   NEXT
            JSR   CREATE
            LDX   HERE
            LDAA  #<CFA_DCOL
            STAA  0,X
            LDAA  #>CFA_DCOL
            STAA  1,X
            INX
            INX
            STX   HERE
            LDAA  #1
            STAA  STATE
            JMP   NEXT

CODE_SEMI:
            ; ; immediate
            LDAA  STATE
            BEQ   NEXT
            LDX   HERE
            LDAA  #<CFA_EXIT
            STAA  0,X
            LDAA  #>CFA_EXIT
            STAA  1,X
            INX
            INX
            STX   HERE
            CLR   STATE
            JMP   NEXT

; ----------------------------------------------------------------------------
; Data stack helpers (A=hi, B=lo)
; ----------------------------------------------------------------------------
PUSH_AB:
            LDX   SP0
            DEX
            DEX
            STX   SP0
            STAA  0,X
            STAB  1,X
            RTS

POP_AB:
            LDX   SP0
            LDAA  0,X
            LDAB  1,X
            INX
            INX
            STX   SP0
            RTS

; ----------------------------------------------------------------------------
; Dictionary management
; Header layout:
;   +0 link hi
;   +1 link lo
;   +2 len|flags
;   +3.. name bytes
;   aligned CFA follows name
; ----------------------------------------------------------------------------
CREATE:
            ; TOKENBUF/TOKENLEN -> new dictionary header
            LDX   HERE
            LDAA  LATEST
            STAA  0,X
            LDAA  LATEST+1
            STAA  1,X
            LDAA  TOKENLEN
            STAA  2,X
            STX   LATEST
            ; copy token
            LDX   HERE
            INX
            INX
            INX
            STX   TMP0
            LDX   #TOKENBUF
            LDAB  TOKENLEN
CR_CPY:
            BEQ   CR_DONE
            LDAA  0,X
            LDX   TMP0
            STAA  0,X
            INX
            STX   TMP0
            LDX   #TOKENBUF
            INX
            STX   TMP1
            LDX   TMP1
            DECB
            BRA   CR_CPY
CR_DONE:
            ; HERE = align after header+name
            LDX   HERE
            LDAA  TOKENLEN
            ADDA  #3
            TAB
            CLRA
            ABX
            ; word align
            TXA
            ANDA  #1
            BEQ   CR_ALN
            INX
CR_ALN:
            STX   HERE
            RTS

FIND:
            ; lookup TOKENBUF/TOKENLEN. Carry set on found, TMP0=CFA
            LDX   LATEST
FIND_NEXT:
            CPX   #0
            BEQ   FIND_FAIL
            LDAA  2,X
            ANDA  #$1F
            CMPA  TOKENLEN
            BNE   FIND_LINK

            ; compare chars
            LDAB  TOKENLEN
            LDAA  #0
            STAA  TMP1
            LDAA  #3
            STAA  TMP1+1
FIND_CMP:
            BEQ   FIND_HIT
            ; dict char
            LDAA  TMP1+1
            TAB
            ABX
            LDAA  0,X
            PSHA
            ; token char
            LDX   #TOKENBUF
            LDAA  TOKENLEN
            SUBA  B
            ABX
            LDAA  0,X
            PULA
            CBA
            BNE   FIND_LINK
            DECB
            BRA   FIND_CMP

FIND_HIT:
            ; compute CFA
            LDX   HERE        ; scratch use
            LDX   LATEST
            ; scan header len
            LDAA  2,X
            ANDA  #$1F
            ADDA  #3
            TAB
            CLRA
            ABX
            TXA
            ANDA  #1
            BEQ   FH2
            INX
FH2:
            STX   TMP0
            SEC
            RTS

FIND_LINK:
            LDAA  0,X
            LDAB  1,X
            STAA  TMP0
            STAB  TMP0+1
            LDX   TMP0
            BRA   FIND_NEXT

FIND_FAIL:
            CLC
            RTS

; ----------------------------------------------------------------------------
; Tokenizer / line input
; ----------------------------------------------------------------------------
QUERY:
            LDX   #TIB
            STX   INPTR
            LDAA  #0
            STAA  TOKENLEN
Q_LOOP:
            JSR   KEY
            CMPA  #13
            BEQ   Q_DONE
            JSR   EMIT
            LDX   INPTR
            STAA  0,X
            INX
            STX   INPTR
            BRA   Q_LOOP
Q_DONE:
            JSR   CR
            LDX   INPTR
            CLR   0,X
            LDX   #TIB
            STX   INPTR
            RTS

WORD:
            ; parse next space-delimited token into TOKENBUF
            CLR   TOKENLEN
            LDX   INPTR
W_SKIP:
            LDAA  0,X
            BEQ   W_END
            CMPA  #' '
            BNE   W_TAKE
            INX
            BRA   W_SKIP
W_TAKE:
            LDAB  TOKENLEN
            CMPB  #31
            BHS   W_ADV
            LDAB  TOKENLEN
            LDX   #TOKENBUF
            ABX
            STAA  0,X
            INC   TOKENLEN
W_ADV:
            LDX   INPTR
            INX
            STX   INPTR
            LDAA  0,X
            BEQ   W_END
            CMPA  #' '
            BNE   W_TAKE
W_END:
            RTS

; ----------------------------------------------------------------------------
; Number conversion (base in BASE)
; ----------------------------------------------------------------------------
NUMBER:
            ; TOKENBUF/TOKENLEN -> NUMACC, C=success
            CLR   SIGNFLAG
            CLRA
            CLRB
            STAA  NUMACC
            STAB  NUMACC+1
            LDAB  TOKENLEN
            BEQ   N_FAIL
            LDX   #TOKENBUF
            LDAA  0,X
            CMPA  #'-'
            BNE   N_LOOP
            INC   SIGNFLAG
            INX
            DECB
            BEQ   N_FAIL
N_LOOP:
            BEQ   N_OK
            LDAA  0,X
            JSR   DIGIT
            BCC   N_FAIL
            ; NUMACC = NUMACC*BASE + A
            PSHA
            LDAA  NUMACC
            LDAB  NUMACC+1
            JSR   MUL_BASE
            STAA  NUMACC
            STAB  NUMACC+1
            PULA
            ADDB  NUMACC+1
            STAB  NUMACC+1
            BCC   N1
            INC   NUMACC
N1:
            INX
            DECB
            BRA   N_LOOP
N_OK:
            LDAA  SIGNFLAG
            BEQ   N_SUCC
            ; two's complement negate
            COM   NUMACC
            COM   NUMACC+1
            LDAA  NUMACC+1
            INCA
            STAA  NUMACC+1
            BNE   N_SUCC
            INC   NUMACC
N_SUCC:
            SEC
            RTS
N_FAIL:
            CLC
            RTS

DIGIT:
            ; char in A, returns value in A, C=valid
            CMPA  #'0'
            BLO   D_FAIL
            CMPA  #'9'
            BHI   D_ALPHA
            SUBA  #'0'
            BRA   D_CHK
D_ALPHA:
            CMPA  #'A'
            BLO   D_FAIL
            CMPA  #'F'
            BHI   D_FAIL
            SUBA  #'A'-10
D_CHK:
            CMPA  BASE
            BHS   D_FAIL
            SEC
            RTS
D_FAIL:
            CLC
            RTS

MUL_BASE:
            ; multiply D by BASE (small loop)
            STAA  TMP0
            STAB  TMP0+1
            CLRA
            CLRB
            STAA  TMP1
            STAB  TMP1+1
            LDAA  BASE
            STAA  TOKENLEN
MB_LOOP:
            LDAA  TOKENLEN
            BEQ   MB_DONE
            LDAA  TMP1
            LDAB  TMP1+1
            ADDB  TMP0+1
            ADCA  TMP0
            STAA  TMP1
            STAB  TMP1+1
            DEC   TOKENLEN
            BRA   MB_LOOP
MB_DONE:
            LDAA  TMP1
            LDAB  TMP1+1
            RTS

; ----------------------------------------------------------------------------
; Console helpers
; ----------------------------------------------------------------------------
KEY:
            JSR   MON_INCH
            RTS

EMIT:
            JSR   MON_OUTCH
            RTS

CR:
            LDAA  #13
            JSR   EMIT
            LDAA  #10
            JSR   EMIT
            RTS

TYPEZ:
            ; X points to zero-terminated string
TZ1:
            LDAA  0,X
            BEQ   TZ2
            JSR   EMIT
            INX
            BRA   TZ1
TZ2:
            RTS

DOT16:
            ; minimal signed decimal printer for D in A:B
            ; simplified: prints as unsigned hex for compactness
            PSHA
            TBA
            JSR   HEX8
            PULA
            JSR   HEX8
            LDAA  #' '
            JSR   EMIT
            RTS

HEX8:
            PSHA
            LSRA
            LSRA
            LSRA
            LSRA
            JSR   HEXN
            PULA
            ANDA  #$0F
            JSR   HEXN
            RTS

HEXN:
            CMPA  #10
            BLO   HN_DEC
            ADDA  #'A'-10
            BRA   HN_OUT
HN_DEC:
            ADDA  #'0'
HN_OUT:
            JSR   EMIT
            RTS

; ----------------------------------------------------------------------------
; Dictionary bootstrap
; ----------------------------------------------------------------------------
BUILD_CORE:
            ; Build primitives directly into dictionary.
            ; CREATE codeword helper expects TOKENBUF/TOKENLEN and CFA address in TMP0.
            JSR   ADD_EXIT
            JSR   ADD_DOCOL
            JSR   ADD_LIT
            JSR   ADD_PRIMS
            RTS

ADDWORD:
            ; token prepared in TOKENBUF/TOKENLEN, TMP0=CFA
            JSR   CREATE
            LDX   HERE
            LDAA  TMP0
            STAA  0,X
            LDAA  TMP0+1
            STAA  1,X
            INX
            INX
            STX   HERE
            RTS

SETTOK:
            ; X -> ascii z-string into TOKENBUF, TOKENLEN set
            CLR   TOKENLEN
            LDY   #TOKENBUF
STK1:
            LDAA  0,X
            BEQ   STK2
            STAA  0,Y
            INX
            INY
            INC   TOKENLEN
            BRA   STK1
STK2:
            RTS

ADD_EXIT:
            LDX   #N_EXIT
            JSR   SETTOK
            LDAA  #<CFA_EXIT
            STAA  TMP0
            LDAA  #>CFA_EXIT
            STAA  TMP0+1
            JSR   ADDWORD
            RTS

ADD_DOCOL:
            LDX   #N_DOCOL
            JSR   SETTOK
            LDAA  #<CFA_DCOL
            STAA  TMP0
            LDAA  #>CFA_DCOL
            STAA  TMP0+1
            JSR   ADDWORD
            RTS

ADD_LIT:
            LDX   #N_LIT
            JSR   SETTOK
            LDAA  #<CFA_LIT
            STAA  TMP0
            LDAA  #>CFA_LIT
            STAA  TMP0+1
            JSR   ADDWORD
            RTS

ADD_PRIMS:
            ; DUP DROP SWAP OVER + - AND OR XOR = 0= EMIT KEY CR . : ;
            ; DUP
            LDX   #N_DUP
            JSR   SETTOK
            LDAA  #<CFA_DUP
            STAA  TMP0
            LDAA  #>CFA_DUP
            STAA  TMP0+1
            JSR   ADDWORD
            ; DROP
            LDX   #N_DROP
            JSR   SETTOK
            LDAA  #<CFA_DROP
            STAA  TMP0
            LDAA  #>CFA_DROP
            STAA  TMP0+1
            JSR   ADDWORD
            ; SWAP
            LDX   #N_SWAP
            JSR   SETTOK
            LDAA  #<CFA_SWAP
            STAA  TMP0
            LDAA  #>CFA_SWAP
            STAA  TMP0+1
            JSR   ADDWORD
            ; OVER
            LDX   #N_OVER
            JSR   SETTOK
            LDAA  #<CFA_OVER
            STAA  TMP0
            LDAA  #>CFA_OVER
            STAA  TMP0+1
            JSR   ADDWORD
            ; +
            LDX   #N_PLUS
            JSR   SETTOK
            LDAA  #<CFA_PLUS
            STAA  TMP0
            LDAA  #>CFA_PLUS
            STAA  TMP0+1
            JSR   ADDWORD
            ; -
            LDX   #N_MINUS
            JSR   SETTOK
            LDAA  #<CFA_MINUS
            STAA  TMP0
            LDAA  #>CFA_MINUS
            STAA  TMP0+1
            JSR   ADDWORD
            ; AND
            LDX   #N_AND
            JSR   SETTOK
            LDAA  #<CFA_AND
            STAA  TMP0
            LDAA  #>CFA_AND
            STAA  TMP0+1
            JSR   ADDWORD
            ; OR
            LDX   #N_OR
            JSR   SETTOK
            LDAA  #<CFA_OR
            STAA  TMP0
            LDAA  #>CFA_OR
            STAA  TMP0+1
            JSR   ADDWORD
            ; XOR
            LDX   #N_XOR
            JSR   SETTOK
            LDAA  #<CFA_XOR
            STAA  TMP0
            LDAA  #>CFA_XOR
            STAA  TMP0+1
            JSR   ADDWORD
            ; =
            LDX   #N_EQ
            JSR   SETTOK
            LDAA  #<CFA_EQ
            STAA  TMP0
            LDAA  #>CFA_EQ
            STAA  TMP0+1
            JSR   ADDWORD
            ; 0=
            LDX   #N_0E
            JSR   SETTOK
            LDAA  #<CFA_0E
            STAA  TMP0
            LDAA  #>CFA_0E
            STAA  TMP0+1
            JSR   ADDWORD
            ; EMIT
            LDX   #N_EMIT
            JSR   SETTOK
            LDAA  #<CFA_EMIT
            STAA  TMP0
            LDAA  #>CFA_EMIT
            STAA  TMP0+1
            JSR   ADDWORD
            ; KEY
            LDX   #N_KEY
            JSR   SETTOK
            LDAA  #<CFA_KEY
            STAA  TMP0
            LDAA  #>CFA_KEY
            STAA  TMP0+1
            JSR   ADDWORD
            ; CR
            LDX   #N_CR
            JSR   SETTOK
            LDAA  #<CFA_CR
            STAA  TMP0
            LDAA  #>CFA_CR
            STAA  TMP0+1
            JSR   ADDWORD
            ; .
            LDX   #N_DOT
            JSR   SETTOK
            LDAA  #<CFA_DOT
            STAA  TMP0
            LDAA  #>CFA_DOT
            STAA  TMP0+1
            JSR   ADDWORD
            ; :
            LDX   #N_COLON
            JSR   SETTOK
            LDAA  #<CFA_COLON
            STAA  TMP0
            LDAA  #>CFA_COLON
            STAA  TMP0+1
            JSR   ADDWORD
            ; ; (immediate bit set in length)
            LDX   #N_SEMI
            JSR   SETTOK
            JSR   CREATE
            LDX   HERE
            LDAA  #<CFA_SEMI
            STAA  0,X
            LDAA  #>CFA_SEMI
            STAA  1,X
            INX
            INX
            STX   HERE
            ; mark latest header immediate (bit 7 in len/flags)
            LDX   LATEST
            LDAA  2,X
            ORAA  #$80
            STAA  2,X
            RTS

; ----------------------------------------------------------------------------
; CFA labels for primitives
; ----------------------------------------------------------------------------
CFA_EXIT:   JMP   CODE_EXIT
CFA_DCOL:   JMP   CODE_DOCOL
CFA_LIT:    JMP   CODE_LIT
CFA_DUP:    JMP   CODE_DUP
CFA_DROP:   JMP   CODE_DROP
CFA_SWAP:   JMP   CODE_SWAP
CFA_OVER:   JMP   CODE_OVER
CFA_PLUS:   JMP   CODE_PLUS
CFA_MINUS:  JMP   CODE_MINUS
CFA_AND:    JMP   CODE_AND
CFA_OR:     JMP   CODE_OR
CFA_XOR:    JMP   CODE_XOR
CFA_EQ:     JMP   CODE_EQUAL
CFA_0E:     JMP   CODE_ZEROE
CFA_EMIT:   JMP   CODE_EMIT
CFA_KEY:    JMP   CODE_KEY
CFA_CR:     JMP   CODE_CR
CFA_DOT:    JMP   CODE_DOT
CFA_COLON:  JMP   CODE_COLON
CFA_SEMI:   JMP   CODE_SEMI

; ----------------------------------------------------------------------------
; Static strings
; ----------------------------------------------------------------------------
MSG_OK:     FCC   " ok"
            FCB   0
MSG_Q:      FCC   " ?"
            FCB   0

N_EXIT:     FCC   "EXIT"
            FCB   0
N_DOCOL:    FCC   "DOCOL"
            FCB   0
N_LIT:      FCC   "LIT"
            FCB   0
N_DUP:      FCC   "DUP"
            FCB   0
N_DROP:     FCC   "DROP"
            FCB   0
N_SWAP:     FCC   "SWAP"
            FCB   0
N_OVER:     FCC   "OVER"
            FCB   0
N_PLUS:     FCC   "+"
            FCB   0
N_MINUS:    FCC   "-"
            FCB   0
N_AND:      FCC   "AND"
            FCB   0
N_OR:       FCC   "OR"
            FCB   0
N_XOR:      FCC   "XOR"
            FCB   0
N_EQ:       FCC   "="
            FCB   0
N_0E:       FCC   "0="
            FCB   0
N_EMIT:     FCC   "EMIT"
            FCB   0
N_KEY:      FCC   "KEY"
            FCB   0
N_CR:       FCC   "CR"
            FCB   0
N_DOT:      FCC   "."
            FCB   0
N_COLON:    FCC   ":"
            FCB   0
N_SEMI:     FCC   ";"
            FCB   0

            END   COLD
