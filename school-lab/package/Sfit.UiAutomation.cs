// Used by the DEPLOYED package, never by a background student watchdog.
// Accessible names support English and Vietnamese Chrome/Windows; no screen coordinates.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Automation;
using System.Runtime.InteropServices;
using System.Globalization;
using System.Text;

// Pure decisions are shared with regression tests; these methods never access UI.
public static class SfitChromePage {
    public static string Normalize(string value) {
        var text = new StringBuilder();
        foreach (char c in (value ?? "").Normalize(NormalizationForm.FormD)) {
            if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                text.Append(c == '\u0111' || c == '\u0110' ? 'd' : Char.ToLowerInvariant(c));
        }
        return Regex.Replace(text.ToString().Replace("&", ""), @"\s+", " ").Trim().TrimEnd(':').Trim();
    }
    public static bool IsExtensionsAddress(string address) {
        // Omnibox can omit the trailing slash, but never accept a website or
        // chrome://extensions-internals as the installation page.
        Uri uri;
        return Uri.TryCreate(address, UriKind.Absolute, out uri) &&
            uri.Scheme == "chrome" && uri.Host == "extensions" &&
            (uri.AbsolutePath == "" || uri.AbsolutePath == "/") &&
            uri.UserInfo == "" && uri.Query == "" && uri.Fragment == "";
    }
    public static bool IsExtensionsTab(string name) {
        string n = Normalize(name);
        return n == "extensions" || n == "tien ich" || n == "tien ich mo rong";
    }
    public static bool IsDeveloperLabel(string name) {
        string n = Normalize(name);
        return n == "developer mode" || n == "che do danh cho nha phat trien" ||
            n == "che do nha phat trien" || n == "che do cho nha phat trien";
    }
    public static bool IsLoadLabel(string name) {
        string n = Normalize(name);
        return n == "load unpacked" || n == "tai tien ich da giai nen" || n == "tai tien ich chua dong goi";
    }
    public static bool IsOmniboxLabel(string name) {
        string n = Normalize(name);
        return n == "address and search bar" || n == "address bar" ||
            n == "thanh dia chi va tim kiem" || n == "thanh dia chi va thanh tim kiem" || n == "thanh dia chi";
    }
    public static string Plan(string address, bool hasExtensionsTab, bool hasExtensionsDocument) {
        // An omnibox VALUE is not proof of navigation: UIA SetValue changes
        // that value BEFORE Enter commits or the new document has loaded.
        if (IsExtensionsAddress(address) && hasExtensionsDocument) return "Ready";
        return hasExtensionsTab ? "SelectTab" : "NavigateAddress";
    }
}

public interface ISfitOmnibox {
    bool IsChromeTarget { get; }
    bool IsForeground { get; }
    bool HasFocus { get; }
    bool ModifiersClear { get; }
    string Value { get; }
    void Activate();
    void Focus();
    void SetValue(string value);
    void PressEnter();
}

// Exact production navigation sequence, independently testable without sending
// input to the developer's desktop. It can navigate ONLY this fixed internal URL.
public static class SfitChromeNavigation {
    public const string Target = "chrome://extensions/";
    public static string Navigate(ISfitOmnibox box) {
        if (!box.IsChromeTarget) throw new InvalidOperationException("Navigation target is not a Chrome browser window");
        box.Activate();
        if (!box.IsForeground) return "AwaitForeground";
        if (!box.ModifiersClear) return "AwaitReleasedKeys";
        box.Focus();
        if (!box.IsForeground || !box.HasFocus) return "AwaitOmniboxFocus";
        box.SetValue(Target);
        if (!SfitChromePage.IsExtensionsAddress(box.Value)) throw new InvalidOperationException("Chrome omnibox did not accept the internal URL");
        if (!box.IsForeground || !box.HasFocus) return "AwaitOmniboxFocus";
        if (!box.ModifiersClear) return "AwaitReleasedKeys";
        box.PressEnter();
        // NEVER return Ready just because text was typed or Enter was sent.
        return "NavigationRequested";
    }
}

public static class SfitUi {
    // UIA providers are out-of-process and can stall. Each call has its own
    // bound; a failed operation stops setup rather than blindly clicking again.
    static readonly Queue<Action> work = new Queue<Action>();
    static Exception invokeError;
    static readonly Dictionary<int,DateTime> lastNavigation = new Dictionary<int,DateTime>();
    static readonly Dictionary<int,int> navigationCount = new Dictionary<int,int>();
    static SfitUi() {
        // Keep the apartment alive: UIA elements must not outlive the apartment
        // that created their provider proxies.
        var thread = new Thread(delegate() {
            while (true) {
                Action action;
                lock (work) { while (work.Count == 0) Monitor.Wait(work); action = work.Dequeue(); }
                action();
            }
        });
        thread.IsBackground = true; thread.SetApartmentState(ApartmentState.MTA); thread.Start();
    }
    static T Bounded<T>(Func<T> action, bool diagnostic = false) {
        lock (work) { if (!diagnostic && invokeError != null) throw new InvalidOperationException("Chrome Load unpacked failed", invokeError); }
        T result = default(T); Exception error = null;
        var finished = new ManualResetEvent(false);
        lock (work) {
            work.Enqueue(delegate() { try { result = action(); } catch (Exception e) { error = e; } finally { finished.Set(); } });
            Monitor.Pulse(work);
        }
        if (!finished.WaitOne(8000)) throw new TimeoutException("Chrome accessibility provider did not respond within 8 seconds");
        finished.Dispose();
        if (error != null) throw error;
        return result;
    }
    public static AutomationElement ChromeWindow(int sessionId) { return Bounded(delegate { return RawChromeWindow(sessionId); }); }
    public static string EnsureExtensionsPage(AutomationElement w) { return Bounded(delegate { return RawEnsureExtensionsPage(w); }); }
    public static bool EnableDeveloperMode(AutomationElement w) { return Bounded(delegate { return RawEnableDeveloperMode(w); }); }
    public static bool ClickLoad(AutomationElement w) { return Bounded(delegate { return RawClickLoad(w); }); }
    public static bool SelectFolder(AutomationElement w,string p) { return Bounded(delegate { return RawSelectFolder(w,p); }); }
    public static string Describe(AutomationElement w) { return Bounded(delegate { return RawDescribe(w); },true); }
    public static string WindowTitle(AutomationElement w) { return Bounded(delegate { return w.Current.Name; }); }
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hWnd);
    [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hWnd,int command);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll",SetLastError=true)] static extern uint SendInput(uint count,Input[] inputs,int size);
    [StructLayout(LayoutKind.Sequential)] struct MouseInput { public int x,y; public uint data,flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct KeyboardInput { public ushort key,scan; public uint flags,time; public UIntPtr extra; }
    [StructLayout(LayoutKind.Sequential)] struct HardwareInput { public uint message; public ushort low,high; }
    [StructLayout(LayoutKind.Explicit)] struct InputData {
        [FieldOffset(0)] public MouseInput mouse;
        [FieldOffset(0)] public KeyboardInput keyboard;
        [FieldOffset(0)] public HardwareInput hardware;
    }
    [StructLayout(LayoutKind.Sequential)] struct Input { public uint type; public InputData data; }
    static AutomationElement Find(AutomationElement root, string expression, ControlType type) {
        var items = root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty,type));
        foreach (AutomationElement e in items) {
            try { if (e.Current.IsEnabled && Regex.IsMatch(e.Current.Name ?? "",expression,RegexOptions.IgnoreCase)) return e; }
            catch (ElementNotAvailableException) {}
        }
        return null;
    }
    static AutomationElement RawChromeWindow(int sessionId) {
        var windows = AutomationElement.RootElement.FindAll(TreeScope.Children,Condition.TrueCondition);
        AutomationElement best = null; int bestRank = -1;
        foreach (AutomationElement w in windows) {
            try {
                var p = Process.GetProcessById(w.Current.ProcessId);
                if (!p.ProcessName.Equals("chrome",StringComparison.OrdinalIgnoreCase) || p.SessionId != sessionId ||
                    w.Current.NativeWindowHandle == 0 || !IsWindowVisible(new IntPtr(w.Current.NativeWindowHandle)) ||
                    !(w.Current.ClassName ?? "").StartsWith("Chrome_WidgetWin_",StringComparison.Ordinal)) continue;
                // Startup/update pages from OTHER extensions can take focus.
                // Prefer our actual page across all browser windows, rather
                // than whichever chrome.exe window UIA enumerates first.
                int rank = ActualExtensionsPage(w) ? 100 : ExtensionTab(w) != null ? 50 : Omnibox(w) != null ? 10 : 1;
                if (rank > bestRank) { best = w; bestRank = rank; }
            } catch (ElementNotAvailableException) {} catch (InvalidOperationException) {} catch (ArgumentException) {}
        }
        return best;
    }
    static AutomationElement Omnibox(AutomationElement window) {
        var edits = window.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Edit));
        foreach (AutomationElement edit in edits) {
            if (!edit.Current.IsEnabled || edit.Current.IsOffscreen || !SfitChromePage.IsOmniboxLabel(edit.Current.Name)) continue;
            // A website can name an input "Address and search bar". Only the
            // native browser toolbar is eligible, never an input in a document.
            var parent = TreeWalker.ControlViewWalker.GetParent(edit); bool inDocument = false;
            while (parent != null && !Automation.Compare(parent,window)) {
                if (parent.Current.ControlType == ControlType.Document) { inDocument = true; break; }
                parent = TreeWalker.ControlViewWalker.GetParent(parent);
            }
            if (!inDocument && parent != null) return edit;
        }
        return null;
    }
    static string Address(AutomationElement window) {
        var edit = Omnibox(window);
        object value;
        return edit != null && edit.TryGetCurrentPattern(ValuePattern.Pattern,out value) ? ((ValuePattern)value).Current.Value : "";
    }
    static bool HasExtensionsDocument(AutomationElement window) {
        var documents = window.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Document));
        foreach (AutomationElement document in documents) {
            if (!document.Current.IsOffscreen && SfitChromePage.IsExtensionsTab(document.Current.Name)) return true;
        }
        return false;
    }
    static bool ActualExtensionsPage(AutomationElement window) {
        return SfitChromePage.IsExtensionsAddress(Address(window)) && HasExtensionsDocument(window);
    }
    sealed class NativeOmnibox : ISfitOmnibox {
        readonly AutomationElement window,edit;
        readonly IntPtr handle;
        readonly ValuePattern value;
        public NativeOmnibox(AutomationElement window,AutomationElement edit) {
            this.window = window; this.edit = edit; handle = new IntPtr(window.Current.NativeWindowHandle);
            object pattern;
            if (!edit.TryGetCurrentPattern(ValuePattern.Pattern,out pattern)) throw new Exception("Chrome omnibox exposes no ValuePattern");
            value = (ValuePattern)pattern;
            if (value.Current.IsReadOnly) throw new Exception("Chrome omnibox is read-only");
        }
        public bool IsChromeTarget { get {
            var process = Process.GetProcessById(window.Current.ProcessId);
            return process.ProcessName.Equals("chrome",StringComparison.OrdinalIgnoreCase) &&
                process.SessionId == Process.GetCurrentProcess().SessionId && IsWindowVisible(handle) &&
                (window.Current.ClassName ?? "").StartsWith("Chrome_WidgetWin_",StringComparison.Ordinal);
        } }
        public bool IsForeground { get { return GetForegroundWindow() == handle; } }
        public bool HasFocus { get { return edit.Current.HasKeyboardFocus && Automation.Compare(AutomationElement.FocusedElement,edit); } }
        public bool ModifiersClear { get {
            foreach (int key in new int[]{0x10,0x11,0x12,0x5B,0x5C}) if ((GetAsyncKeyState(key) & 0x8000) != 0) return false;
            return true;
        } }
        public string Value { get { return value.Current.Value; } }
        public void Activate() { if (IsIconic(handle)) ShowWindow(handle,9); SetForegroundWindow(handle); }
        public void Focus() { edit.SetFocus(); }
        public void SetValue(string text) { value.SetValue(text); }
        public void PressEnter() {
            // Recheck immediately before native input; no WScript.SendKeys,
            // clipboard replacement, screen coordinates or arbitrary text.
            if (!IsChromeTarget || !IsForeground || !HasFocus || !ModifiersClear || !SfitChromePage.IsExtensionsAddress(Value))
                throw new Exception("Chrome lost omnibox focus before Enter; no key was sent");
            var down = new Input(); down.type = 1; down.data.keyboard.key = 0x0D;
            var up = down; up.data.keyboard.flags = 2;
            if (SendInput(2,new Input[]{down,up},Marshal.SizeOf(typeof(Input))) != 2)
                throw new Exception("Windows did not accept Chrome navigation input; Win32 error " + Marshal.GetLastWin32Error());
        }
    }
    static AutomationElement ExtensionTab(AutomationElement window) {
        var tabs = window.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.TabItem));
        foreach (AutomationElement tab in tabs) {
            try { if (tab.Current.IsEnabled && SfitChromePage.IsExtensionsTab(tab.Current.Name)) return tab; }
            catch (ElementNotAvailableException) {}
        }
        return null;
    }
    static string RawEnsureExtensionsPage(AutomationElement window) {
        string address = Address(window);
        var tab = ExtensionTab(window);
        string plan = SfitChromePage.Plan(address,tab != null,HasExtensionsDocument(window));
        if (plan == "Ready") return plan;
        if (plan == "SelectTab") {
            object selection;
            if (!tab.TryGetCurrentPattern(SelectionItemPattern.Pattern,out selection))
                throw new Exception("Extensions tab exposes no SelectionItemPattern");
            var item = (SelectionItemPattern)selection;
            if (!item.Current.IsSelected) {
                SetForegroundWindow(new IntPtr(window.Current.NativeWindowHandle));
                item.Select();
                return "SelectTab";
            }
        }
        int handle = window.Current.NativeWindowHandle;
        DateTime previous; int count;
        if (lastNavigation.TryGetValue(handle,out previous) && (DateTime.UtcNow-previous).TotalSeconds < 3) return "LoadingPage";
        navigationCount.TryGetValue(handle,out count);
        if (count >= 3) return "NavigationLimit";
        var edit = Omnibox(window);
        if (edit == null) return "OmniboxUnavailable"; // do not click first-run / authentication prompts
        string outcome = SfitChromeNavigation.Navigate(new NativeOmnibox(window,edit));
        if (outcome == "NavigationRequested") { lastNavigation[handle] = DateTime.UtcNow; navigationCount[handle] = count+1; }
        return outcome;
    }
    static bool RawEnableDeveloperMode(AutomationElement window) {
        if (!ActualExtensionsPage(window)) return false;
        SetForegroundWindow(new IntPtr(window.Current.NativeWindowHandle));
        // Load unpacked is stronger evidence of enabled mode than a toggle's
        // role, which differs between Chromium accessibility providers.
        if (LoadButton(window) != null) return true;
        var items = window.FindAll(TreeScope.Descendants,Condition.TrueCondition);
        foreach (AutomationElement e in items) {
            if (!SfitChromePage.IsDeveloperLabel(e.Current.Name) && e.Current.AutomationId != "devMode") continue;
            if (!e.Current.IsEnabled) throw new Exception("Chrome Developer mode is disabled; check browser policy.");
            if (e.Current.IsOffscreen) continue;
            object pattern;
            // A separate text label may have the same name. Keep searching
            // for the actual switch instead of failing on its label.
            if (!e.TryGetCurrentPattern(TogglePattern.Pattern,out pattern)) continue;
            var toggle = (TogglePattern)pattern;
            if (toggle.Current.ToggleState == ToggleState.Off) toggle.Toggle();
            return false; // advance only after Load unpacked becomes visible
        }
        return false;
    }
    static AutomationElement LoadButton(AutomationElement window) {
        var buttons = window.FindAll(TreeScope.Descendants,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button));
        foreach (AutomationElement e in buttons)
            if (e.Current.IsEnabled && !e.Current.IsOffscreen && SfitChromePage.IsLoadLabel(e.Current.Name)) return e;
        return null;
    }
    static bool RawClickLoad(AutomationElement window) {
        if (!ActualExtensionsPage(window)) return false;
        var button = LoadButton(window);
        if (button == null) return false;
        int handle = window.Current.NativeWindowHandle;
        // Invoke can block until the native folder dialog CLOSES. Do not
        // occupy the single UIA actor needed to find/fill that same dialog.
        // Reacquire the element inside its own MTA; never share provider
        // proxies from an apartment that has already exited.
        var invoker = new Thread(delegate() {
            try {
                var w = AutomationElement.FromHandle(new IntPtr(handle));
                if (!ActualExtensionsPage(w)) throw new Exception("Chrome page changed before Load unpacked");
                var b = LoadButton(w); object pattern;
                if (b == null || !b.TryGetCurrentPattern(InvokePattern.Pattern,out pattern)) throw new Exception("Load unpacked exposes no InvokePattern");
                ((InvokePattern)pattern).Invoke();
            } catch (Exception e) { lock (work) { invokeError = e; } }
        });
        invoker.IsBackground = true; invoker.SetApartmentState(ApartmentState.MTA); invoker.Start();
        return true;
    }
    static bool RawSelectFolder(AutomationElement window, string path) {
        var candidates = AutomationElement.RootElement.FindAll(TreeScope.Children,new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Window));
        foreach (AutomationElement dialog in candidates) {
            // Chrome's owned folder dialog must belong to the same browser process.
            if (dialog.Current.ProcessId != window.Current.ProcessId) continue;
            var edit = Find(dialog,"^(Folder:|Thư mục:|Tên thư mục:)$",ControlType.Edit);
            if (edit == null) continue;
            object value; if (!edit.TryGetCurrentPattern(ValuePattern.Pattern,out value)) continue;
            ((ValuePattern)value).SetValue(path);
            var select = Find(dialog,"^(Select Folder|Chọn thư mục|Chọn Thư mục)$",ControlType.Button);
            if (select == null) throw new Exception("Cannot find Select Folder button");
            object invoke; if (!select.TryGetCurrentPattern(InvokePattern.Pattern,out invoke)) throw new Exception("Folder button exposes no InvokePattern");
            ((InvokePattern)invoke).Invoke(); return true;
        }
        return false;
    }
    static string RawDescribe(AutomationElement window) {
        var result = new List<string>();
        result.Add("Window: " + window.Current.Name + " | class=" + window.Current.ClassName + " | PID=" + window.Current.ProcessId);
        result.Add("Page classification: " + (ActualExtensionsPage(window) ? "Verified extensions document" : "Other document / not loaded yet"));
        result.Add("Omnibox points to extensions: " + SfitChromePage.IsExtensionsAddress(Address(window)) + "; extensions document loaded: " + HasExtensionsDocument(window));
        var items = window.FindAll(TreeScope.Descendants,Condition.TrueCondition);
        // Tab names and setup controls first, so toolbar-heavy profiles do
        // not use up the log limit before the relevant diagnostics appear.
        foreach (AutomationElement e in items) {
            if (e.Current.ControlType == ControlType.TabItem || SfitChromePage.IsDeveloperLabel(e.Current.Name) || SfitChromePage.IsLoadLabel(e.Current.Name))
                result.Add("TARGET " + e.Current.ControlType.ProgrammaticName + ": " + e.Current.Name + " | id=" + e.Current.AutomationId + " | enabled=" + e.Current.IsEnabled + " | offscreen=" + e.Current.IsOffscreen);
        }
        foreach (AutomationElement e in items) {
            if (result.Count >= 300) break;
            if (!String.IsNullOrEmpty(e.Current.Name)) result.Add(e.Current.ControlType.ProgrammaticName + ": " + e.Current.Name);
        }
        return String.Join(Environment.NewLine,result.ToArray());
    }
}
