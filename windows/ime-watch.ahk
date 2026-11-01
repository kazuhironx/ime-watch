#Requires AutoHotkey v2.0
#SingleInstance Force
; IME 既定ウィンドウは非表示なので、これが無いと SendMessage が対象を見つけられない
DetectHiddenWindows(true)
; IME 切替キーを押すたびに、キャレット横へ現在のモードを一瞬出す。
; MS-IME の通知はトレイにしか出ず、横長ディスプレイでは視線が届かない。
; モードが変わらない押下でも出すのは、今どちらかを確かめたいときに押せるようにするため。

; キャレット座標・モニタ座標・ウィンドウ位置を物理ピクセルで揃える
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

POPUP_MS := 700
; キーを IME が処理し終える前に読むと、切替前の状態が返る
SETTLE_MS := 60
POPUP_W := 80
POPUP_H := 60
COLOR_ON := "FFB347"
COLOR_OFF := "FFFFFF"

; IME を切り替えるキー。~ で IME へ素通しする。
; Alt+` は 101 配列での MS-IME 既定の切替、変換/無変換は IME オン/オフ。
; vk1A/vk16 は HHKB の英数/かな (HID Lang2/Lang1)。スキャンコードが 0x1F1/0x1F2 と
; 変換/無変換とは別物で届くので、仮想キーで指定する
IME_KEYS := ["~!sc029", "*~sc079", "*~sc07B", "*~vk1A", "*~vk16"]

for key in IME_KEYS
    Hotkey(key, (*) => SetTimer(ShowMode, -SETTLE_MS))

A_IconTip := "ime-watch"

; WS_EX_NOACTIVATE | WS_EX_TRANSPARENT: フォーカスを奪わず、クリックも下へ通す
popup := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000020")
popup.BackColor := "1E1E1E"
popup.MarginX := 0
popup.MarginY := 0
popup.SetFont("s26 bold c" COLOR_OFF, "Yu Gothic UI")
label := popup.AddText("w" POPUP_W " h" POPUP_H " Center 0x200")  ; 0x200 = SS_CENTERIMAGE
; WS_EX_TRANSPARENT のクリック透過は layered ウィンドウでないと効かない
WinSetTransparent(235, popup)
; DWMWA_WINDOW_CORNER_PREFERENCE = DWMWCP_ROUND (Windows 11)
DllCall("dwmapi\DwmSetWindowAttribute", "ptr", popup.Hwnd, "int", 33, "int*", 2, "int", 4)

ShowMode() {
    mode := ImeMode()
    if !mode
        return
    label.Text := mode.text
    label.SetFont("c" (mode.kana ? COLOR_ON : COLOR_OFF))
    PopupPos(&x, &y)
    popup.Show("x" x " y" y " NoActivate")
    ; 連打したら最後の押下から数え直す
    SetTimer(HidePopup, -POPUP_MS)
}

HidePopup() {
    popup.Hide()
}

ImeMode() {
    hwnd := FocusedHwnd()
    ime := hwnd ? DllCall("imm32\ImmGetDefaultIMEWnd", "ptr", hwnd, "ptr") : 0
    if !ime
        return ""
    try {
        ; WM_IME_CONTROL: IMC_GETOPENSTATUS / IMC_GETCONVERSIONMODE
        open := SendMessage(0x283, 0x5, 0, , ime, , , , 200)
        conv := SendMessage(0x283, 0x1, 0, , ime, , , , 200)
    } catch
        return ""
    full := conv & 0x8
    if !open
        return {text: "A", kana: false}
    if conv & 0x1 {  ; IME_CMODE_NATIVE
        if conv & 0x2  ; IME_CMODE_KATAKANA
            return {text: full ? "カ" : "ｶ", kana: true}
        return {text: "あ", kana: true}
    }
    return {text: full ? "Ａ" : "A", kana: false}
}

GuiThreadInfo() {
    gti := Buffer(A_PtrSize = 8 ? 72 : 48, 0)
    NumPut("uint", gti.Size, gti)
    return DllCall("GetGUIThreadInfo", "uint", 0, "ptr", gti) ? gti : ""
}

FocusedHwnd() {
    gti := GuiThreadInfo()
    if !gti
        return 0
    return NumGet(gti, 8 + A_PtrSize, "ptr") || NumGet(gti, 8, "ptr")
}

PopupPos(&x, &y) {
    if CaretRect(&cx, &cy, &cw, &ch) {
        refX := cx, refY := cy
        x := cx + cw + 12, y := cy + ch + 8
    } else {
        ; キャレットが取れないアプリでは、作業中のウィンドウの中央に出す
        try WinGetPos(&wx, &wy, &ww, &wh, "A")
        catch {
            wx := 0, wy := 0, ww := A_ScreenWidth, wh := A_ScreenHeight
        }
        refX := wx + ww // 2, refY := wy + wh // 2
        x := refX - POPUP_W // 2, y := refY - POPUP_H // 2
    }
    ClampToMonitor(refX, refY, &x, &y)
}

ClampToMonitor(refX, refY, &x, &y) {
    loop MonitorGetCount() {
        MonitorGetWorkArea(A_Index, &l, &t, &r, &b)
        if refX >= l && refX < r && refY >= t && refY < b {
            x := Max(l, Min(x, r - POPUP_W))
            y := Max(t, Min(y, b - POPUP_H))
            return
        }
    }
}

; Win32 標準の system caret → UI Automation → MSAA の順に試す。
; Chrome/Electron/Windows Terminal は system caret を持たないので後ろ2つが要る。
; Windows Terminal で MSAA の OBJID_CARET を呼ぶとプロセスが落ちたので、MSAA は最後に回す
CaretRect(&x, &y, &w, &h) {
    return CaretFromThread(&x, &y, &w, &h)
        || CaretFromUia(&x, &y, &w, &h)
        || CaretFromAcc(&x, &y, &w, &h)
}

CaretFromThread(&x, &y, &w, &h) {
    gti := GuiThreadInfo()
    if !gti
        return false
    hwnd := NumGet(gti, 8 + 5 * A_PtrSize, "ptr")
    if !hwnd
        return false
    rc := 8 + 6 * A_PtrSize
    pt := Buffer(8)
    NumPut("int", NumGet(gti, rc, "int"), "int", NumGet(gti, rc + 4, "int"), pt)
    DllCall("ClientToScreen", "ptr", hwnd, "ptr", pt)
    x := NumGet(pt, 0, "int"), y := NumGet(pt, 4, "int")
    w := NumGet(gti, rc + 8, "int") - NumGet(gti, rc, "int")
    h := NumGet(gti, rc + 12, "int") - NumGet(gti, rc + 4, "int")
    ; Chromium 系は 0x0 のダミーキャレットを置くことがあり、これを信じると後段に進めない
    return w || h
}

CaretFromAcc(&x, &y, &w, &h) {
    static IID_IAccessible := Guid("{618736E0-3C3D-11CF-810C-00AA00389B71}")
    hwnd := FocusedHwnd()
    if !hwnd || A_PtrSize != 8
        return false
    ; OBJID_CARET = -8
    if DllCall("oleacc\AccessibleObjectFromWindow", "ptr", hwnd, "uint", 0xFFFFFFF8,
            "ptr", IID_IAccessible, "ptr*", &pacc := 0) || !pacc
        return false
    acc := ComValue(13, pacc)
    ; IDispatch 経由 (acc.accLocation) では Invalid memory read/write でプロセスが落ちたので、vtable を直接呼ぶ。
    ; varChild は VARIANT の値渡しだが、x64 では 8 バイトを超える引数はポインタで渡る
    child := Buffer(24, 0)
    NumPut("ushort", 3, child)  ; VT_I4, CHILDID_SELF = 0
    try ComCall(22, acc, "int*", &x := 0, "int*", &y := 0, "int*", &w := 0, "int*", &h := 0,
        "ptr", child)  ; accLocation
    catch
        return false
    return x || y || w || h
}

CaretFromUia(&x, &y, &w, &h) {
    static uia := ""
    try {
        if !uia
            uia := ComObject("{E22AD333-B25F-460C-83D0-0581107395C9}", "{30CBE57D-D9D0-452A-AB13-7AC5AC4825EE}")
        ComCall(8, uia, "ptr*", &pel := 0)  ; GetFocusedElement
        if !pel
            return false
        el := ComValue(13, pel)
        range := UiaCaretRange(el)
        if !range
            return false
        if RangeRect(range, &x, &y, &w, &h)
            return true
        ; 幅ゼロの範囲は矩形を返さない実装があるので、1文字に広げて測る
        ComCall(6, range, "int", 0)  ; ExpandToEnclosingUnit(TextUnit_Character)
        return RangeRect(range, &x, &y, &w, &h)
    } catch
        return false
}

UiaCaretRange(el) {
    ComCall(16, el, "int", 10024, "ptr*", &p := 0)  ; GetCurrentPattern(UIA_TextPattern2Id)
    if p {
        tp2 := ComObjQuery(ComValue(13, p), "{506A921A-FCC9-409F-B23B-37EB74106872}")
        ComCall(10, tp2, "int*", &active := 0, "ptr*", &pr := 0)  ; GetCaretRange
        if pr
            return ComValue(13, pr)
    }
    ComCall(16, el, "int", 10014, "ptr*", &p := 0)  ; GetCurrentPattern(UIA_TextPatternId)
    if !p
        return ""
    tp := ComObjQuery(ComValue(13, p), "{32EBA289-3583-42C9-9C59-3B6D9A1E9B6A}")
    ComCall(5, tp, "ptr*", &parr := 0)  ; GetSelection
    if !parr
        return ""
    arr := ComValue(13, parr)
    ComCall(3, arr, "int*", &n := 0)  ; get_Length
    if n < 1
        return ""
    ComCall(4, arr, "int", 0, "ptr*", &pr := 0)  ; GetElement
    return pr ? ComValue(13, pr) : ""
}

RangeRect(range, &x, &y, &w, &h) {
    ComCall(10, range, "ptr*", &psa := 0)  ; GetBoundingRectangles
    if !psa
        return false
    rects := ComValue(0x2005, psa)  ; SAFEARRAY(double): left, top, width, height, ...
    if rects.MaxIndex() < 3
        return false
    x := Integer(rects[0]), y := Integer(rects[1])
    w := Integer(rects[2]), h := Integer(rects[3])
    return true
}

Guid(s) {
    b := Buffer(16)
    DllCall("ole32\CLSIDFromString", "wstr", s, "ptr", b, "hresult")
    return b
}
