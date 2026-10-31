// Read-only Windows identity/session checks. No UI input, token impersonation,
// privilege changes, process launch or writes to another user's profile.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

namespace SchoolLab {
    public sealed class DesktopContextSnapshot {
        public string CurrentSid="", CurrentAccount="", ShellSid="", SessionSid="", InputDesktop="";
        public int SessionId=-1, ShellSessionId=-1, ShellProcessId=0, SessionState=-1;
        public string[] Errors=new string[0];
    }
    public static class DesktopContext {
        [DllImport("user32.dll")] static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h,out uint pid);
        [DllImport("kernel32.dll",SetLastError=true)] static extern IntPtr OpenProcess(uint access,bool inherit,uint pid);
        [DllImport("advapi32.dll",SetLastError=true)] static extern bool OpenProcessToken(IntPtr process,uint access,out IntPtr token);
        [DllImport("advapi32.dll",SetLastError=true)] static extern bool GetTokenInformation(IntPtr token,int type,IntPtr buffer,int size,out int needed);
        [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
        [DllImport("wtsapi32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool WTSQuerySessionInformationW(IntPtr server,int session,int type,out IntPtr buffer,out int bytes);
        [DllImport("wtsapi32.dll")] static extern void WTSFreeMemory(IntPtr buffer);
        [DllImport("user32.dll",SetLastError=true)] static extern IntPtr OpenInputDesktop(uint flags,bool inherit,uint access);
        [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool GetUserObjectInformationW(IntPtr handle,int index,StringBuilder value,int size,out int needed);
        [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr handle);
        static Exception Win32(string api) { return new InvalidOperationException(api+" failed (Win32 "+Marshal.GetLastWin32Error()+")"); }
        static string ProcessSid(uint pid) {
            IntPtr process=OpenProcess(0x1000,false,pid),token=IntPtr.Zero,buffer=IntPtr.Zero;
            if(process==IntPtr.Zero) throw Win32("OpenProcess");
            try {
                if(!OpenProcessToken(process,8,out token)) throw Win32("OpenProcessToken");
                int size;GetTokenInformation(token,1,IntPtr.Zero,0,out size);
                if(size<=0) throw Win32("GetTokenInformation size");
                buffer=Marshal.AllocHGlobal(size);
                if(!GetTokenInformation(token,1,buffer,size,out size)) throw Win32("GetTokenInformation");
                return new SecurityIdentifier(Marshal.ReadIntPtr(buffer)).Value;
            } finally {
                if(buffer!=IntPtr.Zero) Marshal.FreeHGlobal(buffer);
                if(token!=IntPtr.Zero) CloseHandle(token);
                CloseHandle(process);
            }
        }
        static string SessionString(int session,int type) {
            IntPtr buffer;int bytes;
            if(!WTSQuerySessionInformationW(IntPtr.Zero,session,type,out buffer,out bytes)) throw Win32("WTSQuerySessionInformation");
            try {return bytes>2 ? Marshal.PtrToStringUni(buffer) : "";} finally {WTSFreeMemory(buffer);}
        }
        public static DesktopContextSnapshot Capture() {
            var s=new DesktopContextSnapshot();var errors=new List<string>();
            using(var identity=WindowsIdentity.GetCurrent()){s.CurrentSid=identity.User.Value;s.CurrentAccount=identity.Name;}
            using(var process=Process.GetCurrentProcess()){s.SessionId=process.SessionId;}
            try {
                var window=GetShellWindow();uint pid;
                if(window!=IntPtr.Zero && GetWindowThreadProcessId(window,out pid)!=0 && pid!=0) {
                    s.ShellProcessId=(int)pid;
                    using(var shell=Process.GetProcessById((int)pid)){s.ShellSessionId=shell.SessionId;}
                    s.ShellSid=ProcessSid(pid);
                }
            } catch(Exception e){errors.Add("Shell: "+e.Message);}
            try {
                string user=SessionString(s.SessionId,5),domain=SessionString(s.SessionId,7);
                if(!String.IsNullOrEmpty(user)) s.SessionSid=((SecurityIdentifier)new NTAccount(String.IsNullOrEmpty(domain)?user:domain+"\\"+user).Translate(typeof(SecurityIdentifier))).Value;
            } catch(Exception e){errors.Add("Session identity: "+e.Message);}
            try {
                IntPtr buffer;int bytes;
                if(!WTSQuerySessionInformationW(IntPtr.Zero,s.SessionId,8,out buffer,out bytes)) throw Win32("WTS session state");
                try{if(bytes>=4) s.SessionState=Marshal.ReadInt32(buffer);}finally{WTSFreeMemory(buffer);}
            } catch(Exception e){errors.Add("Session state: "+e.Message);}
            try {
                var desktop=OpenInputDesktop(0,false,1);
                if(desktop==IntPtr.Zero) throw Win32("OpenInputDesktop");
                try {
                    var name=new StringBuilder(256);int needed;
                    if(!GetUserObjectInformationW(desktop,2,name,name.Capacity*2,out needed)) throw Win32("GetUserObjectInformation");
                    s.InputDesktop=name.ToString();
                } finally {CloseDesktop(desktop);}
            } catch(Exception e){errors.Add("Input desktop: "+e.Message);}
            s.Errors=errors.ToArray();return s;
        }
    }
}
