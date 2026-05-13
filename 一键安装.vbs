' WSL Zombie Killer - One-Click Install (auto-elevates to admin)
CreateObject("Shell.Application").ShellExecute CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & "\install.bat", "", "", "runas", 5
