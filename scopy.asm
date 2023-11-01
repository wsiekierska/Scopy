global _start

; Wartości funkcji systemowych.
SYS_READ    equ 0
SYS_WRITE   equ 1
SYS_OPEN    equ 2
SYS_CLOSE   equ 3
SYS_EXIT    equ 60

O_CREAT		equ 00000100
O_EXCL		equ 00000200
O_WRONLY	equ 00000001

EXIT_FAIL   equ 1                      

section .data
    buf_len equ 4096                            ; Rozmiar bufora - po sprawdzeniu różnych rozmiarów: najkrótszy czas wykonywania programu dla 4096,
                                                ; ponadto w Linuxie o architekturze x86 w trybie 64-bitowym rozmiar jednej strony to 4096 bajtów.
    number  dq 0                                ; Liczba odczytanych bajtów w każdym wykonaniu pętli read_loop.
    len     dq 0                                ; Długość maksymalnego ciągu nie zwierającego 's' ani 'S'.
    out_len dq 0                                ; Długość buforu zapisu do pliku, maksymalnie będzie to 4096.

section .bss                 
    buf_in  resb buf_len                        ; Bufor odczytu.
    buf_out resb buf_len                        ; Bufor zapisu do pliku.

section .text

_start:
    mov     rcx, [rsp]                          ; Ładuję do rcx liczbę parametrów.
    cmp     rcx, 3                              ; Sprawdzam, czy są podane wszystkie parametry.
    jne     exit_error                          ; Jeśli nie, kończę program z kodem 1.

    mov     rax, SYS_OPEN                       ; Otwieram plik wejściowy (do odczytu).
    mov     rdi, [rsp + 16]                     ; Nazwa jest drugim z podanych parametrów.
    xor     rsi, rsi                            ; Flagi O_RDONLY.
    xor     rdx, rdx                            ; Tryb dostępu 0.
    syscall                             
    test    rax, rax                            ; Sprawdzam poprawność wykonania funkcji systemowej.
    js      exit_error                          ; Jeśli jej wynik jest ujemny (co oznacza błąd), kończę program z kodem 1.
    mov     r8, rax                             ; Deskryptor pliku wejściowego będzie przechowywany w rejestrze r8.


    mov     rax, SYS_OPEN                       ; Tworzę plik wyjściowy przy pomocy funkcji sys_open.
    mov     rsi, O_WRONLY | O_CREAT | O_EXCL    ; Używam flag pozwalających na utworzenie nieistniejącego pliku.
    mov     rdx, 0644o                          ; Dodaję uprawnienia -rw-r--r-- do nowego pliku.
    mov     rdi, [rsp + 24]                     ; Nazwa pliku wyjściowego jest trzecim parametrem.
    syscall
    test    rax, rax                            ; Sprawdzam poprawność wykonania funkcji, która zwraca błąd także, jeśli istnieje już plik wyjścia.
    js      exit_close_input                    ; Jeśli jej wynik jest ujemny, zamykam otwarty plik wejściowy i kończę program z kodem 1.
    mov     r9, rax                             ; Deskryptor pliku wyjściowego będzie trzymany w rejestrze r9.
    mov     qword [len], 0                      ; Ustawiam aktualną długość maksymalnego ciągu bez 's' lub 'S' na 0.
    mov     qword [out_len], 0                  ; Ustawiam aktualną długość ciągu do zapisu na 0. 

 read_loop:
    mov     rax, SYS_READ                       ; Odczytuję plik wejściowy.
    mov     rdi, r8                             ; Zapisuję do rdi deskryptor pliku wejściowego. 
    mov     rsi, buf_in                         ; Bufor odczytu.
    mov     rdx, buf_len                        ; Liczba bajtów do odczytu.
    syscall
    test    rax, rax                            ; Sprawdzam, czy mam już koniec pliku, czyli czy nic nie zostało odczytane.
    jz      final_exit                          ; Jeśli nic nie zostało odczytane, to kończę prograam.
    js      exit_close_output                   ; Jeśli funkcja systemowa nie wykonała się poprawnie, zamykam otwarte pliki i kończę program z kodem 1.
    mov     qword [out_len], 0                  ; Ustawiam długość napisu do wpisania do pliku wyjściowego na 0, bo rozpoczynamy też nowy bufor wejściowy. 
    mov     [number], rax                       ; Ustawiam number na liczbę odczytanych bajtów.
    xor     r10, r10                            ; Zeruję iterator odczytanych bajtów (będzie to rejestr r10), po których teraz będę przechodzić.

process_data:
    cmp     r10, [number]                       ; Sprawdzam, czy przeszłam już wszystkie bajty.
    je      write_buffer                        ; Jeśli tak, to dopiero teraz zapisuję wszystkie zgromadzone dane do pliku wyjścia.
    cmp     byte [buf_in + r10], 's'            ; W przeciwnym wypadku sprawdzam czy aktualny bit to "s" lub "S".
    je      write_length                        ; Jeśli tak, przechodzę do zapisu tego bajtu oraz długości aktualnego maksymalnego ciągu bez 's' / 'S'.
    cmp     byte [buf_in + r10], 'S'             
    je      write_length
    inc     qword [len]                         ; Jeśli nie, to zwiększam długość ww. ciągu.
    inc     r10                                 ; Zwiększam iterator, przechodzę do kolejnego bajtu.
    jmp     process_data
    
write_length:
    cmp     qword [len], 0                      ; Sprawdzam, czy mój aktualny ciąg bez 's' / 'S' jest pusty.
    je      write_char                          ; Jeśli jest, to przechodzę prosto do zapisania 's' lub 'S' do buforu wyjścia.
    mov     rsi, [len]                          ; Pomocniczo wrzucam aktualną długość ww. ciągu do rejestru rsi.
    mov     rax, [out_len]                      ; Oraz ustawiam rejestr rax na aktualną długość buforu wyjścia.
    mov     word [buf_out+rax], si              ; Dorzucam do buforu wyjścia aktualną długość ciągu modulo 65536, czyli najmłodsze 16 bitów rejestru rsi.
    add     qword [out_len], 2                  ; Zwiększam rozmiar aktualnego buforu wyjścia o 2, bo zapisana liczba miała 16 bitów - 2 bajty.
    mov     qword [len], 0                      ; Zeruję długość aktualnego maksymalnego ciągu bez 's' / 'S'.
    
write_char:
    mov     sil, byte[buf_in + r10]             ; Ustawiam pomocniczo rejestr sil na aktualnie rozpatrywany bajt.
    mov     rax, [out_len]                      ; Podobnie robię z aktualną długością buforu wyjścia.
    mov     byte [buf_out+rax], sil             ; Dorzucam do buforu wyjścia napotkany znak 's' lub 'S'.
    inc     qword [out_len]                     ; Zwiększam rozmiar aktualnego buforu wyjścia o 1, bo zapisałam znak zajmujący 1 bajt.
    inc     r10                                 ; Zwiększam iterator odczytanego wcześniej ciągu bajtów.
    jmp     process_data                

write_buffer:
    mov     rax, SYS_WRITE                      ; Teraz będę zapisywać do pliku wyjściowego aktualny bufor wyjścia o rozmiarze maks 4096 bajtów.
    mov     rsi, buf_out                        ; Bufor zapisu.
    mov     rdi, r9                             ; Zapisuję do rejestru rdi deskryptor pliku wyjściowego. 
    mov     rdx, [out_len]                      ; Do rejestru rdx wrzucam aktualny rozmiar buforu.
    syscall
    test    rax, rax                            ; Sprawdzam poprawność wykonania funkcji systemowej.
    js      exit_close_output
    jmp     read_loop                           ; Przechodzę do odczytu kolejnej porcji danych.

exit_error:
    mov     rax, SYS_EXIT               
    mov     rdi, EXIT_FAIL
    syscall

exit_close_output:
    mov     rax, SYS_CLOSE                      ; Zamykam plik wyjścia.
    mov     rdi, r9                             ; Zapisuję do rdi deskryptor pliku wyjściowego. 
    syscall

exit_close_input:
    mov     rax, SYS_CLOSE                      ; Zamykam plik wejścia.
    mov     rdi, r8                             ; Zapisuję do rdi deskryptor pliku wejściowego. 
    syscall
    jmp     exit_error                  

final_exit:
    cmp     qword [len], 0                      ; Sprawdzam, czy nie muszę do pliku wyjścia dopisać jeszcze długości ciągu bez 's' / 'S'.
    je      exit                                ; Jeśli taki ciąg jest pusty (czyli na końcu pliku wejścia stoi 's' / 'S'), kończę program.
    mov     rsi, len                            ; W przeciwnym przypadku rejestr rsi ustawiam na długość tego ciągu.         
    mov     rdi, r9                             ; Zapisuję do rdi deskryptor pliku wyjściowego. 
    mov     rdx, 2                              ; Zapisuję liczbę 16-bitową, więc rozmiar zapisu ustawiam na 2 bajty.
    mov     rax, SYS_WRITE                      ; Zapisuję długość ciągu do pliku wyjściowego.
    syscall
    test    rax, rax                            ; Sprawdzam poprawność wykonania funkcji systemowej.
    js      exit_close_output

exit:
    mov     rax, SYS_CLOSE                      ; Zamykam plik wyjściowy.
    mov     rdi, r9                             ; Zapisuję do rdi deskryptor pliku wyjściowego. 
    syscall
    test    rax, rax                            ; Sprawdzam poprawność wykonania funkcji systemowej.
    js      exit_close_input
    mov     rax, SYS_CLOSE                      ; Zamykam plik wejściowy.
    mov     rdi, r8                             ; Deskryptor pliku wejścia.
    syscall
    test    rax, rax                            ; Sprawdzam poprawność wykonania funkcji systemowej.
    js      exit_error
    mov     rax, SYS_EXIT                       ; Kończę program z kodem 0.
    xor     rdi, rdi
    syscall