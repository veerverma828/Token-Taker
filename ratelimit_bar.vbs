scriptPath = CreateObject("WScript.Shell").ExpandEnvironmentStrings("%USERPROFILE%") & "\.claude\ratelimit_bar.ps1"
CreateObject("Wscript.Shell").Run "powershell -sta -windowstyle hidden -ExecutionPolicy Bypass -File """ & scriptPath & """", 0, False
