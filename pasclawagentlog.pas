unit PasClawAgentLog;

{$mode objfpc}{$H+}
{$WARN 4105 OFF}
{$codepage utf8}

{ PasClaw 插件的 Agent 使用日志（SQLite）。
  每次点“发送”把 edtPrompt.Text 落一行，会话结束后把 memOutput.Text 的全文
  写回该行；浏览窗口可以把任意一条日志回读并填回 edtPrompt / memOutput。

  日志库固定放在插件数据目录（<pasclaw.exe 目录>\.pasclaw\agentlog.db），
  与配置文件 ide-plugin.json 同一个目录；它不跟着工程走，每条记录用
  project 列记下当时的工程名。 }

interface

uses
  Classes, SysUtils, Contnrs, Forms, Controls, StdCtrls, ExtCtrls, ComCtrls,
  Dialogs, Graphics, LCLType,
  LazIDEIntf, ProjectIntf, PackageIntf,
  sqlite3dyn,
  PasClawConfig;

const
  { 日志库名：与配置文件 ide-plugin.json 同目录（见 PluginLogName） }
  AgentLogName = PluginLogName;
  { 浏览窗口默认最多列出多少条 }
  AgentLogListLimit   = 500;

  { agent_log.status 的取值 }
  LogStatusRunning   = 'running';
  LogStatusDone      = 'done';
  LogStatusCancelled = 'cancelled';
  LogStatusError     = 'error';

type
  { 列表用的一条日志摘要 }
  TAgentLogItem = class
  public
    Id: Integer;
    CreatedAt: string;
    Project: string;
    Status: string;
    Prompt: string;
    DurationMs: Int64;
  end;

  { Agent 使用日志。所有方法都不抛异常：失败时置 LastError 并返回 False/-1。 }
  TAgentLog = class
  private
    FDb: psqlite3;
    FFile: string;
    FLastError: string;
    procedure SetError(const S: string);
    function  ExecSQL(const SQL: string): Boolean;
    function  Prepare(const SQL: string; out Stmt: psqlite3_stmt): Boolean;
    function  ColText(Stmt: psqlite3_stmt; Idx: Integer): string;
    procedure BindText(Stmt: psqlite3_stmt; Idx: Integer; const S: string);
    function  OpenDb(const AFile: string): Boolean;
    function  EnsureSchema: Boolean;
  public
    destructor Destroy; override;
    { 打开（或切换到）日志库；同一路径重复调用是空操作。 }
    function  EnsureOpen(const AFile: string): Boolean;
    procedure Close;
    function  IsOpen: Boolean;
    property  FileName: string read FFile;
    property  LastError: string read FLastError;

    { 新开一条日志，返回自增 id（失败 -1） }
    function  AddEntry(const APrompt, AProject: string): Integer;
    { 会话结束时写回完整输出 }
    procedure UpdateEntry(AId: Integer; const AOutput, AStatus: string;
      ADurationMs: Int64);
    procedure DeleteEntry(AId: Integer);
    procedure ClearAll;
    function  EntryCount: Integer;
    { 最近的日志摘要，倒序；调用方负责释放（OwnsObjects） }
    function  ListRecent(ALimit: Integer): TObjectList;
    { 取一条完整日志 }
    function  GetEntry(AId: Integer; out ACreatedAt, APrompt, AOutput,
      AStatus: string; out ADurationMs: Int64): Boolean;
  end;

  { 日志浏览窗口：ShowModal 返回 mrOk 时 PickedPrompt / PickedOutput 有效 }
  TfmAgentLog = class(TForm)
  private
    FItems: TObjectList;
    FPickedId: Integer;
    FPickedPrompt: string;
    FPickedOutput: string;
    pnlTop: TPanel;
    lvLog: TListView;
    splMain: TSplitter;
    memPreview: TMemo;
    btnRefresh: TButton;
    btnLoad: TButton;
    btnDelete: TButton;
    btnClear: TButton;
    btnClose: TButton;
    lblInfo: TLabel;
    procedure BuildUI;
    procedure Reload;
    procedure ShowPreview(AIndex: Integer);
    procedure SetPicked(AIndex: Integer);
    procedure btnRefreshClick(Sender: TObject);
    procedure btnLoadClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
    procedure btnCloseClick(Sender: TObject);
    procedure lvLogSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure lvLogDblClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    property PickedPrompt: string read FPickedPrompt;
    property PickedOutput: string read FPickedOutput;
    property PickedId: Integer read FPickedId;
  end;

{ 进程级单例 }
function AgentLog: TAgentLog;
{ 当前工程的目录（没有打开工程时返回 ''） }
function ActiveProjectDir: string;
{ 当前工程名（.lpi 的文件名，不含扩展名） }
function ActiveProjectName: string;
{ 日志库路径：插件数据目录下的 agentlog.db，与配置文件同目录 }
function ActiveAgentLogFile: string;
{ 定位并加载 sqlite3.dll，成功返回 True }
function LoadSqliteLibrary: Boolean;
{ 日志里存的时间字符串 }
function LogStatusText(const AStatus: string): string;

implementation

const
  SqliteDllName = 'sqlite3.dll';

{ ---------------- 字符串 <-> sqlite 的 UTF-8 ----------------

   LCL 控件里的 string 里装的已经是 UTF-8 字节（与插件其它单元一致），
   而 sqlite3 的 pansichar 参数要求 UTF-8。RawByteString 赋值不做代码页
   转换，正好把它们原样搬过去。 }

function AsUtf8(const S: string): RawByteString;
begin
  Result := S;
end;

function Utf8ToStr(const P: PAnsiChar): string;
var
  R: RawByteString;
begin
  if P = nil then
    Exit('');
  R := P;
  Result := R;
end;

{ ---------------- sqlite3.dll 定位 ---------------- }

var
  GSqliteLoaded: Boolean = False;

function PackageDir: string;
var
  Pkg: TIDEPackage;
begin
  Result := '';
  if not Assigned(PackageEditingInterface) then
    Exit;
  Pkg := PackageEditingInterface.FindPackageWithName('PasClawIDEPlugin');
  if Pkg = nil then
    Exit;
  Result := Pkg.DirectoryExpanded;
  if Result = '' then
    Result := ExtractFilePath(Pkg.Filename);
end;

function LoadSqliteLibrary: Boolean;
var
  List: TStringList;
  I: Integer;
begin
  if GSqliteLoaded then
    Exit(True);

  List := TStringList.Create;
  try
    { 1. 插件目录：sqlite3.dll 跟 .lpk 放在一起 }
    try
      if PackageDir <> '' then
        List.Add(IncludeTrailingPathDelimiter(PackageDir) + SqliteDllName);
    except
      { 取不到就算了 }
    end;
    { 2. lazarus.exe 所在目录 }
    List.Add(IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + SqliteDllName);
    { 3. PasClaw 主目录（pasclaw.exe 自己带一份） }
    try
      if PasClawSettings.EffectivePasClawDir <> '' then
        List.Add(IncludeTrailingPathDelimiter(PasClawSettings.EffectivePasClawDir) +
          SqliteDllName);
    except
    end;
    { 4. 插件配置目录 }
    try
      List.Add(IncludeTrailingPathDelimiter(TPasClawIDESettings.ConfigDir) + SqliteDllName);
    except
    end;
    { 5. 当前目录 }
    List.Add(IncludeTrailingPathDelimiter(GetCurrentDir) + SqliteDllName);
    { 6. 交给系统按 PATH 等规则去找 }
    List.Add(SqliteDllName);

    for I := 0 to List.Count - 1 do
    begin
      if FileExists(List[I]) then
      begin
        if TryInitializeSqlite(UTF8Decode(List[I])) > 0 then
        begin
          GSqliteLoaded := True;
          Exit(True);
        end;
      end;
    end;
    { 兜底：让 sqlite3dyn 自己按默认名字找一次 }
    if TryInitializeSqlite('') > 0 then
      GSqliteLoaded := True;
  finally
    List.Free;
  end;
  Result := GSqliteLoaded;
end;

{ ---------------- 工程信息 ---------------- }

function ActiveProjectDir: string;
var
  Proj: TLazProject;
  InfoFile: string;
begin
  Result := '';
  try
    Proj := LazarusIDE.ActiveProject;
    if not Assigned(Proj) then
      Exit;
    InfoFile := Proj.ProjectInfoFile;
    if InfoFile = '' then
      Exit;
  except
    Exit;
  end;
  Result := ExtractFilePath(InfoFile);
end;

function ActiveProjectName: string;
var
  Proj: TLazProject;
begin
  Result := '';
  try
    Proj := LazarusIDE.ActiveProject;
    if Assigned(Proj) then
      Result := ChangeFileExt(ExtractFileName(Proj.ProjectInfoFile), '');
  except
    Result := '';
  end;
end;

function ActiveAgentLogFile: string;
begin
  { 不跟随工程：始终是 <pasclaw.exe 目录>\.pasclaw\agentlog.db，
    与配置文件 ide-plugin.json 放在同一个目录 }
  Result := TPasClawIDESettings.DataFile(AgentLogName);
end;

function LogStatusText(const AStatus: string): string;
begin
  if AStatus = LogStatusDone then
    Result := '完成'
  else if AStatus = LogStatusRunning then
    Result := '运行中'
  else if AStatus = LogStatusCancelled then
    Result := '已取消'
  else if AStatus = LogStatusError then
    Result := '错误'
  else
    Result := AStatus;
end;

function FormatDuration(AMs: Int64): string;
begin
  if AMs < 1000 then
    Result := IntToStr(AMs) + ' ms'
  else if AMs < 60000 then
    Result := Format('%.1f s', [AMs / 1000])
  else
    Result := Format('%.1f min', [AMs / 60000]);
end;

{ 列表里显示用的 prompt 单行摘要 }
function FirstLine(const S: string): string;
var
  P: Integer;
begin
  P := Pos(#10, S);
  if P > 0 then
    Result := Copy(S, 1, P - 1)
  else
    Result := S;
  Result := StringReplace(Result, #13, '', [rfReplaceAll]);
  Result := Trim(Result);
  if Result = '' then
    Result := '（空）';
end;

{ 列表里显示用的工程名（旧记录 / 没有工程时给个占位） }
function ProjectText(const S: string): string;
begin
  Result := Trim(S);
  if Result = '' then
    Result := '（无工程）';
end;

{ ---------------- TAgentLog ---------------- }

destructor TAgentLog.Destroy;
begin
  Close;
  inherited Destroy;
end;

procedure TAgentLog.SetError(const S: string);
begin
  FLastError := S;
end;

function TAgentLog.IsOpen: Boolean;
begin
  Result := FDb <> nil;
end;

procedure TAgentLog.Close;
begin
  if FDb <> nil then
  begin
    sqlite3_close(FDb);
    FDb := nil;
  end;
  FFile := '';
end;

function TAgentLog.ExecSQL(const SQL: string): Boolean;
var
  S: RawByteString;
  ErrMsg: PAnsiChar;
  RC: Integer;
begin
  Result := False;
  if FDb = nil then
    Exit;
  S := AsUtf8(SQL);
  ErrMsg := nil;
  RC := sqlite3_exec(FDb, PAnsiChar(S), nil, nil, @ErrMsg);
  if RC <> SQLITE_OK then
  begin
    if ErrMsg <> nil then
    begin
      SetError(Utf8ToStr(ErrMsg));
      sqlite3_free(ErrMsg);
    end
    else
      SetError(Format('SQL 执行失败（%d）', [RC]));
    Exit;
  end;
  Result := True;
end;

function TAgentLog.Prepare(const SQL: string; out Stmt: psqlite3_stmt): Boolean;
var
  S: RawByteString;
begin
  Result := False;
  Stmt := nil;
  if FDb = nil then
    Exit;
  S := AsUtf8(SQL);
  if sqlite3_prepare_v2(FDb, PAnsiChar(S), -1, @Stmt, nil) <> SQLITE_OK then
  begin
    SetError(Utf8ToStr(sqlite3_errmsg(FDb)));
    Exit;
  end;
  Result := True;
end;

function TAgentLog.ColText(Stmt: psqlite3_stmt; Idx: Integer): string;
begin
  Result := Utf8ToStr(sqlite3_column_text(Stmt, Idx));
end;

procedure TAgentLog.BindText(Stmt: psqlite3_stmt; Idx: Integer; const S: string);
var
  R: RawByteString;
begin
  R := AsUtf8(S);
  if R = '' then
    sqlite3_bind_text(Stmt, Idx, '', 0, sqlite3_destructor_type(SQLITE_TRANSIENT))
  else
    sqlite3_bind_text(Stmt, Idx, PAnsiChar(R), -1, sqlite3_destructor_type(SQLITE_TRANSIENT));
end;

function TAgentLog.EnsureSchema: Boolean;
begin
  Result := ExecSQL(
    'CREATE TABLE IF NOT EXISTS agent_log(' +
    '  id          INTEGER PRIMARY KEY AUTOINCREMENT,' +
    '  created_at  TEXT    NOT NULL,' +
    '  project     TEXT    NOT NULL DEFAULT '''',' +
    '  prompt      TEXT    NOT NULL DEFAULT '''',' +
    '  output      TEXT    NOT NULL DEFAULT '''',' +
    '  status      TEXT    NOT NULL DEFAULT ''running'',' +
    '  duration_ms INTEGER NOT NULL DEFAULT 0)') and
    ExecSQL('CREATE INDEX IF NOT EXISTS ix_agent_log_created ON agent_log(created_at)');
end;

function TAgentLog.OpenDb(const AFile: string): Boolean;
var
  Db: psqlite3;
  Name: RawByteString;
begin
  Result := False;
  if AFile = '' then
  begin
    SetError('日志数据库路径为空');
    Exit;
  end;
  if not LoadSqliteLibrary then
  begin
    SetError('无法加载 ' + SqliteDllName + '，请把它放到插件目录或 lazarus.exe 目录下');
    Exit;
  end;

  try
    ForceDirectories(ExtractFilePath(AFile));
  except
    { 目录建不出来时让 sqlite3_open 去报错 }
  end;

  Db := nil;
  Name := AsUtf8(AFile);
  if sqlite3_open(PAnsiChar(Name), @Db) <> SQLITE_OK then
  begin
    if Db <> nil then
    begin
      SetError(Utf8ToStr(sqlite3_errmsg(Db)));
      sqlite3_close(Db);
    end
    else
      SetError(Format('打开日志数据库失败：%s', [AFile]));
    Exit;
  end;

  FDb := Db;
  FFile := AFile;
  if not EnsureSchema then
  begin
    Close;
    Exit;
  end;
  Result := True;
end;

function TAgentLog.EnsureOpen(const AFile: string): Boolean;
begin
  if (FDb <> nil) and (FFile = AFile) then
    Exit(True);
  Close;
  try
    Result := OpenDb(AFile);
  except
    on E: Exception do
    begin
      SetError(E.Message);
      Result := False;
    end;
  end;
end;

function TAgentLog.AddEntry(const APrompt, AProject: string): Integer;
var
  Stmt: psqlite3_stmt;
begin
  Result := -1;
  if FDb = nil then
    Exit;
  if not Prepare('INSERT INTO agent_log(created_at, project, prompt, output, status, duration_ms)' +
    ' VALUES(?, ?, ?, '''', ''' + LogStatusRunning + ''', 0)', Stmt) then
    Exit;
  try
    BindText(Stmt, 1, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    BindText(Stmt, 2, AProject);
    BindText(Stmt, 3, APrompt);
    if sqlite3_step(Stmt) <> SQLITE_DONE then
    begin
      SetError(Utf8ToStr(sqlite3_errmsg(FDb)));
      Exit;
    end;
    Result := Integer(sqlite3_last_insert_rowid(FDb));
  finally
    sqlite3_finalize(Stmt);
  end;
end;

procedure TAgentLog.UpdateEntry(AId: Integer; const AOutput, AStatus: string;
  ADurationMs: Int64);
var
  Stmt: psqlite3_stmt;
begin
  if (FDb = nil) or (AId < 0) then
    Exit;
  if not Prepare('UPDATE agent_log SET output = ?, status = ?, duration_ms = ? WHERE id = ?',
    Stmt) then
    Exit;
  try
    BindText(Stmt, 1, AOutput);
    BindText(Stmt, 2, AStatus);
    sqlite3_bind_int64(Stmt, 3, ADurationMs);
    sqlite3_bind_int64(Stmt, 4, AId);
    if sqlite3_step(Stmt) <> SQLITE_DONE then
      SetError(Utf8ToStr(sqlite3_errmsg(FDb)));
  finally
    sqlite3_finalize(Stmt);
  end;
end;

procedure TAgentLog.DeleteEntry(AId: Integer);
var
  Stmt: psqlite3_stmt;
begin
  if FDb = nil then
    Exit;
  if not Prepare('DELETE FROM agent_log WHERE id = ?', Stmt) then
    Exit;
  try
    sqlite3_bind_int64(Stmt, 1, AId);
    if sqlite3_step(Stmt) <> SQLITE_DONE then
      SetError(Utf8ToStr(sqlite3_errmsg(FDb)));
  finally
    sqlite3_finalize(Stmt);
  end;
end;

procedure TAgentLog.ClearAll;
begin
  if FDb = nil then
    Exit;
  ExecSQL('DELETE FROM agent_log');
  { 让 id 重新从 1 开始，顺便把库文件缩回去 }
  ExecSQL('DELETE FROM sqlite_sequence WHERE name = ''agent_log''');
  ExecSQL('VACUUM');
end;

function TAgentLog.EntryCount: Integer;
var
  Stmt: psqlite3_stmt;
begin
  Result := 0;
  if FDb = nil then
    Exit;
  if not Prepare('SELECT count(*) FROM agent_log', Stmt) then
    Exit;
  try
    if sqlite3_step(Stmt) = SQLITE_ROW then
      Result := Integer(sqlite3_column_int64(Stmt, 0));
  finally
    sqlite3_finalize(Stmt);
  end;
end;

function TAgentLog.ListRecent(ALimit: Integer): TObjectList;
var
  Stmt: psqlite3_stmt;
  Item: TAgentLogItem;
begin
  Result := TObjectList.Create(True);
  if FDb = nil then
    Exit;
  if not Prepare('SELECT id, created_at, status, prompt, duration_ms, project' +
    ' FROM agent_log ORDER BY id DESC LIMIT ?', Stmt) then
    Exit;
  try
    sqlite3_bind_int64(Stmt, 1, ALimit);
    while sqlite3_step(Stmt) = SQLITE_ROW do
    begin
      Item := TAgentLogItem.Create;
      Item.Id := Integer(sqlite3_column_int64(Stmt, 0));
      Item.CreatedAt := ColText(Stmt, 1);
      Item.Status := ColText(Stmt, 2);
      Item.Prompt := ColText(Stmt, 3);
      Item.DurationMs := sqlite3_column_int64(Stmt, 4);
      Item.Project := ColText(Stmt, 5);
      Result.Add(Item);
    end;
  finally
    sqlite3_finalize(Stmt);
  end;
end;

function TAgentLog.GetEntry(AId: Integer; out ACreatedAt, APrompt, AOutput,
  AStatus: string; out ADurationMs: Int64): Boolean;
var
  Stmt: psqlite3_stmt;
begin
  Result := False;
  ACreatedAt := '';
  APrompt := '';
  AOutput := '';
  AStatus := '';
  ADurationMs := 0;
  if FDb = nil then
    Exit;
  if not Prepare('SELECT created_at, prompt, output, status, duration_ms' +
    ' FROM agent_log WHERE id = ?', Stmt) then
    Exit;
  try
    sqlite3_bind_int64(Stmt, 1, AId);
    if sqlite3_step(Stmt) = SQLITE_ROW then
    begin
      ACreatedAt := ColText(Stmt, 0);
      APrompt := ColText(Stmt, 1);
      AOutput := ColText(Stmt, 2);
      AStatus := ColText(Stmt, 3);
      ADurationMs := sqlite3_column_int64(Stmt, 4);
      Result := True;
    end;
  finally
    sqlite3_finalize(Stmt);
  end;
end;

{ ---------------- 日志浏览窗口 ---------------- }

constructor TfmAgentLog.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FPickedId := -1;
  FItems    := TObjectList.Create(True);
  BuildUI;
  Reload;
end;

destructor TfmAgentLog.Destroy;
begin
  FreeAndNil(FItems);
  inherited Destroy;
end;

procedure TfmAgentLog.BuildUI;
begin
  Caption     := 'Agent 使用日志';
  Width       := 940;
  Height      := 560;
  Position    := poScreenCenter;
  BorderStyle := bsSizeable;
  Constraints.MinWidth  := 560;
  Constraints.MinHeight := 320;

  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 36;
  pnlTop.BevelOuter := bvNone;

  btnRefresh := TButton.Create(Self);
  btnRefresh.Parent := pnlTop;
  btnRefresh.Caption := '刷新';
  btnRefresh.SetBounds(4, 6, 70, 24);
  btnRefresh.OnClick := @btnRefreshClick;

  btnLoad := TButton.Create(Self);
  btnLoad.Parent := pnlTop;
  btnLoad.Caption := '载入到会话';
  btnLoad.SetBounds(80, 6, 100, 24);
  btnLoad.OnClick := @btnLoadClick;

  btnDelete := TButton.Create(Self);
  btnDelete.Parent := pnlTop;
  btnDelete.Caption := '删除';
  btnDelete.SetBounds(186, 6, 60, 24);
  btnDelete.OnClick := @btnDeleteClick;

  btnClear := TButton.Create(Self);
  btnClear.Parent := pnlTop;
  btnClear.Caption := '清空全部';
  btnClear.SetBounds(252, 6, 80, 24);
  btnClear.OnClick := @btnClearClick;

  lblInfo := TLabel.Create(Self);
  lblInfo.Parent := pnlTop;
  lblInfo.Caption := '';
  lblInfo.AutoSize := False;
  lblInfo.SetBounds(340, 11, 580, 16);
  lblInfo.Anchors := [akLeft, akTop, akRight];
  lblInfo.ShowHint := True;

  btnClose := TButton.Create(Self);
  btnClose.Parent := pnlTop;
  btnClose.Caption := '关闭';
  btnClose.Align := alRight;
  btnClose.Width := 70;
  btnClose.OnClick := @btnCloseClick;
  btnClose.Cancel := True;

  memPreview := TMemo.Create(Self);
  memPreview.Parent := Self;
  memPreview.ReadOnly := True;
  memPreview.ScrollBars := ssBoth;
  memPreview.WordWrap := False;
  memPreview.Font.Name := 'Consolas';
  memPreview.Font.Size := 10;

  splMain := TSplitter.Create(Self);
  splMain.Parent := Self;
  splMain.Width := 5;

  lvLog := TListView.Create(Self);
  lvLog.Parent := Self;
  lvLog.ViewStyle := vsReport;
  lvLog.ReadOnly := True;
  lvLog.RowSelect := True;
  lvLog.GridLines := True;
  lvLog.HideSelection := False;
  lvLog.Width := 540;
  lvLog.Columns.Add.Caption := '时间';
  lvLog.Columns[0].Width := 130;
  lvLog.Columns.Add.Caption := '工程';
  lvLog.Columns[1].Width := 110;
  lvLog.Columns.Add.Caption := '状态';
  lvLog.Columns[2].Width := 66;
  lvLog.Columns.Add.Caption := '耗时';
  lvLog.Columns[3].Width := 66;
  lvLog.Columns.Add.Caption := '提示';
  lvLog.Columns[4].Width := 150;
  lvLog.OnSelectItem := @lvLogSelectItem;
  lvLog.OnDblClick := @lvLogDblClick;

  { 对齐顺序：最后设置 Align 的 alLeft 控件排在最左边 }
  memPreview.Align := alClient;
  splMain.Align := alLeft;
  lvLog.Align := alLeft;
end;

procedure TfmAgentLog.Reload;
var
  NewItems: TObjectList;
  I: Integer;
  Item: TListItem;
  E: TAgentLogItem;
  Opened: Boolean;
  ErrMsg: string;
begin
  { 取库路径 / 打开库都可能因为环境问题抛异常，日志窗口不该因此崩掉 }
  Opened := False;
  ErrMsg := '';
  try
    Opened := AgentLog.EnsureOpen(ActiveAgentLogFile);
  except
    on E: Exception do
      ErrMsg := E.Message;
  end;

  if not Opened then
  begin
    lvLog.Items.Clear;             { 先断开对旧 item 的引用 }
    FItems.Clear;
    memPreview.Lines.Clear;
    if ErrMsg = '' then
      ErrMsg := AgentLog.LastError;
    lblInfo.Caption := Format('无法打开日志库：%s', [ErrMsg]);
    Exit;
  end;

  lvLog.Items.Clear;
  NewItems := AgentLog.ListRecent(AgentLogListLimit);
  FItems.Free;
  FItems := NewItems;

  lvLog.Items.BeginUpdate;
  try
    for I := 0 to FItems.Count - 1 do
    begin
      E := TAgentLogItem(FItems[I]);
      Item := lvLog.Items.Add;
      Item.Caption := E.CreatedAt;
      Item.SubItems.Add(ProjectText(E.Project));
      Item.SubItems.Add(LogStatusText(E.Status));
      Item.SubItems.Add(FormatDuration(E.DurationMs));
      Item.SubItems.Add(FirstLine(E.Prompt));
      Item.Data := E;
    end;
  finally
    lvLog.Items.EndUpdate;
  end;

  if FItems.Count > 0 then
    lvLog.ItemIndex := 0;
  ShowPreview(lvLog.ItemIndex);

  if AgentLog.FileName <> '' then
    lblInfo.Caption := Format('%d 条记录   |   %s', [FItems.Count, AgentLog.FileName])
  else
    lblInfo.Caption := Format('%d 条记录', [FItems.Count]);
end;

procedure TfmAgentLog.ShowPreview(AIndex: Integer);
var
  E: TAgentLogItem;
  CreatedAt, Prompt, Output, Status: string;
  Dur: Int64;
begin
  memPreview.Lines.BeginUpdate;
  try
    memPreview.Lines.Clear;
    if (AIndex < 0) or (AIndex >= FItems.Count) then Exit;

    E := TAgentLogItem(FItems[AIndex]);
    if not AgentLog.GetEntry(E.Id, CreatedAt, Prompt, Output, Status, Dur) then
    begin
      memPreview.Lines.Add(Format('无法读取日志 #%d：%s', [E.Id, AgentLog.LastError]));
      Exit;
    end;

    memPreview.Lines.Add(Format('==== 日志 #%d   %s   %s   工程 %s   耗时 %s ====',
      [E.Id, CreatedAt, LogStatusText(Status), ProjectText(E.Project),
       FormatDuration(Dur)]));
    memPreview.Lines.Add('');
    memPreview.Lines.Add('-------- Prompt --------');
    memPreview.Lines.Add(Prompt);
    memPreview.Lines.Add('');
    memPreview.Lines.Add('-------- Output --------');
    memPreview.Lines.Add(Output);
  finally
    memPreview.Lines.EndUpdate;
  end;
  memPreview.SelStart := 0;
end;

procedure TfmAgentLog.SetPicked(AIndex: Integer);
var
  E: TAgentLogItem;
  CreatedAt, Status: string;
  Dur: Int64;
begin
  if (AIndex < 0) or (AIndex >= FItems.Count) then
  begin
    MessageDlg('请先选中一条日志。', mtInformation, [mbOK], 0);
    Exit;
  end;

  E := TAgentLogItem(FItems[AIndex]);
  if not AgentLog.GetEntry(E.Id, CreatedAt, FPickedPrompt, FPickedOutput, Status, Dur) then
  begin
    MessageDlg(Format('读取日志失败：%s', [AgentLog.LastError]), mtError, [mbOK], 0);
    Exit;
  end;

  FPickedId := E.Id;
  ModalResult := mrOk;
end;

procedure TfmAgentLog.btnRefreshClick(Sender: TObject);
begin
  Reload;
end;

procedure TfmAgentLog.btnLoadClick(Sender: TObject);
begin
  SetPicked(lvLog.ItemIndex);
end;

procedure TfmAgentLog.btnDeleteClick(Sender: TObject);
var
  Idx: Integer;
begin
  Idx := lvLog.ItemIndex;
  if (Idx < 0) or (Idx >= FItems.Count) then Exit;
  if MessageDlg('确定删除选中的这条日志？', mtConfirmation, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  AgentLog.DeleteEntry(TAgentLogItem(FItems[Idx]).Id);
  Reload;
end;

procedure TfmAgentLog.btnClearClick(Sender: TObject);
begin
  if FItems.Count = 0 then Exit;
  if MessageDlg(Format('确定清空全部 %d 条日志？此操作不可撤销。', [FItems.Count]),
    mtWarning, [mbYes, mbNo], 0) <> mrYes then
    Exit;
  AgentLog.ClearAll;
  Reload;
end;

procedure TfmAgentLog.btnCloseClick(Sender: TObject);
begin
  ModalResult := mrCancel;
end;

procedure TfmAgentLog.lvLogSelectItem(Sender: TObject; Item: TListItem;
  Selected: Boolean);
begin
  if Selected then
    ShowPreview(Item.Index);
end;

procedure TfmAgentLog.lvLogDblClick(Sender: TObject);
begin
  SetPicked(lvLog.ItemIndex);
end;

{ ---------------- 单例 ---------------- }

var
  GAgentLog: TAgentLog = nil;

function AgentLog: TAgentLog;
begin
  if GAgentLog = nil then
    GAgentLog := TAgentLog.Create;
  Result := GAgentLog;
end;

initialization

finalization
  FreeAndNil(GAgentLog);

end.
