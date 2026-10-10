unit PasClawConfig;

{ PasClaw IDE 插件的配置。

  A. 插件自身设置（工具链目录）
     保存为 JSON（fcl-json，Lazarus 自带，不依赖 pasclaw 自身的单元），
     默认位置：<pasclaw.exe 目录>\.pasclaw\ide-plugin.json
     （和 pasclaw 自己 2026-10-10 起的数据目录是同一个：exe 旁边的 .pasclaw。
      旧版本放在 %APPDATA%\PasClaw，首次 Load 会把旧文件搬过来。）
     插件的运行时数据（Agent 日志库 agentlog.db 等）与它放在同一个目录。
        pasclawDir  PasClaw 主程序所在目录（pascal 编译器 / pasclaw.exe 都在这）
        lazarusDir  Lazarus 安装目录（lazbuild.exe、lazarus.exe 所在处）
        fpcDir      FPC 安装目录（bin\x86_64-win64\fpc.exe、units\ 所在处）

  B. 代理（agent）设置：providers + systemPrompt
     直接读写 pasclaw 自己的配置文件 <pasclaw.exe 目录>\.pasclaw\config.json：
        providers                 服务商数组（name/kind/api_base/api_key/model）
        agents.defaults.systemPrompt  系统提示词
     只更新上面两处，文件里其余键（default_provider、sandbox、skills …）
     原样保留；文件不存在时新建一个最小配置。

  三个目录各自独立可改；留空表示"未配置 / 关掉"。相对路径按 JSON
  文件所在目录解析，绝对路径原样使用。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Contnrs;

type
  { 一个模型服务商，对应 .pasclaw/config.json 里 providers 数组的一项。 }
  TPasClawProvider = class(TPersistent)
  private
    FName: string;
    FKind: string;
    FApiBase: string;
    FApiKey: string;
    FModel: string;
  public
    procedure Assign(Source: TPersistent); override;
    function Clone: TPasClawProvider;
    property Name: string read FName write FName;
    property Kind: string read FKind write FKind;
    property ApiBase: string read FApiBase write FApiBase;
    property ApiKey: string read FApiKey write FApiKey;
    property Model: string read FModel write FModel;
  end;

  TPasClawIDESettings = class
  private
    FFileName: string;
    FAgentConfigFile: string;
    FPasClawDir: string;
    FLazarusDir: string;
    FFpcDir: string;
    FSystemPrompt: string;
    FProviders: TObjectList;   // owns TPasClawProvider

    procedure Normalize;
    procedure DetectDefaults;
    function  Resolve(const APath: string): string;

    { 旧版本的数据目录（%APPDATA%\PasClaw / ~/.config/PasClaw），
      只在 MigrateLegacyData 里用来找要搬的文件。 }
    class function  LegacyConfigDir: string;
    { 把旧数据目录里的 ide-plugin.json / agentlog.db 搬到新数据目录；
      目标已存在或搬不动就跳过（下次 Load 会再试）。 }
    class procedure MigrateLegacyData(const ANewDir: string);

    procedure LoadAgentConfig;
    function  SaveAgentConfig: Boolean;

    function  GetProvider(Index: Integer): TPasClawProvider;
    function  GetProviderCount: Integer;
  public
    constructor Create;
    destructor  Destroy; override;

    { 读取配置；文件不存在或解析失败时退回"自动探测"并返回 False。
      返回 True 表示确实读到了磁盘上的配置文件（上面 A / B 任一）。 }
    function Load: Boolean;
    { 写回配置文件（A 用 ide-plugin.json，B 用 .pasclaw\config.json），
      全部成功返回 True。 }
    function Save: Boolean;

    { 把某个目录拷进来后自动补全其余未配置的目录：选了 Lazarus 目录
      就能顺带推出 fpc / pasclaw（如果它们还没配置）。 }
    procedure AutoFillFrom(const ASource: string = '');

    function EffectivePasClawDir: string;
    function EffectiveLazarusDir: string;
    function EffectiveFpcDir: string;

    { ---- providers ---- }
    function  AddProvider(const AName: string = ''): TPasClawProvider;
    procedure RemoveProvider(Index: Integer);
    procedure ClearProviders;
    function  IndexOfProvider(const AName: string): Integer;
    function  FindProvider(const AName: string): TPasClawProvider;

    { 插件数据目录：<pasclaw.exe 目录>\.pasclaw —— 与 pasclaw 自己用的数据
      目录相同。配置文件 ide-plugin.json 与日志库 agentlog.db 都放在这里。 }
    class function ConfigDir: string;
    class function DefaultFileName: string;
    { 数据目录下的一个文件；日志库靠它定位，保证"日志和配置同目录" }
    class function DataFile(const AName: string): string;
    { pasclaw.exe 所在目录：当前目录下的 pasclaw.exe，否则 DefaultPasClawDir
      解析出来的 exe 位置（认得 <dir>\pasclaw.exe 和 <dir>\build\pasclaw.exe）。
      数据目录就是它下面的 .pasclaw。 }
    class function PasClawExeDir: string;
    { 操作系统用户主目录（%USERPROFILE%，Unix 为 ~）；数据目录已不在这里，
      见 ConfigDir。 }
    class function HomeDir: string;
    { pasclaw 自己的 config.json 所在目录，与 ConfigDir 是同一个 }
    class function AgentConfigDir: string;
    class function DefaultAgentConfigFileName: string;

    property FileName: string read FFileName write FFileName;
    { pasclaw 自己的 config.json（providers / systemPrompt 写这里） }
    property AgentConfigFile: string read FAgentConfigFile write FAgentConfigFile;

    property PasClawDir: string read FPasClawDir write FPasClawDir;
    property LazarusDir: string read FLazarusDir write FLazarusDir;
    property FpcDir: string read FFpcDir write FFpcDir;

    property SystemPrompt: string read FSystemPrompt write FSystemPrompt;
    property ProviderCount: Integer read GetProviderCount;
    property Providers[Index: Integer]: TPasClawProvider read GetProvider;
  end;

{ 全局配置实例（首次访问时创建并 Load） }
function PasClawSettings: TPasClawIDESettings;
{ 释放全局配置实例，供 finalization 调用 }
procedure FreePasClawSettings;

{ pasclaw.exe 完整路径（优先 <dir>\pasclaw.exe，其次 <dir>\build\pasclaw.exe） }
function FindPasClawExe(const ADir: string): string;
{ 在给定的 PasClaw 目录里找可执行文件（<dir>\pasclaw.exe，
   再试 <dir>\build\pasclaw.exe）。传入的已经是文件名时原样返回。 }
function ResolvePasClawExe(const APath: string): string;

const
  PasClawExeName = 'pasclaw.exe';
  DefaultPasClawDir = 'C:\PasClaw\build';
  DefaultLazarusDir = 'D:\QFLazarus4.8\lazarus';
  DefaultFpcDir = 'D:\QFLazarus4.8\fpc';
  AgentConfigDirName = '.pasclaw';
  AgentConfigName = 'config.json';
  { 插件数据目录（ConfigDir）里并排存放的两个文件 }
  PluginConfigName = 'ide-plugin.json';
  PluginLogName    = 'agentlog.db';

{ pasclaw 自己的 config.json 不存在时写进去的默认模板。
  providers / systemPrompt 会被设置对话框覆盖，其余键（gateway、sandbox、
  skills …）原样保留。这里把上传的 config.json 逐字展开，方便阅读和改动。 }
const
  DefaultAgentConfigJSON: String =
    '{' + #10 +
    '  "default_provider": "deepseek",' + #10 +
    '  "default_model": "deepseek-flash",' + #10 +
    '  "agents": {' + #10 +
    '    "defaults": {' + #10 +
    '      "max_tool_iterations": 200,' + #10 +
    '      "systemPrompt": "你是资深 Free Pascal / Lazarus 开发专家。回答时遵循：1) 显式声明编译模式（{$mode objfpc} 或 {$mode delphi}），并指出两者在过程变量赋值、forward 声明、字符串类型上的关键差异；2) 涉及路径、行结束符、编码时，提供 Windows/Linux/macOS 兼容方案（使用 PathDelim、LineEnding，避免硬编码）；3) 平台特定 API 必须用 {$IFDEF} 隔离，优先使用 FPC 预定义符号（MSWINDOWS/LINUX/DARWIN）；4) 涉及具体 API 用法时，检索知识库中的 FPC及lazarus文档和相关源代码，不凭记忆回答。"' + #10 +
    '    }' + #10 +
    '  },' + #10 +
    '  "gateway": { "log_level": "info", "bind_addr": "127.0.0.1", "port": 8088 },' + #10 +
    '  "diagnostics": {' + #10 +
    '    "otel": {' + #10 +
    '      "enabled": false,' + #10 +
    '      "endpoint": "http://localhost:4318",' + #10 +
    '      "protocol": "http/json",' + #10 +
    '      "serviceName": "pasclaw",' + #10 +
    '      "sampleRate": 1.0,' + #10 +
    '      "traces": true,' + #10 +
    '      "metrics": false,' + #10 +
    '      "logs": false' + #10 +
    '    }' + #10 +
    '  },' + #10 +
    '  "sandbox": {' + #10 +
    '    "restrict_to_workspace": false,' + #10 +
    '    "allow_read_outside_workspace": false,' + #10 +
    '    "workspace": "",' + #10 +
    '    "shell_deny_enabled": true,' + #10 +
    '    "block_private_networks": true,' + #10 +
    '    "allow_read_paths": [],' + #10 +
    '    "allow_write_paths": [],' + #10 +
    '    "custom_shell_deny": []' + #10 +
    '  },' + #10 +
    '  "vault_tools_enabled": true,' + #10 +
    '  "rerank_search_enabled": true,' + #10 +
    '  "rerank_backend": "llm",' + #10 +
    '  "stats_collection_enabled": false,' + #10 +
    '  "checkpoints_enabled": false,' + #10 +
    '  "memory_distill_enabled": true,' + #10 +
    '  "auto_router": {' + #10 +
    '    "enabled": true,' + #10 +
    '    "easy_provider": "",' + #10 +
    '    "easy_model": "",' + #10 +
    '    "easy_max_tokens": 500' + #10 +
    '  },' + #10 +
    '  "self_improving_skills": {' + #10 +
    '    "self_manage": false,' + #10 +
    '    "progressive_disclosure": false,' + #10 +
    '    "auto_approve": false,' + #10 +
    '    "guard_deny": [],' + #10 +
    '    "distiller": {' + #10 +
    '      "enabled": false,' + #10 +
    '      "min_tool_calls": 5,' + #10 +
    '      "model": ""' + #10 +
    '    }' + #10 +
    '  },' + #10 +
    '  "openai_server_tools": { "web_search": true },' + #10 +
    '  "gemini_server_tools": { "google_search": true },' + #10 +
    '  "providers": [' + #10 +
    '    {' + #10 +
    '      "name": "deepseek",' + #10 +
    '      "kind": "deepseek",' + #10 +
    '      "api_base": "https://api.deepseek.com",' + #10 +
    '      "api_key": "",' + #10 +
    '      "model": "deepseek-flash"' + #10 +
    '    }' + #10 +
    '  ],' + #10 +
    '  "mcp_servers": [],' + #10 +
    '  "crons": [],' + #10 +
    '  "skills": [' + #10 +
    '    { "name": "clawhub:<slug>[@<version>]", "source": "clawhub:<slug>[@<version>]", "enabled": true },' + #10 +
    '    { "name": "clawhub:<slug>", "source": "clawhub:<slug>", "enabled": true }' + #10 +
    '  ]' + #10 +
    '}' + #10;

implementation

uses
  fpjson;

var
  GSettings: TPasClawIDESettings = nil;

function PasClawSettings: TPasClawIDESettings;
begin
  if GSettings = nil then
  begin
    GSettings := TPasClawIDESettings.Create;
    GSettings.Load;
  end;
  Result := GSettings;
end;

procedure FreePasClawSettings;
begin
  FreeAndNil(GSettings);
end;

function ResolvePasClawExe(const APath: string): string;
var
  S, Dir: string;
begin
  S := Trim(APath);
  if S = '' then Exit(S);
  if (ExtractFileExt(S) <> '') and FileExists(S) then Exit(S);
  Dir := ExcludeTrailingPathDelimiter(S);
  Result := IncludeTrailingPathDelimiter(Dir) + PasClawExeName;
  if not FileExists(Result) then
    Result := IncludeTrailingPathDelimiter(Dir) + 'build' + PathDelim + PasClawExeName;
  if not FileExists(Result) then
    Result := IncludeTrailingPathDelimiter(Dir) + PasClawExeName;
end;

function FindPasClawExe(const ADir: string): string;
begin
  Result := ResolvePasClawExe(ADir);
end;

{ ---------------- 原始字节读写（config.json 强制 UTF-8） ---------------- }

{ config.json 由 pasclaw 以 UTF-8 落盘，systemPrompt 里通常有中文。
   TStringList.LoadFromFile 会按 RTL 代码页解释字节，容易把 UTF-8 中文
   弄成乱码，所以这里一律按原始字节读、按 UTF-8 写。 }
function ReadFileUTF8(const AFileName: string; out AText: UTF8String): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  AText := '';
  if not FileExists(AFileName) then Exit;
  F := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(AText, F.Size);
    if F.Size > 0 then
      F.ReadBuffer(AText[1], F.Size);
  finally
    F.Free;
  end;
  { 去掉可能存在的 UTF-8 BOM }
  if (Length(AText) >= 3) and (AText[1] = #$EF) and (AText[2] = #$BB) and
     (AText[3] = #$BF) then
    Delete(AText, 1, 3);
  Result := True;
end;

function WriteFileUTF8(const AFileName: string; const AText: UTF8String): Boolean;
var
  F: TFileStream;
begin
  Result := False;
  ForceDirectories(ExtractFilePath(AFileName));
  F := TFileStream.Create(AFileName, fmCreate);
  try
    if Length(AText) > 0 then
      F.WriteBuffer(AText[1], Length(AText));
    Result := True;
  finally
    F.Free;
  end;
end;

function ReadJSONObject(const AFileName: string): TJSONObject;
var
  Text: UTF8String;
  Data: TJSONData;
begin
  Result := nil;
  if not ReadFileUTF8(AFileName, Text) then Exit;
  Data := nil;
  try
    Data := GetJSON(Text);
  except
    Data := nil;
  end;
  if Data is TJSONObject then
    Result := TJSONObject(Data)
  else
    Data.Free;
end;

{ ---------------- TPasClawProvider ---------------- }

procedure TPasClawProvider.Assign(Source: TPersistent);
begin
  if Source is TPasClawProvider then
  begin
    FName    := TPasClawProvider(Source).FName;
    FKind    := TPasClawProvider(Source).FKind;
    FApiBase := TPasClawProvider(Source).FApiBase;
    FApiKey  := TPasClawProvider(Source).FApiKey;
    FModel   := TPasClawProvider(Source).FModel;
  end
  else
    inherited Assign(Source);
end;

function TPasClawProvider.Clone: TPasClawProvider;
begin
  Result := TPasClawProvider.Create;
  Result.Assign(Self);
end;

{ ---------------- TPasClawIDESettings ---------------- }

constructor TPasClawIDESettings.Create;
begin
  inherited Create;
  FFileName        := DefaultFileName;
  FAgentConfigFile := DefaultAgentConfigFileName;
  FPasClawDir      := '';
  FLazarusDir      := '';
  FFpcDir          := '';
  FSystemPrompt    := '';
  FProviders       := TObjectList.Create(True);
  DetectDefaults;
end;

destructor TPasClawIDESettings.Destroy;
begin
  FreeAndNil(FProviders);
  inherited Destroy;
end;

class function TPasClawIDESettings.HomeDir: string;
begin
  {$IFDEF MSWINDOWS}
  Result := GetEnvironmentVariable('USERPROFILE');
  if Result = '' then
    Result := GetEnvironmentVariable('HOMEDRIVE') + GetEnvironmentVariable('HOMEPATH');
  {$ELSE}
  Result := GetEnvironmentVariable('HOME');
  {$ENDIF}
  Result := ExcludeTrailingPathDelimiter(Result);
end;

class function TPasClawIDESettings.PasClawExeDir: string;
begin
  { 先看当前目录（开发时 cwd 常常就指着 pasclaw.exe 所在处），否则用默认
    目录；ResolvePasClawExe 认得 <dir>\pasclaw.exe 和 <dir>\build\pasclaw.exe
    两种布局，所以这里取 exe 实际所在目录。 }
  if FileExists(PasClawExeName) then
    Result := ExpandFileName('.')
  else
    Result := ExtractFileDir(ResolvePasClawExe(DefaultPasClawDir));
  Result := ExcludeTrailingPathDelimiter(Result);
end;

class function TPasClawIDESettings.AgentConfigDir: string;
begin
  { pasclaw 自己（2026-10-10 起）的 config.json 就在 <exe 目录>\.pasclaw 下 }
  Result := ConfigDir;
end;

class function TPasClawIDESettings.DefaultAgentConfigFileName: string;
begin
  Result := IncludeTrailingPathDelimiter(AgentConfigDir) + AgentConfigName;
end;

class function TPasClawIDESettings.ConfigDir: string;
begin
  { 与 pasclaw 的数据目录保持一致：pasclaw.exe 旁边的 .pasclaw }
  Result := IncludeTrailingPathDelimiter(PasClawExeDir) + AgentConfigDirName;
end;

{ 旧版本的数据目录（2026-10-06 起是 %APPDATA%\PasClaw，其它平台
  ~/.config/PasClaw）。搬完就不再使用。 }
class function TPasClawIDESettings.LegacyConfigDir: string;
var
  Base: string;
begin
  {$IFDEF MSWINDOWS}
  Base := GetEnvironmentVariable('APPDATA');
  if Base = '' then
    Base := GetEnvironmentVariable('USERPROFILE');
  {$ELSE}
  Base := GetEnvironmentVariable('XDG_CONFIG_HOME');
  if Base = '' then
  begin
    Base := GetEnvironmentVariable('HOME');
    if Base <> '' then
      Base := IncludeTrailingPathDelimiter(Base) + '.config';
  end;
  {$ENDIF}
  if Base = '' then
    Base := GetCurrentDir;
  Result := IncludeTrailingPathDelimiter(Base) + 'PasClaw';
end;

{ 整文件拷贝：先写 <dst>.part 再改名，中途失败不会留下半截的目标文件
  （日志库半截就废了）。 }
function CopyFileAtomic(const Src, Dst: string): Boolean;
var
  S, D: TFileStream;
  Tmp: string;
begin
  Result := False;
  Tmp := Dst + '.part';
  S := nil;
  D := nil;
  try
    try
      ForceDirectories(ExtractFilePath(Dst));
      S := TFileStream.Create(Src, fmOpenRead or fmShareDenyNone);
      D := TFileStream.Create(Tmp, fmCreate);
      D.CopyFrom(S, 0);
      FreeAndNil(D);
      FreeAndNil(S);
      Result := RenameFile(Tmp, Dst);
    except
      Result := False;
    end;
  finally
    FreeAndNil(D);
    FreeAndNil(S);
    if not Result then
      DeleteFile(Tmp);
  end;
end;

class procedure TPasClawIDESettings.MigrateLegacyData(const ANewDir: string);
const
  FileNames: array[0..1] of string = (PluginConfigName, PluginLogName);
var
  Old, Src, Dst: string;
  I: Integer;
begin
  Old := LegacyConfigDir;
  if SameFileName(ExcludeTrailingPathDelimiter(Old),
                  ExcludeTrailingPathDelimiter(ANewDir)) then
    Exit;
  if not DirectoryExists(Old) then
    Exit;
  for I := Low(FileNames) to High(FileNames) do
  begin
    Src := IncludeTrailingPathDelimiter(Old) + FileNames[I];
    Dst := IncludeTrailingPathDelimiter(ANewDir) + FileNames[I];
    if FileExists(Src) and not FileExists(Dst) then
      CopyFileAtomic(Src, Dst);
  end;
end;

class function TPasClawIDESettings.DefaultFileName: string;
begin
  Result := DataFile(PluginConfigName);
end;

class function TPasClawIDESettings.DataFile(const AName: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ConfigDir) + AName;
end;

function TPasClawIDESettings.Resolve(const APath: string): string;
var
  P: string;
begin
  P := Trim(APath);
  if P = '' then Exit('');
  P := StringReplace(P, '/', PathDelim, [rfReplaceAll]);
  { 相对路径按配置文件所在目录解析；绝对路径（盘符或根斜杠）原样使用 }
  if not (IsPathDelimiter(P, 1) or
          ((Length(P) >= 2) and (P[2] = ':'))) then
    P := IncludeTrailingPathDelimiter(ExtractFilePath(FFileName)) + P;
  Result := ExcludeTrailingPathDelimiter(ExpandFileName(P));
end;

procedure TPasClawIDESettings.Normalize;
begin
  FPasClawDir := Resolve(FPasClawDir);
  FLazarusDir := Resolve(FLazarusDir);
  FFpcDir     := Resolve(FFpcDir);
end;

{ 自动探测：只在对应目录还没配置时填，绝不覆盖用户填过的值。
  探测目标按"当前机器上真实存在的布局"来，找不到就留空。 }
procedure TPasClawIDESettings.DetectDefaults;
begin
  if (FPasClawDir = '') and FileExists(PasClawExeName) then
    FPasClawDir := ExcludeTrailingPathDelimiter(ExpandFileName('.'));

  if (FPasClawDir = '') and DirectoryExists(DefaultPasClawDir) then
    FPasClawDir := ExcludeTrailingPathDelimiter(DefaultPasClawDir);

  if (FLazarusDir = '') and DirectoryExists(DefaultLazarusDir) then
    FLazarusDir := ExcludeTrailingPathDelimiter(DefaultLazarusDir);

  if (FFpcDir = '') and DirectoryExists(DefaultFpcDir) then
    FFpcDir := ExcludeTrailingPathDelimiter(DefaultFpcDir);

  Normalize;
end;

{ 从一个刚被选中的目录反推其余目录。
  例：选中 D:\QFLazarus4.8\lazarus，则 D:\QFLazarus4.8\fpc 自动认出来。 }
function HasFpcCompiler(const ADir: string): Boolean;
begin
  Result := DirectoryExists(ADir) and
            (FileExists(IncludeTrailingPathDelimiter(ADir) + 'bin' + PathDelim +
                        'x86_64-win64' + PathDelim + 'fpc.exe') or
             FileExists(IncludeTrailingPathDelimiter(ADir) + 'bin' + PathDelim +
                        'i386-win32' + PathDelim + 'fpc.exe'));
end;

function HasLazbuild(const ADir: string): Boolean;
begin
  Result := FileExists(IncludeTrailingPathDelimiter(ADir) + 'lazbuild.exe') or
            FileExists(IncludeTrailingPathDelimiter(ADir) + 'lazbuild');
end;

procedure TPasClawIDESettings.AutoFillFrom(const ASource: string);
var
  Src, Base: string;
begin
  Src := Trim(ASource);
  if Src <> '' then
    Src := ExcludeTrailingPathDelimiter(ExpandFileName(Src));

  { 选中了 Lazarus 目录：同级找 fpc，上级找 pasclaw }
  if (Src <> '') and HasLazbuild(Src) then
  begin
    if FLazarusDir = '' then FLazarusDir := Src;
    Base := ExcludeTrailingPathDelimiter(ExtractFileDir(Src));
    if (FFpcDir = '') and HasFpcCompiler(IncludeTrailingPathDelimiter(Base) + 'fpc') then
      FFpcDir := IncludeTrailingPathDelimiter(Base) + 'fpc';
    if (FPasClawDir = '') and FileExists(IncludeTrailingPathDelimiter(Base) + PasClawExeName) then
      FPasClawDir := Base;
  end;

  { 选中了 FPC 目录：同级找 lazarus }
  if (Src <> '') and HasFpcCompiler(Src) then
  begin
    if FFpcDir = '' then FFpcDir := Src;
    Base := ExcludeTrailingPathDelimiter(ExtractFileDir(Src));
    if (FLazarusDir = '') and HasLazbuild(IncludeTrailingPathDelimiter(Base) + 'lazarus') then
      FLazarusDir := IncludeTrailingPathDelimiter(Base) + 'lazarus';
  end;

  { 选中了 PasClaw 目录：什么都推不出来，只填自己 }
  if (Src <> '') and (FPasClawDir = '') and FileExists(ResolvePasClawExe(Src)) then
    FPasClawDir := Src;

  DetectDefaults;
end;

{ ---------------- providers ---------------- }

function TPasClawIDESettings.GetProvider(Index: Integer): TPasClawProvider;
begin
  Result := TPasClawProvider(FProviders[Index]);
end;

function TPasClawIDESettings.GetProviderCount: Integer;
begin
  Result := FProviders.Count;
end;

function TPasClawIDESettings.AddProvider(const AName: string): TPasClawProvider;
begin
  Result := TPasClawProvider.Create;
  Result.Name := AName;
  FProviders.Add(Result);
end;

procedure TPasClawIDESettings.RemoveProvider(Index: Integer);
begin
  if (Index >= 0) and (Index < FProviders.Count) then
    FProviders.Delete(Index);
end;

procedure TPasClawIDESettings.ClearProviders;
begin
  FProviders.Clear;
end;

function TPasClawIDESettings.IndexOfProvider(const AName: string): Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to FProviders.Count - 1 do
    if SameText(TPasClawProvider(FProviders[I]).Name, AName) then
      Exit(I);
end;

function TPasClawIDESettings.FindProvider(const AName: string): TPasClawProvider;
var
  I: Integer;
begin
  I := IndexOfProvider(AName);
  if I >= 0 then
    Result := TPasClawProvider(FProviders[I])
  else
    Result := nil;
end;

{ ---------------- 载入 / 保存 ---------------- }

procedure TPasClawIDESettings.LoadAgentConfig;
var
  Root, Agents, Defaults, Obj: TJSONObject;
  Data: TJSONData;
  Arr: TJSONArray;
  P: TPasClawProvider;
  I: Integer;
begin
  FProviders.Clear;
  FSystemPrompt := '';

  { 首次运行：<pasclaw.exe 目录>\.pasclaw\config.json 不存在时写入默认模板，
    让 pasclaw CLI 第一次就能起来，也让设置对话框里的
    providers / systemPrompt 有初始内容。写失败就退化成"没有 agent 配置"，
    不影响插件本身的加载。 }
  if not FileExists(FAgentConfigFile) then
  begin
    try
      WriteFileUTF8(FAgentConfigFile, DefaultAgentConfigJSON);
    except
      { 忽略：下面 ReadJSONObject 会返回 nil，等同没有配置 }
    end;
  end;

  Root := ReadJSONObject(FAgentConfigFile);
  if Root = nil then Exit;
  try
    { providers[] }
    Data := Root.Find('providers');
    if Data is TJSONArray then
    begin
      Arr := TJSONArray(Data);
      for I := 0 to Arr.Count - 1 do
      begin
        if not (Arr.Items[I] is TJSONObject) then Continue;
        Obj := TJSONObject(Arr.Items[I]);
        P := TPasClawProvider.Create;
        P.Name    := Obj.Get('name', '');
        P.Kind    := Obj.Get('kind', '');
        P.ApiBase := Obj.Get('api_base', Obj.Get('apiBase', ''));
        P.ApiKey  := Obj.Get('api_key', Obj.Get('apiKey', ''));
        P.Model   := Obj.Get('model', '');
        FProviders.Add(P);
      end;
    end;

    { agents.defaults.systemPrompt }
    Agents := Root.Get('agents', TJSONObject(nil));
    if Agents <> nil then
    begin
      Defaults := Agents.Get('defaults', TJSONObject(nil));
      if Defaults <> nil then
        FSystemPrompt := Defaults.Get('systemPrompt',
                          Defaults.Get('system_prompt', ''));
    end;
  finally
    Root.Free;
  end;
end;

function TPasClawIDESettings.SaveAgentConfig: Boolean;
var
  Root, Agents, Defaults, Item: TJSONObject;
  Arr: TJSONArray;
  P: TPasClawProvider;
  I: Integer;
  Text: UTF8String;
begin
  Result := False;
  try
    Root := ReadJSONObject(FAgentConfigFile);
    { 已有配置文件但解析失败时不要覆盖，免得把用户的配置冲掉 }
    if (Root = nil) and FileExists(FAgentConfigFile) then Exit;
    if Root = nil then
      Root := TJSONObject.Create;
    try
      { providers[]：插件里的列表即最终内容 }
      Arr := TJSONArray.Create;
      for I := 0 to FProviders.Count - 1 do
      begin
        P := TPasClawProvider(FProviders[I]);
        Item := TJSONObject.Create;
        Item.Add('name', P.Name);
        if P.Kind <> '' then Item.Add('kind', P.Kind);
        if P.ApiBase <> '' then Item.Add('api_base', P.ApiBase);
        if P.ApiKey <> '' then Item.Add('api_key', P.ApiKey);
        if P.Model <> '' then Item.Add('model', P.Model);
        Arr.Add(Item);
      end;
      Root.Elements['providers'] := Arr;

      { agents.defaults.systemPrompt }
      Agents := Root.Get('agents', TJSONObject(nil));
      if Agents = nil then
      begin
        Agents := TJSONObject.Create;
        Root.Elements['agents'] := Agents;
      end;
      Defaults := Agents.Get('defaults', TJSONObject(nil));
      if Defaults = nil then
      begin
        Defaults := TJSONObject.Create;
        Agents.Elements['defaults'] := Defaults;
      end;
      Defaults.Strings['systemPrompt'] := FSystemPrompt;

      Text := Root.FormatJSON(AsJSONFormat);
      Result := WriteFileUTF8(FAgentConfigFile, Text + #10);
    finally
      Root.Free;
    end;
  except
    Result := False;
  end;
end;

function TPasClawIDESettings.Load: Boolean;
var
  L: TStringList;
  Data: TJSONData;
  Obj: TJSONObject;
begin
  Result := False;
  FPasClawDir := '';
  FLazarusDir := '';
  FFpcDir := '';

  { 数据目录搬过一次（%APPDATA%\PasClaw → <pasclaw.exe 目录>\.pasclaw），
    首次运行把旧目录里的文件带过来，别让日志历史悄悄丢掉。 }
  MigrateLegacyData(ExtractFileDir(FFileName));

  if FileExists(FFileName) then
  begin
    L := TStringList.Create;
    try
      try
        L.LoadFromFile(FFileName);
        Data := nil;
        try
          Data := GetJSON(L.Text);
        except
          Data := nil;
        end;
        if Data is TJSONObject then
        begin
          Obj := TJSONObject(Data);
          FPasClawDir := Trim(Obj.Get('pasclawDir', ''));
          FLazarusDir := Trim(Obj.Get('lazarusDir', ''));
          FFpcDir     := Trim(Obj.Get('fpcDir', ''));
          Result := True;
        end;
        Data.Free;
      except
        { 配置损坏时静默退回自动探测 }
      end;
    finally
      L.Free;
    end;
  end;

  Normalize;
  DetectDefaults;

  LoadAgentConfig;
  if FileExists(FAgentConfigFile) then
    Result := True;
end;

function TPasClawIDESettings.Save: Boolean;
var
  Obj: TJSONObject;
  S: string;
  L: TStringList;
begin
  Result := False;
  try
    ForceDirectories(ExtractFilePath(FFileName));
    Obj := TJSONObject.Create;
    try
      Obj.Add('pasclawDir', FPasClawDir);
      Obj.Add('lazarusDir', FLazarusDir);
      Obj.Add('fpcDir',     FFpcDir);
      S := Obj.FormatJSON(AsJSONFormat) + LineEnding;
    finally
      Obj.Free;
    end;
    { 显式按 UTF-8 落盘：目录里可能出现中文用户名 }
    L := TStringList.Create;
    try
      L.Text := S;
      L.SaveToFile(FFileName);
    finally
      L.Free;
    end;
    Result := True;
  except
    Result := False;
  end;

  { providers / systemPrompt 写到 pasclaw 自己的 .pasclaw\config.json }
  if not SaveAgentConfig then
    Result := False;
end;

function TPasClawIDESettings.EffectivePasClawDir: string;
begin
  if FPasClawDir <> '' then
    Result := FPasClawDir
  else if DirectoryExists(DefaultPasClawDir) then
    Result := DefaultPasClawDir
  else
    Result := '';
end;

function TPasClawIDESettings.EffectiveLazarusDir: string;
begin
  if FLazarusDir <> '' then
    Result := FLazarusDir
  else if DirectoryExists(DefaultLazarusDir) then
    Result := DefaultLazarusDir
  else
    Result := '';
end;

function TPasClawIDESettings.EffectiveFpcDir: string;
begin
  if FFpcDir <> '' then
    Result := FFpcDir
  else if DirectoryExists(DefaultFpcDir) then
    Result := DefaultFpcDir
  else
    Result := '';
end;

initialization
  { 什么都不做：延迟到 PasClawSettings 第一次调用再读盘，
    避免插件加载阶段就访问文件系统。 }

finalization
  FreePasClawSettings;

end.
