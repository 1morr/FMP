; FMP 的 Windows 安裝檔（ADR 0022 §決定 3）。.github/workflows/app-release.yml
; 以 ISCC 編譯：
;
;   ISCC /DAppVersion=<版本> /DProgramDir=<prod release 的程式目錄> /DOutputDir=<輸出目錄> fmp.iss
;
; 產出 <OutputDir>\fmp-setup.exe，workflow 再改成 release 的檔名。檔案以 UTF-8
; 加 BOM 存，ISCC 才不會把中文註解當成 ANSI。
;
; 設定沿用舊版（根目錄 pubspec.yaml 的 inno_bundle 產生、release.yml 再修補的
; 那一份），因為舊版使用者會拿這個安裝檔覆蓋安裝（ADR 0022 §決定 4）。
; test/release/windows_installer_test.dart 守下面標了「閘門」的幾項：
; - 閘門：AppId 不加大括號。舊版是 `AppId=BAF6…`，解除安裝的登錄機碼是
;   `<AppId>_is1`，多了大括號就成了另一個 App（ADR 0008 §決定 3）。
; - 閘門：PrivilegesRequired=lowest、{autopf}\FMP：與舊版裝在同一處（使用者的
;   Programs 目錄），更新不必系統管理員權限。
; - 閘門：捷徑帶 AppUserModelID com.personal.fmp，與執行中的 App 相同，SMTC 與
;   工作列才認得是同一個 App（app/AGENTS.md § App 身分）。
; - 閘門：[Run] 不帶 skipifsilent。App 內更新以 /SILENT 執行，裝完要自己開回 App。
; - [InstallDelete] 先清空 {app}：舊版留下的 DLL 不混進新版。使用者資料不在
;   程式目錄（app/AGENTS.md § 資料目錄）。VC++ runtime 因此由 workflow 放進
;   程式目錄一起打包（舊版的安裝檔也附了這三個 DLL）。
; - 只有英文介面：Inno Setup 6 的中文翻譯不是官方檔，runner 上沒有；舊版的
;   安裝檔也沒有中文。

#ifndef AppVersion
  #error Pass /DAppVersion=<version>
#endif
#ifndef ProgramDir
  #error Pass /DProgramDir=<program directory>
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
AppId=BAF6CE8D-E1C8-4C29-AE0B-EDE98D5F8FAA
AppName=FMP
AppVersion={#AppVersion}
AppPublisher=FMP
UninstallDisplayName=FMP
UninstallDisplayIcon={app}\fmp.exe
DefaultDirName={autopf}\FMP
DefaultGroupName=FMP
PrivilegesRequired=lowest
OutputDir={#OutputDir}
OutputBaseFilename=fmp-setup
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableDirPage=auto
DisableProgramGroupPage=auto

[InstallDelete]
Type: filesandordirs; Name: "{app}\*"

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#ProgramDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\FMP"; Filename: "{app}\fmp.exe"; AppUserModelID: "com.personal.fmp"
Name: "{autodesktop}\FMP"; Filename: "{app}\fmp.exe"; AppUserModelID: "com.personal.fmp"; Tasks: desktopicon

[Run]
Filename: "{app}\fmp.exe"; Description: "{cm:LaunchProgram,FMP}"; Flags: nowait postinstall
