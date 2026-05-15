Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
ps1Path = fso.BuildPath(scriptDir, "install-task.ps1")

Set shell = CreateObject("Shell.Application")
shell.ShellExecute "powershell.exe", _
    "-NoProfile -ExecutionPolicy Bypass -File """ & ps1Path & """ -Uninstall", _
    "", "runas", 1
