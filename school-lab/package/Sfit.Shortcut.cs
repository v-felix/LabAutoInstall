// Unicode-safe .lnk persistence. WScript.Shell can silently fail to load
// Vietnamese filenames on Windows installations using an ANSI code page.
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public sealed class SfitShortcutData {
    public string TargetPath;
    public string Arguments;
}

public static class SfitShortcutFile {
    [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
    class ShellLink {}
    [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    interface IShellLinkW {
        void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path,int count,IntPtr findData,uint flags);
        void GetIDList(out IntPtr list);
        void SetIDList(IntPtr list);
        void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text,int count);
        void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text,int count);
        void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder text,int count);
        void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string text);
        void GetHotkey(out short key);
        void SetHotkey(short key);
        void GetShowCmd(out int command);
        void SetShowCmd(int command);
        void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder path,int count,out int index);
        void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string path,int index);
        void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path,uint reserved);
        void Resolve(IntPtr owner,uint flags);
        void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
    }
    public static SfitShortcutData Read(string path) {
        object value = new ShellLink();
        try {
            ((IPersistFile)value).Load(path,0);
            var link = (IShellLinkW)value;
            var target = new StringBuilder(32768); var arguments = new StringBuilder(32768);
            link.GetPath(target,target.Capacity,IntPtr.Zero,4);
            link.GetArguments(arguments,arguments.Capacity);
            return new SfitShortcutData { TargetPath=target.ToString(), Arguments=arguments.ToString() };
        } finally { Marshal.FinalReleaseComObject(value); }
    }
    public static void Write(string path,string target,string arguments,string directory,string description) {
        object value = new ShellLink();
        try {
            var link = (IShellLinkW)value;
            link.SetPath(target); link.SetArguments(arguments); link.SetWorkingDirectory(directory);
            link.SetDescription(description); link.SetIconLocation(target,0); link.SetShowCmd(1);
            ((IPersistFile)value).Save(path,true);
        } finally { Marshal.FinalReleaseComObject(value); }
    }
}
