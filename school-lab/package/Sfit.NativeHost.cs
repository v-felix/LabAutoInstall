// SchoolLab native-messaging bridge. No arbitrary command execution or network access.
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
using System.Web.Script.Serialization;

public static class SfitNativeHost {
    static JavaScriptSerializer json = new JavaScriptSerializer();
    static string Str(IDictionary<string, object> data, string key) {
        object value; return data.TryGetValue(key, out value) ? Convert.ToString(value) : "";
    }
    static byte[] ReadExactly(Stream input, int length) {
        byte[] bytes = new byte[length]; int count = 0;
        while (count < length) { int n = input.Read(bytes, count, length - count); if (n == 0) throw new EndOfStreamException(); count += n; }
        return bytes;
    }
    // The explicit output root makes the production validation/writer testable
    // without modifying the developer's real Chrome / LocalAppData state.
    public static void SaveReport(string payload, string planJson, string origin, string root, string sid) {
            var plan = json.Deserialize<Dictionary<string, object>>(planJson);
            if (origin != "chrome-extension://" + Str(plan,"extensionId") + "/") throw new Exception("Unexpected caller origin");
            var report = json.Deserialize<Dictionary<string,object>>(payload);
            foreach (string field in new string[]{"token","packageId","configSha256","version"}) {
                if (String.IsNullOrEmpty(Str(plan,field)) || Str(report,field) != Str(plan,field)) throw new Exception("Unexpected " + field);
            }
            string phase = Str(report,"phase");
            if (Array.IndexOf(new string[]{"WAITING","ACTIVE","ENDED","DISABLED","INVALID_CONFIG","ERROR"},phase) < 0) throw new Exception("Invalid phase");
            report["receivedAtUtc"] = DateTime.UtcNow.ToString("o");
            report["userSid"] = sid;
            Directory.CreateDirectory(root);
            string path = Path.Combine(root,"heartbeat.json"), temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            File.WriteAllText(temporary,json.Serialize(report),new UTF8Encoding(false));
            // Atomic replace, serialized across short-lived native hosts in this SID.
            using (var mutex = new System.Threading.Mutex(false,"Local\\SchoolLab-Sfit-Report-" + report["userSid"])) {
                bool held = false;
                try {
                    try { held = mutex.WaitOne(5000); } catch (System.Threading.AbandonedMutexException) { held = true; }
                    if (!held) throw new Exception("Report lock timeout");
                    if (File.Exists(path)) File.Replace(temporary,path,null); else File.Move(temporary,path);
                } finally { if (held) mutex.ReleaseMutex(); if (File.Exists(temporary)) File.Delete(temporary); }
            }
    }
    public static int Main(string[] args) {
        Stream output = Console.OpenStandardOutput();
        object answer;
        try {
            string directory = AppDomain.CurrentDomain.BaseDirectory;
            string plan = File.ReadAllText(Path.Combine(directory,"native-plan.json"));
            var input = Console.OpenStandardInput();
            int length = BitConverter.ToInt32(ReadExactly(input,4),0);
            if (length < 2 || length > 65536) throw new Exception("Invalid native message length");
            string inputPayload = Encoding.UTF8.GetString(ReadExactly(input,length));
            string root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"SchoolLab","Chrome");
            SaveReport(inputPayload,plan,args.Length > 0 ? args[0] : "",root,System.Security.Principal.WindowsIdentity.GetCurrent().User.Value);
            answer = new {ok=true};
        } catch (Exception e) { answer = new {ok=false,error=e.Message}; }
        byte[] payload = Encoding.UTF8.GetBytes(json.Serialize(answer));
        byte[] prefix = BitConverter.GetBytes(payload.Length);
        output.Write(prefix,0,4); output.Write(payload,0,payload.Length); output.Flush();
        return 0;
    }
}
