; Compile with ISCC /DReleaseDir=... /DOutputDir=... /DBuildNumber=... SpokenLog.iss
#ifndef ReleaseDir
  #error ReleaseDir is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef BuildNumber
  #error BuildNumber is required
#endif
[Setup]
AppId=io.github.blueb.spokenlog
AppName=SpokenLog
AppVersion=0.1.0
AppVerName=SpokenLog 0.1.0 (build {#BuildNumber})
VersionInfoVersion=0.1.0.{#BuildNumber}
DefaultDirName={localappdata}\Programs\SpokenLog
DefaultGroupName=SpokenLog
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=SpokenLog-Windows-x64-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
UninstallDisplayIcon={app}\SpokenLog.exe
[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\SpokenLog"; Filename: "{app}\SpokenLog.exe"
Name: "{group}\Uninstall SpokenLog"; Filename: "{uninstallexe}"
[Code]
function InitializeUninstall(): Boolean;
var
  Code: Integer;
begin
  Result := True;
  { Silent removal never deletes user data. }
  if UninstallSilent then exit;
  if not FileExists(ExpandConstant('{app}\SpokenLog.exe')) then exit;
  Result := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
    '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\ManageData.ps1') + '"',
    ExpandConstant('{app}'), SW_SHOWNORMAL, ewWaitUntilTerminated, Code);
  Result := Result and (Code = 0);
  if not Result then
    MsgBox('Uninstall cancelled. Close SpokenLog and try again. No automatic data deletion was performed.', mbInformation, MB_OK);
end;
