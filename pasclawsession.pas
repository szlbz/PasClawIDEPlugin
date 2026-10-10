unit PasClawSession;

{$mode objfpc}{$H+}
{$WARN 4105 OFF}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ExtCtrls, Dialogs,
  Process, LCLType, Clipbrd, Graphics, LConvEncoding,LazUTF8,
  SynEdit, SynEditTypes, SynHighlighterPas,ProjectIntf,
  SrcEditorIntf, LazIDEIntf, IDEIntf,
  PasClawConfig, PasClawAgentLog, PasClawSettingsDlg;

type
  TSessionFrame = class(TForm)
  private
    FProcess: TProcess;
    FTimer: TTimer;
    FByteBuffer: RawByteString;
    FTabCaption: string;
    FTitleLocked: Boolean;
    FOnTitleChange: TNotifyEvent;
    FHistory: TStringList;
    FHistoryFile: string;
    FHistoryNav: Integer;
    FHistoryDraft: string;
    FLogId: Integer;
    FLogStart: TDateTime;
    // UI
    pnlTop: TPanel;
    pnlBottom: TPanel;
    edtPrompt: TEdit;
    btnSend: TButton;
    btnSendSelection: TButton;
    btnInsert: TButton;
    btnCopy: TButton;
    btnClear: TButton;
    btnLog: TButton;
    btnSet: TButton;
    memOutput: TSynEdit;
    lblStatus: TLabel;

    procedure BuildUI;
    procedure SetupTimer;
    procedure SetBusy(ABusy: Boolean);
    procedure SetStatus(const S: string);
    function  GetEditorSelection: string;
    procedure StartPasClaw(const APrompt: string);
    procedure StopProcess;
    procedure OnTimerTick(Sender: TObject);
    procedure ProcessBytes(const NewBytes: RawByteString);
    procedure AppendStreamChunk(const S: string);
    procedure UpdateTitleFromPrompt(const APrompt: string);
    procedure InsertToEditor;
    function  GetProjectHistoryFile: string;
    procedure FinalizeLog(const AStatus: string);
    procedure ShowLogBrowser;
    procedure ShowSetForm;
    procedure LoadHistory;
    procedure AppendHistory(const APrompt: string);
    procedure NavigateHistory(ADelta: Integer);
    // 事件
    procedure btnSendClick(Sender: TObject);
    procedure btnSendSelectionClick(Sender: TObject);
    procedure btnInsertClick(Sender: TObject);
    procedure btnCopyClick(Sender: TObject);
    procedure btnClearClick(Sender: TObject);
    procedure btnLogClick(Sender: TObject);
    procedure btnSetClick(Sender: TObject);
    procedure edtPromptKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
  public
    constructor Create(AOwner: TComponent; const ATabCaption: string); reintroduce;
    destructor  Destroy; override;
    procedure SetCaptionManual(const AName: string);
    property TabCaption: string read FTabCaption;
    property OnTitleChange: TNotifyEvent read FOnTitleChange write FOnTitleChange;
  end;

implementation

const
  MaxTitleLen   = 28;
  HistoryFile   = '.pasclaw_history.txt';
  MaxHistoryMem = 200;

{ ---------------- 构造 / 析构 ---------------- }

constructor TSessionFrame.Create(AOwner: TComponent; const ATabCaption: string);
begin
  inherited CreateNew(AOwner);
  FTabCaption   := ATabCaption;
  FTitleLocked  := False;
  FByteBuffer   := '';
  FHistoryNav   := -1;
  FHistoryDraft := '';
  FLogId        := -1;
  FLogStart     := 0;
  FHistory      := TStringList.Create;
  BorderStyle   := bsNone;      // 作为子控件时无边框
  BuildUI;
  SetupTimer;
  memOutput.Lines.Add('');
  LoadHistory;
  SetStatus('就绪');
end;

destructor TSessionFrame.Destroy;
begin
  StopProcess;
  FreeAndNil(FHistory);
  inherited Destroy;
end;

{ ---------------- UI 构建 ---------------- }

procedure TSessionFrame.BuildUI;
begin
  pnlTop := TPanel.Create(Self);
  pnlTop.Parent := Self;
  pnlTop.Align := alTop;
  pnlTop.Height := 34;
  pnlTop.BevelOuter := bvNone;
  pnlTop.BorderSpacing.Around := 4;

  btnSend := TButton.Create(Self);
  btnSend.Parent := pnlTop;
  btnSend.Caption := '发送';
  btnSend.Align := alRight;
  btnSend.Width := 70;
  btnSend.OnClick := @btnSendClick;

  edtPrompt := TEdit.Create(Self);
  edtPrompt.Parent := pnlTop;
  edtPrompt.Align := alClient;
  edtPrompt.OnKeyDown := @edtPromptKeyDown;
  edtPrompt.Hint := '↑/↓ 翻阅历史 prompt';
  edtPrompt.ShowHint:=True;

  pnlBottom := TPanel.Create(Self);
  pnlBottom.Parent := Self;
  pnlBottom.Align := alBottom;
  pnlBottom.Height := 32;
  pnlBottom.BevelOuter := bvNone;

  btnSendSelection := TButton.Create(Self);
  btnSendSelection.Parent := pnlBottom;
  btnSendSelection.Caption := '发送选中代码';
  btnSendSelection.SetBounds(4, 4, 120, 24);
  btnSendSelection.OnClick := @btnSendSelectionClick;

  btnInsert := TButton.Create(Self);
  btnInsert.Parent := pnlBottom;
  btnInsert.Caption := '插入编辑器';
  btnInsert.SetBounds(130, 4, 95, 24);
  btnInsert.OnClick := @btnInsertClick;

  btnCopy := TButton.Create(Self);
  btnCopy.Parent := pnlBottom;
  btnCopy.Caption := '复制';
  btnCopy.SetBounds(230, 4, 60, 24);
  btnCopy.OnClick := @btnCopyClick;

  btnClear := TButton.Create(Self);
  btnClear.Parent := pnlBottom;
  btnClear.Caption := '清空';
  btnClear.SetBounds(295, 4, 60, 24);
  btnClear.OnClick := @btnClearClick;

  btnLog := TButton.Create(Self);
  btnLog.Parent := pnlBottom;
  btnLog.Caption := '日志';
  btnLog.SetBounds(360, 4, 60, 24);
  btnLog.OnClick := @btnLogClick;

  btnSet := TButton.Create(Self);
  btnSet.Parent := pnlBottom;
  btnSet.Caption := '设置';
  btnSet.SetBounds(425, 4, 60, 24);
  btnSet.OnClick := @btnSetClick;

  lblStatus := TLabel.Create(Self);
  lblStatus.Parent := pnlBottom;
  lblStatus.Caption := '就绪';
  lblStatus.SetBounds(490, 8, 320, 16);

  memOutput := TSynEdit.Create(Self);
  memOutput.Parent := Self;
  memOutput.Align := alClient;
  memOutput.ReadOnly := True;
  memOutput.Font.Name := 'Consolas';
  memOutput.Font.Size := 10;
  memOutput.Font.Color:=clBtnText;
  memOutput.Gutter.Parts[1].MarkupInfo.Foreground :=clBtnText;
  memOutput.Color:=clWindow;
  memOutput.Gutter.Visible := True;
  memOutput.Gutter.AutoSize := True;
  memOutput.Gutter.Color := clBtnFace;
  // 高亮器延迟到窗体显示后挂载，避免 IDE 启动早期初始化冲突
  memOutput.Options := memOutput.Options + [eoHideRightMargin];
end;

procedure TSessionFrame.SetupTimer;
begin
  FTimer := TTimer.Create(Self);
  FTimer.Interval := 50;
  FTimer.OnTimer := @OnTimerTick;
  FTimer.Enabled := False;
end;

{ ---------------- 状态控制 ---------------- }

procedure TSessionFrame.SetBusy(ABusy: Boolean);
begin
  btnSend.Enabled          := not ABusy;
  btnSendSelection.Enabled := not ABusy;
  btnInsert.Enabled        := not ABusy;
  btnCopy.Enabled          := not ABusy;
  btnClear.Enabled         := not ABusy;
  btnLog.Enabled           := not ABusy;
  btnSet.Enabled           := not ABusy;
  edtPrompt.Enabled        := not ABusy;
end;

procedure TSessionFrame.SetStatus(const S: string);
begin
  lblStatus.Caption := S;
end;

function TSessionFrame.GetEditorSelection: string;
var
  Editor: TSourceEditorInterface;
begin
  Result := '';
  Editor := SourceEditorManagerIntf.ActiveEditor;
  if Assigned(Editor) then
    Result := Editor.Selection;
end;

{ ---------------- 标题同步 ---------------- }

procedure TSessionFrame.UpdateTitleFromPrompt(const APrompt: string);
var
  S: string;
  I: Integer;
begin
  if FTitleLocked then Exit;
  FTitleLocked := True;

  S := '';
  for I := 1 to Length(APrompt) do
  begin
    if APrompt[I] in [#9, #10, #13, ' '] then
    begin
      if (S <> '') and (S[Length(S)] <> ' ') then
        S := S + ' ';
    end
    else
      S := S + APrompt[I];
  end;
  S := Trim(S);

  if S = '' then Exit;
  if Length(S) > MaxTitleLen then
    S := utf8Copy(S, 1, MaxTitleLen) + '…';

  FTabCaption := S;
  if Assigned(FOnTitleChange) then
    FOnTitleChange(Self);
end;

procedure TSessionFrame.SetCaptionManual(const AName: string);
begin
  FTabCaption  := AName;
  FTitleLocked := True;
end;

{ ---------------- 历史记录 ---------------- }

function TSessionFrame.GetProjectHistoryFile: string;
var
  Dir: string;
begin
  { 工程目录的判定与日志库共用 PasClawAgentLog.ActiveProjectDir }
  Dir := ActiveProjectDir;
  if Dir = '' then
    Exit('');
  Result := IncludeTrailingPathDelimiter(Dir) + HistoryFile;
end;

procedure TSessionFrame.LoadHistory;
var
  L: TStringList;
  I, StartIdx: Integer;
begin
  try
    FHistory.Clear;
    FHistoryFile := GetProjectHistoryFile;
    if (FHistoryFile = '') or (not FileExists(FHistoryFile)) then Exit;

    L := TStringList.Create;
    try
      try
        L.LoadFromFile(FHistoryFile);
      except
        Exit;
      end;
      StartIdx := 0;
      if L.Count > MaxHistoryMem then
        StartIdx := L.Count - MaxHistoryMem;
      for I := StartIdx to L.Count - 1 do
        FHistory.Add(L[I]);
    finally
      L.Free;
    end;
  except
    // 忽略历史加载失败
  end;
end;

procedure TSessionFrame.AppendHistory(const APrompt: string);
var
  F: TextFile;
  Line: string;
begin
  if (FHistory.Count = 0) or (FHistory[FHistory.Count - 1] <> APrompt) then
    FHistory.Add(APrompt);
  if FHistory.Count > MaxHistoryMem then
    FHistory.Delete(0);

  if FHistoryFile = '' then
    FHistoryFile := GetProjectHistoryFile;
  if FHistoryFile = '' then Exit;

  Line := StringReplace(APrompt, #13#10, '\n', [rfReplaceAll]);
  Line := StringReplace(Line, #10, '\n', [rfReplaceAll]);
  Line := StringReplace(Line, #13, '\n', [rfReplaceAll]);

  try
    AssignFile(F, FHistoryFile);
    if FileExists(FHistoryFile) then
      Append(F)
    else
      Rewrite(F);
    try
      WriteLn(F, Line);
    finally
      CloseFile(F);
    end;
  except
    // 静默忽略写盘失败
  end;
end;

procedure TSessionFrame.NavigateHistory(ADelta: Integer);
var
  NewIdx: Integer;
begin
  if FHistory.Count = 0 then Exit;

  if FHistoryNav = -1 then
  begin
    FHistoryDraft := edtPrompt.Text;
    NewIdx := FHistory.Count - 1;
  end
  else
    NewIdx := FHistoryNav + ADelta;

  if NewIdx < -1 then NewIdx := -1;
  if NewIdx > FHistory.Count - 1 then NewIdx := FHistory.Count - 1;

  FHistoryNav := NewIdx;
  if FHistoryNav = -1 then
    edtPrompt.Text := FHistoryDraft
  else
    edtPrompt.Text := FHistory[FHistoryNav];

  edtPrompt.SelStart := Length(edtPrompt.Text);
  edtPrompt.SelLength := 0;
end;

{ ---------------- 进程管理 ---------------- }

procedure TSessionFrame.StopProcess;
begin
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  if Assigned(FProcess) then
  begin
    if FProcess.Running then
      FProcess.Terminate(0);
    FreeAndNil(FProcess);
  end;
  FByteBuffer := '';
  { 进程被中断（关闭会话 / 启动失败）：已经收到的输出照样存档 }
  FinalizeLog(LogStatusCancelled);
end;

procedure TSessionFrame.StartPasClaw(const APrompt: string);
var
  Cfg: TPasClawIDESettings;
  ExePath, PasClawDir: string;
  I: Integer;
begin
  if Assigned(FProcess) and FProcess.Running then
  begin
    SetStatus('PasClaw 正在运行...');
    Exit;
  end;

  UpdateTitleFromPrompt(APrompt);
  AppendHistory(APrompt);
  FHistoryNav := -1;

  { 使用日志：prompt 先落一行（id 记下来），输出等会话结束时补写 }
  FLogStart := Now;
  FLogId    := -1;
  try
    if AgentLog.EnsureOpen(ActiveAgentLogFile) then
      FLogId := AgentLog.AddEntry(APrompt, ActiveProjectName);
  except
    FLogId := -1;   { 日志写不进去不影响正常对话 }
  end;

  { 目录来自 <pasclaw.exe 目录>\.pasclaw\ide-plugin.json（Tools > PasClaw Settings） }
  Cfg := PasClawSettings;
  PasClawDir := Cfg.EffectivePasClawDir;
  ExePath := ResolvePasClawExe(PasClawDir);
  //ShowMessage(ExePath);
  FByteBuffer := '';
  FProcess := TProcess.Create(nil);
  FProcess.Executable := ExePath;
  FProcess.Parameters.Add('agent');
  FProcess.Parameters.Add('-m');
  FProcess.Parameters.Add(APrompt);
  FProcess.Parameters.Add('--no-color');
  FProcess.Parameters.Add('status');
  FProcess.Parameters.Add('--max-iterations');
  FProcess.Parameters.Add('200');
  FProcess.Options := [poUsePipes, poStderrToOutPut, poNoConsole];

  { 工作目录：pasclaw.exe 所在目录 —— 那里放着 sqlite3.dll / webui.res 等
    运行时资源，也是 CLI 解析相对路径的基准。 }
  //if PasClawDir <> '' then
  //  FProcess.CurrentDirectory := PasClawDir
  //else
  //  FProcess.CurrentDirectory := ExtractFilePath(ExePath);

  { 把工具链目录通过环境变量交给 pasclaw：agent 在 IDE 里跑的 shell 命令
    （lazbuild / fpc）就能直接按名字调用，不用写绝对路径。 }
  //FProcess.Environment.Add('PASCLAW_IDE=1');
  //
  //if Cfg.EffectiveLazarusDir <> '' then
  //begin
  //  FProcess.Environment.Add('LAZARUS_DIR=' + Cfg.EffectiveLazarusDir);
  //  FProcess.Environment.Add('PASCLAW_LAZARUS_DIR=' + Cfg.EffectiveLazarusDir);
  //end;
  //
  //if Cfg.EffectiveFpcDir <> '' then
  //begin
  //  FProcess.Environment.Add('FPC_DIR=' + Cfg.EffectiveFpcDir);
  //  FProcess.Environment.Add('PASCLAW_FPC_DIR=' + Cfg.EffectiveFpcDir);
  //  { fpc.exe 在 bin\<cpu>-<os> 里，把这两个常见目录挂到 PATH 后面 }
  //  for I := 0 to FProcess.Environment.Count - 1 do
  //    if Pos('PATH=', UpperCase(FProcess.Environment[I])) = 1 then
  //    begin
  //      FProcess.Environment[I] := FProcess.Environment[I] + PathSeparator +
  //        IncludeTrailingPathDelimiter(Cfg.EffectiveFpcDir) + 'bin' + PathDelim +
  //        'x86_64-win64' + PathSeparator +
  //        IncludeTrailingPathDelimiter(Cfg.EffectiveFpcDir) + 'bin' + PathDelim +
  //        'i386-win32';
  //      Break;
  //    end;
  //end;
  //
  //if Cfg.EffectivePasClawDir <> '' then
  //  FProcess.Environment.Add('PASCLAW_DIR=' + Cfg.EffectivePasClawDir);

  SetBusy(True);
  memOutput.Lines.Add('>>> ' + APrompt);
  SetStatus('调用 PasClaw...');

  try
    FProcess.Execute;
    FTimer.Enabled := True;
  except
    on E: Exception do
    begin
      memOutput.Lines.Add('[错误] 无法启动 PasClaw：' + E.Message);
      if not FileExists(ExePath) then
        memOutput.Lines.Add('[提示] 未找到 ' + ExePath +
          '，请用菜单 Tools > PasClaw Settings 指定正确的目录。');
      SetStatus('错误');
      FinalizeLog(LogStatusError);
      StopProcess;
      SetBusy(False);
    end;
  end;
end;

{ ---------------- 流式读取核心 ---------------- }

function SanitizeUnicode(const S: string): string;
begin
  Result := S;
  Exit;
  Result := StringReplace(Result, '✓', '[OK]', [rfReplaceAll]);
  Result := StringReplace(Result, '✗', '[X]',  [rfReplaceAll]);
  Result := StringReplace(Result, '→', '->',   [rfReplaceAll]);
  Result := StringReplace(Result, '←', '<-',   [rfReplaceAll]);
  Result := StringReplace(Result, '•', '* ',   [rfReplaceAll]);
  //Result := StringReplace(Result, '█', '#',    [rfReplaceAll]);
  Result := StringReplace(Result, '│', '|',    [rfReplaceAll]);
  Result := StringReplace(Result, '─', '-',    [rfReplaceAll]);
  Result := StringReplace(Result, '📄', '[doc]', [rfReplaceAll]);
  Result := StringReplace(Result, '🔧', '[tool]', [rfReplaceAll]);
  Result := StringReplace(Result, '⚠', '[!]',  [rfReplaceAll]);
  Result := StringReplace(Result, '×', 'x',    [rfReplaceAll]);
end;

//Synedit不支持转义字符，清除字符串中的转义字符
function StripAnsiManual(const Input: string): string;
var
  i: Integer;
  InEscape: Boolean;
begin
  Result := '''';
  InEscape := False;
  i := 1;
  while i <= Length(Input) do
  begin
    if (Input[i] = #27) then // #27 就是 ESC 字符
    begin
      InEscape := True;
      Inc(i);
      Continue;
    end;
    if InEscape then
    begin
      // 转义序列的结束字母通常在 A-Z 或 a-z 之间 (比如 m, H, J)
      // 也可能是 @ 等
        if (Input[i] >= 'A') and (Input[i] <= 'Z') or
         (Input[i] >= 'a') and (Input[i] <= 'z') then
        InEscape := False;
      Inc(i);
      Continue;
    end;
    // 不是转义码的部分，保留下来
    Result := Result + Input[i];
    Inc(i);
  end;
end;

procedure TSessionFrame.OnTimerTick(Sender: TObject);
var
  BytesRead: LongInt;
  Raw: RawByteString;

begin
  if not Assigned(FProcess) then
  begin
    FTimer.Enabled := False;
    Exit;
  end;

  while FProcess.Output.NumBytesAvailable > 0 do
  begin
    SetLength(Raw, 4096);
    BytesRead := FProcess.Output.Read(Raw[1], Length(Raw));
    if BytesRead > 0 then
    begin
      SetLength(Raw, BytesRead);
      ProcessBytes(Raw);
    end;
  end;

  if (not FProcess.Running) and (FProcess.Output.NumBytesAvailable = 0) then
  begin
    FByteBuffer:=SanitizeUnicode(FByteBuffer);
    if FByteBuffer <> '' then
    begin
      AppendStreamChunk(StripAnsiManual({$ifdef windows11}CP936ToUTF8({$endif}FByteBuffer));
      FByteBuffer := '';
    end;
    AppendStreamChunk('会话结束...');
    FTimer.Enabled := False;
    SetStatus('就绪');
    SetBusy(False);
    memOutput.Lines.Add('');
    FinalizeLog(LogStatusDone);
    FreeAndNil(FProcess);
  end;
end;

procedure TSessionFrame.ProcessBytes(const NewBytes: RawByteString);
var
  AllBytes: RawByteString;
  CompletePart, Remaining: RawByteString;
  CutPos, I, Need: Integer;
begin
  AllBytes := FByteBuffer + NewBytes;
  if AllBytes = '' then Exit;

  CutPos := Length(AllBytes) + 1;
  I := Length(AllBytes);
  while I >= 1 do
  begin
    if (Ord(AllBytes[I]) and $C0) <> $80 then
    begin
      if (Ord(AllBytes[I]) and $80) = 0 then
        Need := 1
      else if (Ord(AllBytes[I]) and $E0) = $C0 then
        Need := 2
      else if (Ord(AllBytes[I]) and $F0) = $E0 then
        Need := 3
      else if (Ord(AllBytes[I]) and $F8) = $F0 then
        Need := 4
      else
        Need := 1;
      CutPos := I + Need;
      Break;
    end;
    Dec(I);
  end;

  if CutPos > Length(AllBytes) then
    CutPos := Length(AllBytes) + 1;

  CompletePart := Copy(AllBytes, 1, CutPos - 1);
  Remaining    := Copy(AllBytes, CutPos, MaxInt);
  FByteBuffer  := Remaining;
  CompletePart:=SanitizeUnicode(CompletePart);
  if CompletePart <> '' then
    AppendStreamChunk(StripAnsiManual({$ifdef windows11}CP936ToUTF8({$endif}CompletePart));
end;

procedure TSessionFrame.AppendStreamChunk(const S: string);
var
  I: Integer;
  LastIdx: Integer;
  str:String;
begin
  str:=SanitizeUnicode(S);
  if str = '' then Exit;

  memOutput.Lines.BeginUpdate;
  try
    for I := 1 to Length(str) do
    begin
      if str[I] = #10 then
        memOutput.Lines.Add('')
      else if str[I] <> #13 then
      begin
        LastIdx := memOutput.Lines.Count - 1;
        memOutput.Lines[LastIdx] := memOutput.Lines[LastIdx] + str[I];
      end;
    end;
  finally
    memOutput.Lines.EndUpdate;
  end;

  if memOutput.Lines.Count > 0 then
  begin
    memOutput.CaretY := memOutput.Lines.Count;
    memOutput.CaretX := Length(memOutput.Lines[memOutput.Lines.Count - 1]) + 1;
    memOutput.EnsureCursorPosVisible;
  end;
end;

{ ---------------- 使用日志 ---------------- }

procedure TSessionFrame.FinalizeLog(const AStatus: string);
var
  Id: Integer;
  Dur: Int64;
begin
  Id := FLogId;
  FLogId := -1;          { 先清掉，重复调用是空操作 }
  if Id < 0 then Exit;

  Dur := Round((Now - FLogStart) * 86400000);   { 毫秒 }
  if Dur < 0 then Dur := 0;
  try
    AgentLog.UpdateEntry(Id, memOutput.Text, AStatus, Dur);
  except
    { 忽略 }
  end;
end;

procedure TSessionFrame.ShowLogBrowser;
var
  Dlg: TfmAgentLog;
begin
  Dlg := TfmAgentLog.Create(Self);
  try
    if Dlg.ShowModal <> mrOk then Exit;

    edtPrompt.Text := Dlg.PickedPrompt;
    memOutput.Text := Dlg.PickedOutput;
    if memOutput.Lines.Count = 0 then
      memOutput.Lines.Add('');
    memOutput.CaretY := memOutput.Lines.Count;
    memOutput.CaretX := Length(memOutput.Lines[memOutput.Lines.Count - 1]) + 1;
    memOutput.EnsureCursorPosVisible;
    FHistoryNav := -1;
    SetStatus('已载入日志 #' + IntToStr(Dlg.PickedId));
  finally
    Dlg.Free;
  end;
end;

procedure TSessionFrame.ShowSetForm;
var
  Dlg: TfmPasClawSettings;
begin
  Dlg := TfmPasClawSettings.Create(Self);
  try
    Dlg.LoadFromSettings;
    if Dlg.ShowModal <> mrOk then Exit;

  finally
    Dlg.Free;
  end;
end;

{ ---------------- 反向插入编辑器 ---------------- }

procedure TSessionFrame.InsertToEditor;
var
  Editor: TSourceEditorInterface;
  SynEd: TSynEdit;
  TextToInsert: string;
begin
  if memOutput.SelAvail then
    TextToInsert := memOutput.SelText
  else
    TextToInsert := memOutput.Text;

  if Trim(TextToInsert) = '' then
  begin
    ShowMessage('没有可插入的内容。');
    Exit;
  end;

  Editor := SourceEditorManagerIntf.ActiveEditor;
  if not Assigned(Editor) then
  begin
    ShowMessage('当前没有活动的编辑器窗口。');
    Exit;
  end;

  if Editor.EditorControl is TSynEdit then
  begin
    SynEd := TSynEdit(Editor.EditorControl);
    if SynEd.SelAvail then
      SynEd.SelText := TextToInsert
    else
      SynEd.InsertTextAtCaret(TextToInsert);
    SetStatus('已插入到编辑器');
  end
  else
    SetStatus('当前编辑器不支持直接插入');
end;

{ ---------------- 事件 ---------------- }

procedure TSessionFrame.btnSendClick(Sender: TObject);
begin
  if Trim(edtPrompt.Text) = '' then Exit;
  memOutput.Clear;
  memOutput.Lines.Add('');
  StartPasClaw(edtPrompt.Text);
  edtPrompt.Clear;
  FHistoryNav := -1;
end;

procedure TSessionFrame.btnSendSelectionClick(Sender: TObject);
var
  Sel: string;
begin
  Sel := GetEditorSelection;
  if Trim(Sel) = '' then
  begin
    memOutput.Lines.Add('[提示] 当前编辑器中没有选中文本。');
    Exit;
  end;
  StartPasClaw('请分析以下代码：' + sLineBreak + Sel);
end;

procedure TSessionFrame.btnInsertClick(Sender: TObject);
begin
  InsertToEditor;
end;

procedure TSessionFrame.btnCopyClick(Sender: TObject);
begin
  if memOutput.SelAvail then
    Clipboard.AsText := memOutput.SelText
  else
    Clipboard.AsText := memOutput.Text;
  SetStatus('已复制到剪贴板');
end;

procedure TSessionFrame.btnClearClick(Sender: TObject);
begin
  memOutput.Clear;
  memOutput.Lines.Add('');
end;

procedure TSessionFrame.btnLogClick(Sender: TObject);
begin
  ShowLogBrowser;
end;

procedure TSessionFrame.btnSetClick(Sender: TObject);
begin
  ShowSetForm;
end;

procedure TSessionFrame.edtPromptKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Shift = [] then
  begin
    case Key of
      VK_RETURN:
        begin
          btnSendClick(nil);
          Key := 0;
          Exit;
        end;
      VK_UP:
        begin
          NavigateHistory(-1);
          Key := 0;
          Exit;
        end;
      VK_DOWN:
        begin
          NavigateHistory(+1);
          Key := 0;
          Exit;
        end;
    end;
  end;
end;

end.
