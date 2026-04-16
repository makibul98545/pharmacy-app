[Setup]
AppName=MM LifeCare Ledger
AppVersion=1.0
DefaultDirName={pf}\MMLifeCareLedger
DefaultGroupName=MM LifeCare Ledger
OutputDir=output
OutputBaseFilename=MMLifeCare_Setup
Compression=lzma
SolidCompression=yes

[Files]
Source: "dist\app.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "dist\backups\*"; DestDir: "{app}\backups"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\MM LifeCare Ledger"; Filename: "{app}\app.exe"
Name: "{commondesktop}\MM LifeCare Ledger"; Filename: "{app}\app.exe"

[Run]
Filename: "{app}\app.exe"; Description: "Launch App"; Flags: nowait postinstall skipifsilent