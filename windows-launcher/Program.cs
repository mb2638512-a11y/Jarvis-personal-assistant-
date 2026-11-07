using System.Diagnostics;
using System.Text;
using System.Windows.Forms;

internal static class Program
{
    [STAThread]
    private static int Main()
    {
        var installRoot = AppContext.BaseDirectory;
        var script = Path.Combine(installRoot, "Start-Jarvis.ps1");
        var logDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Jarvis", "logs");
        Directory.CreateDirectory(logDirectory);
        var logPath = Path.Combine(logDirectory, "launcher.log");

        try
        {
            if (!File.Exists(script))
                throw new FileNotFoundException("Jarvis startup component is missing. Run the installer again.", script);

            var powershell = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.System),
                "WindowsPowerShell", "v1.0", "powershell.exe");
            if (!File.Exists(powershell))
                powershell = "powershell.exe";

            var start = new ProcessStartInfo
            {
                FileName = powershell,
                Arguments = "-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script + "\"",
                WorkingDirectory = installRoot,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using var process = new Process { StartInfo = start };
            var logLock = new object();
            using var log = new StreamWriter(logPath, append: true, Encoding.UTF8) { AutoFlush = true };
            log.WriteLine($"[{DateTimeOffset.Now:O}] Starting Jarvis from {installRoot}");

            process.OutputDataReceived += (_, e) =>
            {
                if (e.Data is null) return;
                lock (logLock) log.WriteLine(e.Data);
            };
            process.ErrorDataReceived += (_, e) =>
            {
                if (e.Data is null) return;
                lock (logLock) log.WriteLine("ERROR: " + e.Data);
            };

            if (!process.Start())
                throw new InvalidOperationException("Windows could not start the Jarvis background services.");

            process.BeginOutputReadLine();
            process.BeginErrorReadLine();
            process.WaitForExit();
            process.WaitForExit();

            if (process.ExitCode != 0)
                throw new InvalidOperationException(
                    $"Jarvis startup failed (exit code {process.ExitCode}). Open the diagnostic log for details.");

            return 0;
        }
        catch (Exception ex)
        {
            try { File.AppendAllText(logPath, $"[{DateTimeOffset.Now:O}] FATAL: {ex}{Environment.NewLine}"); }
            catch { /* Keep the user-facing error available even if the log cannot be written. */ }

            MessageBox.Show(
                ex.Message + Environment.NewLine + Environment.NewLine +
                "Diagnostic log: " + logPath,
                "Jarvis could not start",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return 1;
        }
    }
}
