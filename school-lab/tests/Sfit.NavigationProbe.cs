// Fake native boundary for the EXACT production navigation controller.
// No UIA/Win32 calls, processes, keyboard input or browser changes occur here.
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

public sealed class SfitFakeOmnibox : ISfitOmnibox {
    public bool ChromeTarget = true, Foreground, Focused, ClearKeys = true;
    public bool ActivationSucceeds = true, FocusSucceeds = true;
    public bool LoseFocusOnSet, LoseForegroundOnSet, HoldKeysOnSet, RejectText;
    public string Text = "";
    public int Enters, Sets;
    public List<string> Events = new List<string>();
    public bool IsChromeTarget { get { return ChromeTarget; } }
    public bool IsForeground { get { return Foreground; } }
    public bool HasFocus { get { return Focused; } }
    public bool ModifiersClear { get { return ClearKeys; } }
    public string Value { get { return Text; } }
    public void Activate() { Events.Add("Activate"); if (ActivationSucceeds) Foreground = true; }
    public void Focus() { Events.Add("Focus"); if (FocusSucceeds) Focused = true; }
    public void SetValue(string value) {
        Events.Add("Set:"+value); Sets++; Text = RejectText ? "rejected" : value;
        if (LoseFocusOnSet) Focused = false;
        if (LoseForegroundOnSet) Foreground = false;
        if (HoldKeysOnSet) ClearKeys = false;
    }
    public void PressEnter() {
        if (!ChromeTarget || !Foreground || !Focused || !ClearKeys) throw new Exception("Unsafe keyboard boundary crossed");
        Events.Add("Enter"); Enters++;
    }
    public static int NativeInputSize() {
        var type = typeof(SfitUi).GetNestedType("Input",System.Reflection.BindingFlags.NonPublic);
        return Marshal.SizeOf(type);
    }
}
