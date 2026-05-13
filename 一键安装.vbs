' WSL Zombie Killer - One-Click Install (auto-elevates to admin)
CreateObject("WScript.Shell").CurrentDirectory = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)
CreateObject("Shell.Application").ShellExecute "install.bat", "", "", "runas", 5
