' WSL Zombie Killer - One-Click Uninstall (auto-elevates to admin)
CreateObject("WScript.Shell").CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
CreateObject("Shell.Application").ShellExecute "uninstall.bat", "", "", "runas", 5
