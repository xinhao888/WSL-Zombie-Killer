' WSL Zombie Killer - One-Click Uninstall (auto-elevates to admin)
CreateObject("Shell.Application").ShellExecute CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\uninstall.bat", "", "", "runas", 5
