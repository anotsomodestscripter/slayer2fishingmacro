#Requires AutoHotkey v2.0
#SingleInstance Force

; ==============================================================================
; ROBLOX FISHING MACRO
; ==============================================================================


; ==============================================================================
; ADMIN
; ==============================================================================

if !A_IsAdmin
{
    try
    {
        Run('*RunAs "' A_ScriptFullPath '"')
    }
    ExitApp()
}


; ==============================================================================
; COORDINATE MODES
; ==============================================================================

CoordMode("Pixel", "Window")
CoordMode("Mouse", "Window")


; ==============================================================================
; GLOBAL STATE
; ==============================================================================

global isRunning := false
global isCalibrated := false
global colorsDetected := false

global barLeft := 0
global barTop := 0
global barRight := 0
global barBottom := 0

global barWidth := 0
global barHeight := 0

global BORDER_INSET := 5 

; ==============================================================================
; SMOOTH TRACKING SETTINGS
; ==============================================================================
; Target Offset: Verhoogd naar 30 voor betere centrering in de groene balk.
global TARGET_OFFSET := 30 

; Deadzone: Vergroot naar 20 zodat hij minder agressief corrigeert (minder wiebel).
global DEADZONE := 20 


; ==============================================================================
; AUTO-DETECTED COLORS
; ==============================================================================

global COLOR_WHITE_CUBE := 0xFFFFFF
global COLOR_QUEUE_MIN := 0x00FF00
global COLOR_QUEUE_MAX := 0xFFFF00


; ==============================================================================
; TIMING
; ==============================================================================

global HOOK_DETECTION_DELAY := 1500
global HOOK_CONFIRMATIONS_REQUIRED := 4
global HOOK_TIMEOUT := 15000
global TRACKING_TIMEOUT := 15000
global RECAST_DELAY := 1000


; ==============================================================================
; GUI VARIABLES
; ==============================================================================

global controlsGui := 0
global diagnosticGui := 0
global diagnosticText := 0


; ==============================================================================
; STARTUP CONTROLS LEGEND
; ==============================================================================

ShowControlsLegend()
{
    global controlsGui
    controlsGui := Gui("+AlwaysOnTop", "Roblox Fishing Macro")
    controlsGui.BackColor := "202020"
    controlsGui.SetFont("s10", "Segoe UI")
    controlsGui.AddText("x15 y15 w350 cFFFFFF", "ROBLOX FISHING MACRO")
    controlsGui.SetFont("s9", "Segoe UI")
    controlsGui.AddText("x15 y50 w350 cDDDDDD", 
        "[    Start / Screen Calibration`n"
      . "F8    Auto Color Detection`n"
      . "]    Stop / Kill Switch`n`n"
      . "The mouse is NEVER moved by the script.`n"
      . "Clicks use your current cursor position."
    )
    controlsGui.AddText("x15 y170 w350 cAAAAAA", "Bar calibration uses 4 corners.`nColors auto-detected from bar area.")
    
    controlsGui.Show("x20 y20 w380 h225 NoActivate") 
    SetTimer(() => CloseControlsLegend(), -8000)
}

CloseControlsLegend()
{
    global controlsGui
    if IsObject(controlsGui)
    {
        controlsGui.Destroy()
        controlsGui := 0
    }
}
ShowControlsLegend()


; ==============================================================================
; COLOR HELPERS
; ==============================================================================

RGB(hex)
{
    return ((hex & 0xFF) << 16) | (hex & 0xFF00) | ((hex >> 16) & 0xFF)
}

ColorToHex(color)
{
    return Format("0x{:06X}", color)
}


; ==============================================================================
; PIXEL SEARCH FUNCTIONS (BOTTOM TO TOP)
; ==============================================================================

AutoDetectWhiteCube()
{
    global barLeft, barTop, barRight, barBottom
    global COLOR_WHITE_CUBE

    if PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0xFFFFFF, 40)
    {
        COLOR_WHITE_CUBE := PixelGetColor(foundX, foundY, "RGB")
        return true
    }
    return false
}

AutoDetectQueue()
{
    global barLeft, barTop, barRight, barBottom
    global COLOR_QUEUE_MIN, COLOR_QUEUE_MAX

    if PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0x5EFF00, 60)
        || PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0x00FF00, 60)
    {
        COLOR_QUEUE_MIN := 0x00FF00
        COLOR_QUEUE_MAX := 0xFFFF00
        return true
    }
    if PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0xFFE600, 60)
        || PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0xFFFF00, 60)
    {
        COLOR_QUEUE_MIN := 0x00FF00
        COLOR_QUEUE_MAX := 0xFFFF00
        return true
    }
    return false
}

FindWhiteCube()
{
    global barLeft, barTop, barRight, barBottom
    global COLOR_WHITE_CUBE

    whiteTolerance := 45
    if PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, COLOR_WHITE_CUBE, whiteTolerance)
    {
        return { found: true, y: foundY, x: foundX }
    }
    if PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0xFFFFFF, 30)
    {
        return { found: true, y: foundY, x: foundX }
    }
    return { found: false, y: 0, x: 0 }
}

FindQueue()
{
    global barLeft, barTop, barRight, barBottom

    queueTolerance := 50
    if PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0x5EFF00, queueTolerance)
        || PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0x00FF00, queueTolerance)
    {
        return { found: true, y: foundY, x: foundX, type: "GREEN" }
    }
    if PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0xFFE600, queueTolerance)
        || PixelSearch(&foundX, &foundY, barLeft, barBottom, barRight, barTop, 0xFFFF00, queueTolerance)
    {
        return { found: true, y: foundY, x: foundX, type: "YELLOW" }
    }
    return { found: false, y: 0, x: 0, type: "" }
}


; ==============================================================================
; AUTO COLOR DETECTION SETUP
; ==============================================================================

StartAutoColorDetection()
{
    global isRunning, colorsDetected, barLeft, barTop, barRight, barBottom
    global COLOR_WHITE_CUBE, COLOR_QUEUE_MIN, COLOR_QUEUE_MAX

    if isRunning
    {
        ToolTip("Cannot detect colors while the macro is running.`n`nPress ] to stop first.")
        SetTimer(() => ToolTip(), -2500)
        return
    }
    if barLeft == 0 || barTop == 0 || barRight == 0 || barBottom == 0
    {
        ToolTip("You must calibrate the bar FIRST.`n`nPress [ to start calibration.")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    ToolTip("AUTO COLOR DETECTION - STEP 1`n`nScanning for WHITE CUBE...")
    Sleep(500)
    if !AutoDetectWhiteCube()
    {
        ToolTip("FAILED TO DETECT WHITE CUBE")
        SetTimer(() => ToolTip(), -3000)
        return
    }
    SoundBeep(700, 150)

    ToolTip("WHITE CUBE DETECTED!`n`nScanning for QUEUE...")
    Sleep(500)
    if !AutoDetectQueue()
    {
        ToolTip("FAILED TO DETECT QUEUE")
        SetTimer(() => ToolTip(), -3000)
        return
    }
    
    colorsDetected := true
    SoundBeep(1000, 300)
    ToolTip("COLOR DETECTION COMPLETE!`nReady to start fishing!")
    SetTimer(() => ToolTip(), -5000)
}


; ==============================================================================
; DIAGNOSTICS & MOUSE INPUT
; ==============================================================================

CreateDiagnosticWindow()
{
    global diagnosticGui, diagnosticText
    diagnosticGui := Gui("+AlwaysOnTop", "Roblox Fishing Diagnostic")
    diagnosticGui.BackColor := "202020"
    diagnosticText := diagnosticGui.AddText("x15 y15 w430 h320 cFFFFFF", "Waiting for macro...")
    
    diagnosticGui.Show("x20 y260 w460 h350 NoActivate")
}

UpdateDiagnostic(message)
{
    global diagnosticText
    if IsObject(diagnosticText)
        diagnosticText.Value := message
}

CloseDiagnosticWindow()
{
    global diagnosticGui
    if IsObject(diagnosticGui)
    {
        diagnosticGui.Destroy()
        diagnosticGui := 0
    }
}

RobloxClickDown()
{
    Click("Down")
}

RobloxClickUp()
{
    Click("Up")
}

RobloxTap()
{
    Click("Down")
    Sleep(60)
    Click("Up")
}


; ==============================================================================
; HOTKEYS
; ==============================================================================

*]::StopMacro("Macro stopped by user.")

#HotIf WinActive("ahk_exe RobloxPlayerBeta.exe")
F8::StartAutoColorDetection()

*[::
{
    global isRunning, isCalibrated
    if isRunning
        return
    if !isCalibrated
        StartCalibration()
    else
        StartMacro()
}
#HotIf


; ==============================================================================
; SCREEN CALIBRATION
; ==============================================================================

StartCalibration()
{
    global barLeft, barTop, barRight, barBottom, barWidth, barHeight
    global isCalibrated, BORDER_INSET

    ToolTip("BAR CALIBRATION - STEP 1`n`nTop-Left corner. Press SPACE to save.")
    KeyWait("Space", "D")
    KeyWait("Space", "U")
    MouseGetPos(&barLeft, &barTop)
    SoundBeep(750, 150)

    ToolTip("BAR CALIBRATION - STEP 2`n`nBottom-Right corner. Press SPACE to save.")
    KeyWait("Space", "D")
    KeyWait("Space", "U")
    MouseGetPos(&barRight, &barBottom)
    
    barLeft := barLeft + BORDER_INSET
    barTop := barTop + BORDER_INSET
    barRight := barRight - BORDER_INSET
    barBottom := barBottom - BORDER_INSET

    barWidth := barRight - barLeft
    barHeight := barBottom - barTop
    isCalibrated := true
    SoundBeep(1000, 300)
    ToolTip("BAR CALIBRATION COMPLETE!`n`nPress F8 for colors, then [ to start.")
    SetTimer(() => ToolTip(), -3000)
}


; ==============================================================================
; MAIN AUTOMATION
; ==============================================================================

StartMacro()
{
    global isRunning, colorsDetected
    global barLeft, barTop, barRight, barBottom
    global HOOK_DETECTION_DELAY, HOOK_CONFIRMATIONS_REQUIRED, HOOK_TIMEOUT
    global TRACKING_TIMEOUT, RECAST_DELAY
    global TARGET_OFFSET, DEADZONE

    if !colorsDetected
    {
        ToolTip("Colors not detected! Press F8 first.")
        SetTimer(() => ToolTip(), -2500)
        return
    }

    isRunning := true
    CreateDiagnosticWindow()
    
    UpdateDiagnostic(
        "MACRO STARTED`n"
      . "--------------------------------`n"
      . "Connecting to Roblox..."
    )

    if WinExist("ahk_exe RobloxPlayerBeta.exe")
    {
        WinActivate("ahk_exe RobloxPlayerBeta.exe")
    }
    
    Sleep(1000)

    while isRunning
    {
        if !WinActive("ahk_exe RobloxPlayerBeta.exe")
        {
            UpdateDiagnostic(
                "PAUSED`n"
              . "--------------------------------`n"
              . "Roblox is not the active window.`n"
              . "Click back into the game to resume!"
            )
            Sleep(500)
            continue
        }

        UpdateDiagnostic(
            "PHASE 1 - CASTING`n"
          . "--------------------------------`n"
          . "Throwing the line..."
        )
        
        RobloxTap()
        delayStart := A_TickCount

        while isRunning
        {
            elapsed := A_TickCount - delayStart
            if (elapsed >= HOOK_DETECTION_DELAY)
                break
                
            UpdateDiagnostic(
                "PHASE 1 - WAITING`n"
              . "--------------------------------`n"
              . "Cast complete.`n"
              . "Waiting: " . Round((HOOK_DETECTION_DELAY - elapsed) / 1000, 1) . " sec"
            )
            Sleep(50)
        }
        if !isRunning
            break

        hookDetected := false
        hookStartTime := A_TickCount
        consecutiveConfirmations := 0

        while isRunning && !hookDetected
        {
            UpdateDiagnostic(
                "PHASE 2 - WAITING FOR BITE`n"
              . "--------------------------------`n"
              . "Searching for white cube...`n"
              . "Confirmations: " . consecutiveConfirmations . " / " . HOOK_CONFIRMATIONS_REQUIRED
            )
            
            white := FindWhiteCube()
            if white.found
            {
                consecutiveConfirmations++
                if consecutiveConfirmations >= HOOK_CONFIRMATIONS_REQUIRED
                {
                    hookDetected := true
                    Sleep(150)
                    break
                }
            }
            else
            {
                consecutiveConfirmations := 0
            }

            if (A_TickCount - hookStartTime >= HOOK_TIMEOUT)
            {
                Sleep(RECAST_DELAY)
                break
            }
            Sleep(30)
        }

        if !hookDetected
            continue

        isMouseHeld := false
        lastUsefulDetection := A_TickCount

        while isRunning
        {
            white := FindWhiteCube()
            queue := FindQueue()
            
            whiteY := white.found ? white.y : 0
            queueY := queue.found ? queue.y : 0

            if queueY != 0 || whiteY != 0
                lastUsefulDetection := A_TickCount

            statusText := "PHASE 3 - TRACKING`n--------------------------------`n"

            if queueY != 0 && whiteY != 0
            {
                targetY := queueY - TARGET_OFFSET 

                if whiteY > (targetY + DEADZONE) 
                {
                    statusText .= "ACTION: HOLD (Going UP)`n"
                    if !isMouseHeld
                    {
                        RobloxClickDown()
                        isMouseHeld := true
                    }
                }
                else if whiteY < (targetY - DEADZONE) 
                {
                    statusText .= "ACTION: RELEASE (Going DOWN)`n"
                    if isMouseHeld
                    {
                        RobloxClickUp()
                        isMouseHeld := false
                    }
                }
                else
                {
                    statusText .= "ACTION: HOVER (In Deadzone!)`n"
                    if isMouseHeld
                    {
                        RobloxClickUp()
                        isMouseHeld := false
                    }
                }
            }

            UpdateDiagnostic(statusText)

            if queueY == 0 && whiteY == 0
            {
                emptyStart := A_TickCount
                while isRunning
                {
                    checkWhite := FindWhiteCube()
                    if checkWhite.found
                        break

                    if A_TickCount - emptyStart >= 300
                    {
                        if isMouseHeld
                        {
                            RobloxClickUp()
                            isMouseHeld := false
                        }
                        
                        ; ======================================================
                        ; NIEUW: WACHTEN & 4 SECONDEN T INHOUDEN
                        ; ======================================================
                        UpdateDiagnostic(
                            "PHASE 4 - CLAIMING CATCH`n"
                          . "--------------------------------`n"
                          . "Waiting 1 second before claiming..."
                        )

                        Sleep(1000) ; De toegevoegde wacht van 1 seconde

                        UpdateDiagnostic(
                            "PHASE 4 - CLAIMING CATCH`n"
                          . "--------------------------------`n"
                          . "Holding 'T' for 4 seconds..."
                        )

                        if isRunning
                        {
                            Send("{t down}")
                            tWaitStart := A_TickCount
                            
                            ; Check constant of de macro nog runt, voor max 4000ms
                            while isRunning && (A_TickCount - tWaitStart < 4000)
                            {
                                Sleep(50)
                            }
                            
                            Send("{t up}")
                        }

                        UpdateDiagnostic(
                            "CATCH CLAIMED!`n"
                          . "--------------------------------`n"
                          . "Item removed. Preparing next cast..."
                        )
                        
                        Sleep(1500) 
                        ; ======================================================
                        
                        break 2
                    }
                    Sleep(30)
                }
            }

            if (A_TickCount - lastUsefulDetection >= TRACKING_TIMEOUT)
            {
                if isMouseHeld
                {
                    RobloxClickUp()
                    isMouseHeld := false
                }
                Sleep(RECAST_DELAY)
                break
            }

            Sleep(10) 
        }

        if isMouseHeld
            RobloxClickUp()

        Sleep(RECAST_DELAY)
    }

    CloseDiagnosticWindow()
}

StopMacro(reason)
{
    global isRunning
    isRunning := false
    
    if GetKeyState("LButton")
        Click("Up")
        
    if GetKeyState("t")
        Send("{t up}")
        
    CloseDiagnosticWindow()
    ToolTip(reason)
    SetTimer(() => ToolTip(), -2000)
}