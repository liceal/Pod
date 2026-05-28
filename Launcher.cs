using System;
using System.IO;
using System.Diagnostics;
using System.Reflection;
using System.IO.Compression;
using System.Windows.Forms;
using System.Runtime.Versioning;

[assembly: TargetFramework(".NETFramework,Version=v4.5", FrameworkDisplayName = ".NET Framework 4.5")]

public class Program {
    [STAThread]
    public static void Main() {
        try {
            // Path to extract: %LOCALAPPDATA%\Liceal\Pod\App
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string appDir = Path.Combine(localAppData, "Liceal", "Pod", "App");
            string exePath = Path.Combine(appDir, "Pod.exe");
            string versionFile = Path.Combine(appDir, "launcher.version");
            
            // Use the launcher's write time or a hash of the assembly to determine version change
            string launcherPath = Assembly.GetExecutingAssembly().Location;
            string currentMarker = File.Exists(launcherPath) ? File.GetLastWriteTimeUtc(launcherPath).Ticks.ToString() : "1.0.0";

            bool needExtract = true;
            if (Directory.Exists(appDir) && File.Exists(exePath) && File.Exists(versionFile)) {
                try {
                    string existingMarker = File.ReadAllText(versionFile).Trim();
                    if (existingMarker == currentMarker) {
                        needExtract = false;
                    }
                } catch {}
            }

            if (needExtract) {
                // Check if Pod is running (excluding the current launcher process itself)
                bool processesRunning = true;
                while (processesRunning) {
                    Process currentProcess = Process.GetCurrentProcess();
                    Process[] processes = Process.GetProcessesByName("Pod");
                    
                    bool otherInstanceRunning = false;
                    foreach (Process p in processes) {
                        if (p.Id != currentProcess.Id) {
                            otherInstanceRunning = true;
                            break;
                        }
                    }

                    if (otherInstanceRunning) {
                        DialogResult result = MessageBox.Show(
                            "检测到 Pod 正在运行。请先关闭它以完成软件更新。",
                            "提示",
                            MessageBoxButtons.RetryCancel,
                            MessageBoxIcon.Warning
                        );
                        if (result == DialogResult.Cancel) {
                            return; // Exit launcher
                        }
                    } else {
                        processesRunning = false;
                    }
                }

                int retryCount = 5;
                while (retryCount > 0) {
                    try {
                        if (Directory.Exists(appDir)) {
                            Directory.Delete(appDir, true);
                        }
                        Directory.CreateDirectory(appDir);
                        
                        Assembly assembly = Assembly.GetExecutingAssembly();
                        using (Stream stream = assembly.GetManifestResourceStream("Pod.zip")) {
                            if (stream == null) {
                                MessageBox.Show("嵌入式资源丢失，请重新打包。", "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                                return;
                            }
                            using (ZipArchive archive = new ZipArchive(stream)) {
                                archive.ExtractToDirectory(appDir);
                            }
                        }
                        File.WriteAllText(versionFile, currentMarker);
                        break;
                    } catch (Exception ex) {
                        retryCount--;
                        if (retryCount == 0) {
                            MessageBox.Show("解压程序失败，可能是文件被占用，请稍后重试。\n错误信息: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                            return;
                        }
                        System.Threading.Thread.Sleep(500);
                    }
                }
            }

            // Run Pod.exe
            if (File.Exists(exePath)) {
                ProcessStartInfo startInfo = new ProcessStartInfo(exePath);
                startInfo.WorkingDirectory = appDir;
                
                // Forward command line args
                string[] args = Environment.GetCommandLineArgs();
                if (args.Length > 1) {
                    string arguments = "";
                    for (int i = 1; i < args.Length; i++) {
                        arguments += "\"" + args[i].Replace("\"", "\\\"") + "\" ";
                    }
                    startInfo.Arguments = arguments.Trim();
                }
                
                try {
                    Process.Start(startInfo);
                } catch (Exception ex) {
                    MessageBox.Show("启动失败: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
                }
            } else {
                MessageBox.Show("找不到主程序: " + exePath, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        } catch (Exception ex) {
            MessageBox.Show("启动器发生错误: " + ex.Message, "错误", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }
}
