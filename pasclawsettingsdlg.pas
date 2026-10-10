unit PasClawSettingsDlg;

{ PasClaw 插件的 IDE 设置对话框（纯代码构建，不用 .lfm 设计器）。

  两个标签页：
    工具链  PasClaw / Lazarus / FPC 三个目录，存 ide-plugin.json。
    代理    providers 列表（name / kind / api_base / api_key / model）
            与系统提示词 agents.defaults.systemPrompt；
            这两项由 PasClawConfig 写进 pasclaw 自己的
            <pasclaw.exe 目录>\.pasclaw\config.json。

  代理页上的 providers 是配置里列表的克隆：对话框里怎么改都不动全局设置，
  只有按下「保存」时才整份拷回去，所以「取消」没有副作用。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Graphics, LCLType,
  Forms, Controls, StdCtrls, ExtCtrls, ComCtrls, Dialogs, ButtonPanel,
  Contnrs,
  PasClawConfig;

type
  TfmPasClawSettings = class(TForm)
  private
    FSettings: TPasClawIDESettings;
    FExeName: string;

    { 两个页签。建控件的时候页签还是 0x0，所有尺寸都等页签
      真拿到大小之后由 LayoutXxxPage 重算，所以必须留引用。 }
    TsTool: TTabSheet;
    TsAgent: TTabSheet;

    { ---- 工具链页 ---- }
    edtPasClaw: TEdit;
    edtLazarus: TEdit;
    edtFpc: TEdit;
    pnlPasClaw: TPanel;
    pnlLazarus: TPanel;
    pnlFpc: TPanel;
    btnBrowsePasClaw: TButton;
    btnBrowseLazarus: TButton;
    btnBrowseFpc: TButton;
    btnAutoDetect: TButton;
    btnReset: TButton;
    lblJsonPath: TLabel;
    lblExeStatus: TLabel;
    lblLazStatus: TLabel;
    lblFpcStatus: TLabel;

    { ---- 代理页 ---- }
    grpProviders: TGroupBox;
    grpPrompt: TGroupBox;
    lbProviders: TListBox;
    edtProvName: TEdit;
    edtProvKind: TEdit;
    edtProvBase: TEdit;
    edtProvKey: TEdit;
    edtProvModel: TEdit;
    btnAddProvider: TButton;
    btnDelProvider: TButton;
    memSystemPrompt: TMemo;

    { providers 的工作副本（这里 owns TPasClawProvider） }
    FProviders: TObjectList;
    FProviderIndex: Integer;
    { 回填控件 / 重建列表期间为 True，用来抑制 OnChange、OnSelectionChange }
    FUpdating: Boolean;

    procedure BuildUI;
    procedure BuildToolchainPage(AParent: TWinControl);
    procedure BuildAgentPage(AParent: TWinControl);
    procedure BuildRow(AParent: TPanel; const ACaption, AHint: string;
      AEdit: TEdit; AButton: TButton; AStatus: TLabel);
    { 页签大小变了就整体重排（建控件时页签是 0x0，靠这一步纠正） }
    procedure SheetResize(Sender: TObject);
    procedure LayoutToolchainPage;
    procedure LayoutAgentPage;
    procedure RefreshStatus;

    procedure btnBrowsePasClawClick(Sender: TObject);
    procedure btnBrowseLazarusClick(Sender: TObject);
    procedure btnBrowseFpcClick(Sender: TObject);
    procedure btnAutoDetectClick(Sender: TObject);
    procedure btnResetClick(Sender: TObject);
    procedure EditChanged(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function  PickDir(const APrompt, ACurrent: string): string;
    { 用临时实例跑 AutoFillFrom，只把结果填回编辑框，绝不碰全局设置 }
    procedure ApplyAutoFill(const ASource: string);

    { ---- providers ---- }
    procedure LoadProviders;
    procedure RebuildProviderList;
    function  ProviderCaption(P: TPasClawProvider): string;
    procedure SelectProviderIndex(AIndex: Integer);
    procedure LoadFields(AIndex: Integer);
    procedure CommitFields(AIndex: Integer);
    procedure EnableProviderFields(AEnabled: Boolean);
    procedure lbProvidersSelectionChange(Sender: TObject; User: Boolean);
    procedure ProviderEditChanged(Sender: TObject);
    procedure btnAddProviderClick(Sender: TObject);
    procedure btnDelProviderClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    destructor  Destroy; override;
    procedure LoadFromSettings;
    procedure StoreToSettings;
  end;

{ 弹出设置对话框。模态返回 mrOk 时把结果写入配置并保存，
  保存失败会提示但不阻断。返回 True 表示用户确认了修改。 }
function ShowPasClawSettings(AOwner: TForm): Boolean;

implementation

const
  RowHeight = 58;
  LabelW    = 150;
  BrowseW   = 30;
  PadX      = 12;

function ShowPasClawSettings(AOwner: TForm): Boolean;
var
  Dlg: TfmPasClawSettings;
begin
  Dlg := TfmPasClawSettings.Create(AOwner);
  try
    Dlg.LoadFromSettings;
    Result := Dlg.ShowModal = mrOk;
    if Result then
    begin
      Dlg.StoreToSettings;
      if not PasClawSettings.Save then
        MessageDlg('PasClaw 设置',
          '配置已生效，但写入失败：' + sLineBreak + PasClawSettings.FileName,
          mtWarning, [mbOK], 0);
    end;
  finally
    Dlg.Free;
  end;
end;

{ ---------------- 构造 ---------------- }

constructor TfmPasClawSettings.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner);
  FSettings := PasClawSettings;
  FExeName  := Application.ExeName;
  FProviders := TObjectList.Create(True);
  FProviderIndex := -1;
  FUpdating := False;

  Caption   := 'PasClaw 设置';
  BorderStyle := bsSizeable;
  ClientWidth  := 640;
  ClientHeight := 520;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnShow := @FormShow;
  BuildUI;
end;

destructor TfmPasClawSettings.Destroy;
begin
  FreeAndNil(FProviders);
  inherited Destroy;
end;

procedure TfmPasClawSettings.BuildUI;
var
  Pages: TPageControl;
  B: TButtonPanel;
begin
  { 标签页撑满整块窗体，底部留给 ButtonPanel }
  Pages := TPageControl.Create(Self);
  Pages.Name := 'pages';
  Pages.Parent := Self;
  Pages.SetBounds(0, 0, ClientWidth, ClientHeight - 46);
  Pages.Anchors := [akLeft, akTop, akRight, akBottom];

  TsTool := TTabSheet.Create(Pages);
  TsTool.PageControl := Pages;
  TsTool.Name := 'tsToolchain';
  TsTool.Caption := '工具链';
  TsTool.OnResize := @SheetResize;

  TsAgent := TTabSheet.Create(Pages);
  TsAgent.PageControl := Pages;
  TsAgent.Name := 'tsAgent';
  TsAgent.Caption := '代理（providers / 提示词）';
  TsAgent.OnResize := @SheetResize;

  BuildToolchainPage(TsTool);
  BuildAgentPage(TsAgent);
  Pages.ActivePageIndex := 0;

  B := TButtonPanel.Create(Self);
  B.Parent := Self;
  B.Align := alBottom;
  B.ShowButtons := [pbOK, pbCancel];
  B.ShowGlyphs := [pbOK, pbCancel];
  B.OKButton.Caption := '保存';
  B.CancelButton.Caption := '取消';
end;

procedure TfmPasClawSettings.BuildToolchainPage(AParent: TWinControl);
begin
  { ---- PasClaw ---- }
  pnlPasClaw := TPanel.Create(Self);
  pnlPasClaw.Parent := AParent;
  pnlPasClaw.BevelOuter := bvNone;
  pnlPasClaw.Height := RowHeight;
  edtPasClaw := TEdit.Create(Self);
  edtPasClaw.Name := 'edtPasClaw';
  btnBrowsePasClaw := TButton.Create(Self);
  btnBrowseLazarus := TButton.Create(Self);
  btnBrowseFpc := TButton.Create(Self);
  lblExeStatus := TLabel.Create(Self);
  lblLazStatus := TLabel.Create(Self);
  lblFpcStatus := TLabel.Create(Self);
  btnBrowsePasClaw.Parent := pnlPasClaw;
  BuildRow(pnlPasClaw, 'PasClaw 程序所在目录',
    '内含 pasclaw.exe（也支持指向 pasclaw.exe / 其上级目录）',
    edtPasClaw, btnBrowsePasClaw, lblExeStatus);
  btnBrowsePasClaw.Hint := '浏览 PasClaw 目录';
  btnBrowsePasClaw.OnClick := @btnBrowsePasClawClick;

  { ---- Lazarus ---- }
  pnlLazarus := TPanel.Create(Self);
  pnlLazarus.Parent := AParent;
  pnlLazarus.BevelOuter := bvNone;
  pnlLazarus.Height := RowHeight;
  edtLazarus := TEdit.Create(Self);
  edtLazarus.Name := 'edtLazarus';
  btnBrowseLazarus.Parent := pnlLazarus;
  BuildRow(pnlLazarus, 'Lazarus 安装目录',
    '内含 lazbuild.exe / lazarus.exe',
    edtLazarus, btnBrowseLazarus, lblLazStatus);
  btnBrowseLazarus.Hint := '浏览 Lazarus 目录';
  btnBrowseLazarus.OnClick := @btnBrowseLazarusClick;

  { ---- FPC ---- }
  pnlFpc := TPanel.Create(Self);
  pnlFpc.Parent := AParent;
  pnlFpc.BevelOuter := bvNone;
  pnlFpc.Height := RowHeight;
  edtFpc := TEdit.Create(Self);
  edtFpc.Name := 'edtFpc';
  btnBrowseFpc.Parent := pnlFpc;
  BuildRow(pnlFpc, 'FPC 编译器目录',
    '内含 bin\<cpu>-<os>\fpc.exe 与 units\',
    edtFpc, btnBrowseFpc, lblFpcStatus);
  btnBrowseFpc.Hint := '浏览 FPC 目录';
  btnBrowseFpc.OnClick := @btnBrowseFpcClick;

  { ---- 操作按钮 ---- }
  btnAutoDetect := TButton.Create(Self);
  btnAutoDetect.Parent := AParent;
  btnAutoDetect.Caption := '自动探测';
  btnAutoDetect.Width := 100;
  btnAutoDetect.Height := 26;
  btnAutoDetect.OnClick := @btnAutoDetectClick;

  btnReset := TButton.Create(Self);
  btnReset.Parent := AParent;
  btnReset.Caption := '全部留空';
  btnReset.Width := 100;
  btnReset.Height := 26;
  btnReset.OnClick := @btnResetClick;

  lblJsonPath := TLabel.Create(Self);
  lblJsonPath.Parent := AParent;
  lblJsonPath.Height := 56;
  lblJsonPath.AutoSize := true;
  lblJsonPath.WordWrap := True;
end;

{ 代理页：左边服务商列表，右边五个字段；下面是系统提示词 }
procedure TfmPasClawSettings.BuildAgentPage(AParent: TWinControl);
const
  FldLabelW = 64;
  FldHeight = 24;
  FldGap    = 30;
var
  Y, EditX, EditW: Integer;

  procedure PutLabel(const ACaption: string; ATop: Integer);
  var
    Lbl: TLabel;
  begin
    Lbl := TLabel.Create(Self);
    Lbl.Parent := grpProviders;
    Lbl.Caption := ACaption;
    Lbl.SetBounds(190, ATop + 5, FldLabelW, 16);
    Lbl.AutoSize := False;
  end;

  procedure PutField(AEdit: TEdit; ATop: Integer; const AHint: string);
  begin
    AEdit.Parent := grpProviders;
    AEdit.SetBounds(EditX, ATop, EditW, FldHeight);
    AEdit.Hint := AHint;
    AEdit.OnChange := @ProviderEditChanged;
  end;

begin
  { ---- providers ---- }
  grpProviders := TGroupBox.Create(Self);
  grpProviders.Name := 'grpProviders';
  grpProviders.Parent := AParent;
  grpProviders.Caption := '模型服务商（providers）';

  lbProviders := TListBox.Create(Self);
  lbProviders.Name := 'lbProviders';
  lbProviders.Parent := grpProviders;
  lbProviders.OnSelectionChange := @lbProvidersSelectionChange;

  btnAddProvider := TButton.Create(Self);
  btnAddProvider.Name := 'btnAddProvider';
  btnAddProvider.Parent := grpProviders;
  btnAddProvider.Caption := '新增';
  btnAddProvider.OnClick := @btnAddProviderClick;

  btnDelProvider := TButton.Create(Self);
  btnDelProvider.Name := 'btnDelProvider';
  btnDelProvider.Parent := grpProviders;
  btnDelProvider.Caption := '删除';
  btnDelProvider.OnClick := @btnDelProviderClick;

  EditX := 190 + FldLabelW + 6;
  EditW := 100;   { 占位；真正宽度由 LayoutAgentPage 按页签大小算 }

  Y := 20;
  PutLabel('名称', Y);
  edtProvName := TEdit.Create(Self);
  edtProvName.Name := 'edtProvName';
  PutField(edtProvName, Y, '服务商标识，对应 providers[].name');
  Inc(Y, FldGap);

  PutLabel('类型', Y);
  edtProvKind := TEdit.Create(Self);
  edtProvKind.Name := 'edtProvKind';
  PutField(edtProvKind, Y, 'providers[].kind，例如 openai / anthropic');
  Inc(Y, FldGap);

  PutLabel('接口地址', Y);
  edtProvBase := TEdit.Create(Self);
  edtProvBase.Name := 'edtProvBase';
  PutField(edtProvBase, Y, 'providers[].api_base，API 根地址');
  Inc(Y, FldGap);

  PutLabel('密钥', Y);
  edtProvKey := TEdit.Create(Self);
  edtProvKey.Name := 'edtProvKey';
  PutField(edtProvKey, Y, 'providers[].api_key');
  Inc(Y, FldGap);

  PutLabel('模型', Y);
  edtProvModel := TEdit.Create(Self);
  edtProvModel.Name := 'edtProvModel';
  PutField(edtProvModel, Y, 'providers[].model，默认模型名');

  { ---- systemPrompt ---- }
  grpPrompt := TGroupBox.Create(Self);
  grpPrompt.Name := 'grpPrompt';
  grpPrompt.Parent := AParent;
  grpPrompt.Caption := '系统提示词（agents.defaults.systemPrompt）';

  memSystemPrompt := TMemo.Create(Self);
  memSystemPrompt.Name := 'memSystemPrompt';
  memSystemPrompt.Parent := grpPrompt;
  memSystemPrompt.ScrollBars := ssBoth;
  memSystemPrompt.WordWrap := True;
end;

{ 一个"标题 + 说明 + 输入框 + 浏览按钮 + 状态行"的横向布局 }
procedure TfmPasClawSettings.BuildRow(AParent: TPanel;
  const ACaption, AHint: string; AEdit: TEdit; AButton: TButton;
  AStatus: TLabel);
var
  Lbl: TLabel;
  Sub: TLabel;
begin
  Lbl := TLabel.Create(Self);
  Lbl.Parent := AParent;
  Lbl.Caption := ACaption;
  Lbl.Font.Style := Lbl.Font.Style + [fsBold];
  Lbl.SetBounds(0, 4, LabelW, 16);
  Lbl.AutoSize := False;

  Sub := TLabel.Create(Self);
  Sub.Parent := AParent;
  Sub.Caption := AHint;
  Sub.Font.Color := clGrayText;
  Sub.SetBounds(0, 40, LabelW, 14);
  Sub.AutoSize := False;

  AEdit.Parent := AParent;
  { 位置/宽度留空，交给 LayoutToolchainPage（建行时父窗口还是 0 宽） }
  AEdit.SetBounds(LabelW + 4, 8, 60, 24);
  //AEdit.AutoSize := False;  // <--- 关键：强制关闭 Edit 的自动大小
  AEdit.OnChange := @EditChanged;
  AEdit.Hint := AHint;

  AButton.Parent := AParent;
  //AButton.AutoSize := False;
  AButton.Caption := '...';
  AButton.SetBounds(0, 8, BrowseW, 24);

  AStatus.Parent := AParent;
  AStatus.SetBounds(LabelW + 4, 36, 120, 16);
  AStatus.Font.Color := clGrayText;
  AStatus.Caption := '';

  Lbl.AnchorSideTop.Control := AEdit;
  Lbl.AnchorSideTop.Side := asrCenter;

end;

{ ---------------- 布局 ---------------- }

procedure TfmPasClawSettings.SheetResize(Sender: TObject);
begin
  if csDestroying in ComponentState then Exit;
  LayoutToolchainPage;
  LayoutAgentPage;
end;

procedure TfmPasClawSettings.LayoutToolchainPage;
const
  BtnW = 40;
var
  W, RW, RowTop: Integer;

  procedure Row(APanel: TPanel; AEdit: TEdit; AButton: TButton);
  begin
    APanel.SetBounds(PadX, APanel.Top, RW, RowHeight);
    AButton.SetBounds(RW - BtnW - 8, 8, BtnW, AEdit.Height);
    AButton. AnchorSideTop.Control := AEdit;
    AButton.AnchorSideTop.Side := asrCenter;

    //AEdit.Width := RW - (LabelW + 4) - BtnW - (rw-AButton.Left)-10;
    AEdit.AnchorSideRight.Control:=AButton;
    AEdit.BorderSpacing.Right := 5;
    AEdit.Anchors := [akTop, akLeft, akRight];

  end;

begin
  if (TsTool = nil) or (TsTool.ClientWidth < 320) then Exit;
  W := TsTool.ClientWidth;
  RW := W - PadX * 2;

  RowTop := 10;
  pnlPasClaw.Top := RowTop;
  Row(pnlPasClaw, edtPasClaw, btnBrowsePasClaw);
  Inc(RowTop, RowHeight + 8);

  pnlLazarus.Top := RowTop;
  Row(pnlLazarus, edtLazarus, btnBrowseLazarus);
  Inc(RowTop, RowHeight + 8);

  pnlFpc.Top := RowTop;
  Row(pnlFpc, edtFpc, btnBrowseFpc);
  Inc(RowTop, RowHeight + 6);

  btnAutoDetect.SetBounds(PadX, RowTop, 100, 26);
  btnReset.SetBounds(PadX + 108, RowTop, 100, 26);
  lblJsonPath.SetBounds(PadX + 220, RowTop + 6, RW - 220 - PadX, 56);
  lblJsonPath.AnchorSideTop.Control := btnReset;
  lblJsonPath.AnchorSideTop.Side := asrCenter;
end;

procedure TfmPasClawSettings.LayoutAgentPage;
const
  EditX     = 260;      { 字段编辑框的 x（相对分组框）= 190 + 标签宽 64 + 6 }
  ListW     = 168;
  BtnW      = 80;
  BtnH      = 26;
  ProvH     = 212;      { 服务商分组框的固定高度 }
  GapY      = 6;
var
  SW, SH, GH, H: Integer;
begin
  if (TsAgent = nil) or (TsAgent.ClientWidth < 320) then Exit;
  SW := TsAgent.ClientWidth;
  SH := TsAgent.ClientHeight;

  { 上：服务商列表 + 五个字段。
    分组框的最终高度由字段编辑框的实际高度决定，必须先定下来再摆列表/按钮：
    给 TGroupBox 赋 ClientHeight 会连带改 Height，后摆的话按钮按的是旧高度，
    会落到新客户区外面（实测差 1px）。 }
  grpProviders.SetBounds(8, GapY, SW - 16, ProvH);
  grpProviders.ClientHeight := edtProvModel.Top + edtProvModel.Height + 20;
  GH := grpProviders.ClientHeight;

  lbProviders.SetBounds(10, 20, ListW, GH - 20 - BtnH - 10);
  btnAddProvider.SetBounds(10, GH - BtnH - 4, BtnW, BtnH);
  btnDelProvider.SetBounds(10 + BtnW + 8, GH - BtnH - 4, BtnW, BtnH);

  { 字段编辑框只要宽度：Left/Top 建的时候已经定好 }
  edtProvName.Width := grpProviders.ClientWidth - EditX - 12;
  edtProvKind.Width := edtProvName.Width;
  edtProvBase.Width := edtProvName.Width;
  edtProvKey.Width  := edtProvName.Width;
  edtProvModel.Width := edtProvName.Width;
  edtProvName.Anchors := [akTop, akLeft, akRight];
  edtProvKind.Anchors := [akTop, akLeft, akRight];
  edtProvBase.Anchors := [akTop, akLeft, akRight];
  edtProvKey.Anchors := [akTop, akLeft, akRight];
  edtProvModel.Anchors := [akTop, akLeft, akRight];
  edtProvName.AnchorSideRight.Control := grpProviders;
  edtProvKind.AnchorSideRight.Control := grpProviders;
  edtProvBase.AnchorSideRight.Control := grpProviders;
  edtProvKey.AnchorSideRight.Control := grpProviders;
  edtProvModel.AnchorSideRight.Control := grpProviders;

  edtProvName.AnchorSideRight.Side :=asrRight;
  edtProvKind.AnchorSideRight.Side :=asrRight;
  edtProvBase.AnchorSideRight.Side :=asrRight;
  edtProvKey.AnchorSideRight.Side :=asrRight;
  edtProvModel.AnchorSideRight.Side :=asrRight;

  edtProvName.BorderSpacing.Right := 5;
  edtProvKind.BorderSpacing.Right := 5;
  edtProvBase.BorderSpacing.Right := 5;
  edtProvKey.BorderSpacing.Right := 5;
  edtProvModel.BorderSpacing.Right := 5;

  { 下：系统提示词，吃掉剩下的高度 }
  grpPrompt.Anchors := [akTop, akLeft, akRight, akBottom];
  grpPrompt.AnchorSideTop.Control := grpProviders;
  grpPrompt.AnchorSideTop.Side := asrBottom;
  grpPrompt.BorderSpacing.Top := 5;

  grpPrompt.AnchorSideLeft.Control := grpProviders;
  grpPrompt.AnchorSideLeft.Side := asrLeft;
  grpPrompt.BorderSpacing.Left := 0;

  grpPrompt.AnchorSideRight.Control := grpProviders;
  grpPrompt.AnchorSideRight.Side := asrRight;
  grpPrompt.BorderSpacing.Right := 0;

  grpPrompt.AnchorSideBottom.Control := TsAgent;
  grpPrompt.AnchorSideBottom.Side := asrBottom;
  grpPrompt.BorderSpacing.Bottom := 5;
  memSystemPrompt.Align:=alClient;
  //H := SH - GapY - ProvH - GapY - GapY;
  //if H < 80 then H := 80;
  //grpPrompt.SetBounds(8, GapY + ProvH + GapY, SW - 16, H);
  //memSystemPrompt.SetBounds(10, 20, grpPrompt.ClientWidth - 20,
  //  grpPrompt.ClientHeight - 30);
end;

{ ---------------- 载入 / 保存 ---------------- }

procedure TfmPasClawSettings.LoadFromSettings;
begin
  edtPasClaw.Text := FSettings.PasClawDir;
  edtLazarus.Text := FSettings.LazarusDir;
  edtFpc.Text     := FSettings.FpcDir;
  memSystemPrompt.Text := FSettings.SystemPrompt;
  LoadProviders;
  RefreshStatus;
end;

procedure TfmPasClawSettings.StoreToSettings;
var
  I: Integer;
  Src, Dst: TPasClawProvider;
begin
  { 编辑框里没回车确认的最后几个字符也要收进去 }
  CommitFields(FProviderIndex);

  FSettings.PasClawDir := Trim(edtPasClaw.Text);
  FSettings.LazarusDir := Trim(edtLazarus.Text);
  FSettings.FpcDir     := Trim(edtFpc.Text);
  FSettings.SystemPrompt := memSystemPrompt.Text;

  FSettings.ClearProviders;
  for I := 0 to FProviders.Count - 1 do
  begin
    Src := TPasClawProvider(FProviders[I]);
    { 点了「新增」但一个字没填的空项不写进配置文件 }
    if (Src.Name = '') and (Src.Kind = '') and (Src.ApiBase = '') and
       (Src.ApiKey = '') and (Src.Model = '') then
      Continue;
    Dst := FSettings.AddProvider;
    Dst.Assign(Src);
  end;
end;

procedure TfmPasClawSettings.EditChanged(Sender: TObject);
begin
  RefreshStatus;
end;

{ 只做"存在性"检查，不校验版本；这样用户先把目录填好、
  之后再去装工具链也能正常保存。 }
procedure TfmPasClawSettings.RefreshStatus;

  function HasAnyFile(const ADir: string; const ANames: array of string): Boolean;
  var
    I: Integer;
  begin
    Result := False;
    if (ADir = '') or (not DirectoryExists(ADir)) then Exit;
    for I := Low(ANames) to High(ANames) do
      if FileExists(IncludeTrailingPathDelimiter(ADir) + ANames[I]) then
        Exit(True);
  end;

  function CheckMark(Ok: Boolean): string;
  begin
    if Ok then Result := '  ✓' else Result := '  ✗';
  end;

var
  D: string;
begin
  { BuildUI 期间 OnChange 可能先于其余控件挂上，先挡住 }
  if (edtLazarus = nil) or (edtFpc = nil) or (lblExeStatus = nil) or
     (lblLazStatus = nil) or (lblFpcStatus = nil) or (lblJsonPath = nil) then
    Exit;

  D := Trim(edtPasClaw.Text);
  lblExeStatus.Caption := CheckMark((D <> '') and FileExists(FindPasClawExe(D)));

  D := Trim(edtLazarus.Text);
  lblLazStatus.Caption := CheckMark(HasAnyFile(D, ['lazbuild.exe', 'lazbuild',
                                                   'lazarus.exe']));

  D := Trim(edtFpc.Text);
  lblFpcStatus.Caption := CheckMark(HasAnyFile(D, ['bin\fpc.exe', 'fpc.exe',
                                                   'bin\x86_64-win64\fpc.exe']));

  lblJsonPath.Caption := '插件数据与 pasclaw 配置（同一目录，就在 pasclaw.exe 旁边）：' +
    sLineBreak + '  ' + FSettings.FileName +
    sLineBreak + '  ' + TPasClawIDESettings.DataFile(PluginLogName) +
    sLineBreak + '代理设置写入：' + FSettings.AgentConfigFile;
end;

{ ---------------- providers ---------------- }

procedure TfmPasClawSettings.LoadProviders;
var
  I: Integer;
begin
  FProviders.Clear;
  for I := 0 to FSettings.ProviderCount - 1 do
    FProviders.Add(FSettings.Providers[I].Clone);

  RebuildProviderList;
  if FProviders.Count > 0 then
    SelectProviderIndex(0)
  else
    SelectProviderIndex(-1);
end;

procedure TfmPasClawSettings.RebuildProviderList;
var
  I: Integer;
  Saved: Boolean;
begin
  Saved := FUpdating;
  FUpdating := True;
  try
    lbProviders.Items.BeginUpdate;
    try
      lbProviders.Items.Clear;
      for I := 0 to FProviders.Count - 1 do
        lbProviders.Items.Add(
          ProviderCaption(TPasClawProvider(FProviders[I])));
    finally
      lbProviders.Items.EndUpdate;
    end;
  finally
    FUpdating := Saved;
  end;
end;

function TfmPasClawSettings.ProviderCaption(P: TPasClawProvider): string;
begin
  Result := P.Name;
  if Result = '' then
    Result := '(未命名)';
  if P.Model <> '' then
    Result := Result + '  ·  ' + P.Model;
end;

procedure TfmPasClawSettings.SelectProviderIndex(AIndex: Integer);
var
  Saved: Boolean;
begin
  FProviderIndex := AIndex;
  Saved := FUpdating;
  FUpdating := True;
  try
    if (AIndex >= 0) and (AIndex < FProviders.Count) then
      lbProviders.ItemIndex := AIndex
    else
      lbProviders.ItemIndex := -1;
  finally
    FUpdating := Saved;
  end;
  LoadFields(AIndex);
end;

{ 把某个服务商的字段填进编辑框。回填过程中产生的 OnChange 必须屏蔽，
  否则「名称」一改就会把其余四个还是旧值的编辑框写进新选中的服务商。 }
procedure TfmPasClawSettings.LoadFields(AIndex: Integer);
var
  P: TPasClawProvider;
  Saved: Boolean;
begin
  Saved := FUpdating;
  FUpdating := True;
  try
    P := nil;
    if (AIndex >= 0) and (AIndex < FProviders.Count) then
      P := TPasClawProvider(FProviders[AIndex]);

    if P <> nil then
    begin
      edtProvName.Text  := P.Name;
      edtProvKind.Text  := P.Kind;
      edtProvBase.Text  := P.ApiBase;
      edtProvKey.Text   := P.ApiKey;
      edtProvModel.Text := P.Model;
    end
    else
    begin
      edtProvName.Text  := '';
      edtProvKind.Text  := '';
      edtProvBase.Text  := '';
      edtProvKey.Text   := '';
      edtProvModel.Text := '';
    end;
    EnableProviderFields(P <> nil);
  finally
    FUpdating := Saved;
  end;
end;

procedure TfmPasClawSettings.CommitFields(AIndex: Integer);
var
  P: TPasClawProvider;
begin
  if (AIndex < 0) or (AIndex >= FProviders.Count) then Exit;
  P := TPasClawProvider(FProviders[AIndex]);
  P.Name    := Trim(edtProvName.Text);
  P.Kind    := Trim(edtProvKind.Text);
  P.ApiBase := Trim(edtProvBase.Text);
  P.ApiKey  := Trim(edtProvKey.Text);
  P.Model   := Trim(edtProvModel.Text);
end;

procedure TfmPasClawSettings.EnableProviderFields(AEnabled: Boolean);
begin
  edtProvName.Enabled  := AEnabled;
  edtProvKind.Enabled  := AEnabled;
  edtProvBase.Enabled  := AEnabled;
  edtProvKey.Enabled   := AEnabled;
  edtProvModel.Enabled := AEnabled;
  btnDelProvider.Enabled := AEnabled;
end;

procedure TfmPasClawSettings.lbProvidersSelectionChange(Sender: TObject;
  User: Boolean);
var
  NewIndex: Integer;
begin
  if FUpdating then Exit;
  NewIndex := lbProviders.ItemIndex;
  if NewIndex = FProviderIndex then Exit;
  CommitFields(FProviderIndex);
  SelectProviderIndex(NewIndex);
end;

procedure TfmPasClawSettings.ProviderEditChanged(Sender: TObject);
var
  Saved: Boolean;
begin
  if FUpdating then Exit;
  if (FProviderIndex < 0) or (FProviderIndex >= FProviders.Count) then Exit;
  CommitFields(FProviderIndex);

  { 只改当前这一行的标题；整表重建会把选中项弄丢。
    更新单项文本有可能让控件把选中项重置掉（取决于控件集实现），
    所以这里屏蔽事件并把选中位置找回来。 }
  Saved := FUpdating;
  FUpdating := True;
  try
    lbProviders.Items[FProviderIndex] :=
      ProviderCaption(TPasClawProvider(FProviders[FProviderIndex]));
    if lbProviders.ItemIndex <> FProviderIndex then
      lbProviders.ItemIndex := FProviderIndex;
  finally
    FUpdating := Saved;
  end;
end;

procedure TfmPasClawSettings.btnAddProviderClick(Sender: TObject);
begin
  CommitFields(FProviderIndex);
  FProviders.Add(TPasClawProvider.Create);
  RebuildProviderList;
  SelectProviderIndex(FProviders.Count - 1);
  { 页签没显示时 SetFocus 会抛 EInvalidOperation，先问一句 }
  if edtProvName.CanFocus then
    edtProvName.SetFocus;
end;

procedure TfmPasClawSettings.btnDelProviderClick(Sender: TObject);
var
  I: Integer;
begin
  I := FProviderIndex;
  if (I < 0) or (I >= FProviders.Count) then Exit;
  FProviders.Delete(I);
  if I >= FProviders.Count then
    I := FProviders.Count - 1;
  RebuildProviderList;
  SelectProviderIndex(I);
end;

{ ---------------- 事件 ---------------- }

procedure TfmPasClawSettings.btnBrowsePasClawClick(Sender: TObject);
var
  D: string;
begin
  D := PickDir('选择 PasClaw 所在目录', edtPasClaw.Text);
  if D = '' then Exit;
  edtPasClaw.Text := D;
  ApplyAutoFill(D);
end;

procedure TfmPasClawSettings.btnBrowseLazarusClick(Sender: TObject);
var
  D: string;
begin
  D := PickDir('选择 Lazarus 安装目录', edtLazarus.Text);
  if D = '' then Exit;
  edtLazarus.Text := D;
  ApplyAutoFill(D);
end;

procedure TfmPasClawSettings.btnBrowseFpcClick(Sender: TObject);
var
  D: string;
begin
  D := PickDir('选择 FPC 安装目录', edtFpc.Text);
  if D = '' then Exit;
  edtFpc.Text := D;
  ApplyAutoFill(D);
end;

procedure TfmPasClawSettings.ApplyAutoFill(const ASource: string);
var
  Tmp: TPasClawIDESettings;
begin
  { 在临时实例上跑 AutoFillFrom：先把编辑框里的现有值塞进去，
    靠它"只补空项"的规则，既保留手填的值，又补全其余目录。
    这样点「...」不会污染全局设置，取消对话框也就真的什么都没改。 }
  Tmp := TPasClawIDESettings.Create;
  try
    Tmp.PasClawDir := Trim(edtPasClaw.Text);
    Tmp.LazarusDir := Trim(edtLazarus.Text);
    Tmp.FpcDir     := Trim(edtFpc.Text);
    Tmp.AutoFillFrom(ASource);
    edtPasClaw.Text := Tmp.PasClawDir;
    edtLazarus.Text := Tmp.LazarusDir;
    edtFpc.Text     := Tmp.FpcDir;
  finally
    Tmp.Free;
  end;
  RefreshStatus;
end;

procedure TfmPasClawSettings.btnAutoDetectClick(Sender: TObject);
var
  Tmp: TPasClawIDESettings;
begin
  { 用一个临时实例探测，不动 FSettings —— 取消时不会留下副作用 }
  Tmp := TPasClawIDESettings.Create;
  try
    if (Tmp.PasClawDir = '') and (Tmp.LazarusDir = '') and (Tmp.FpcDir = '') then
    begin
      MessageDlg('PasClaw 设置',
        '没有找到任何已安装的目录，请手动指定。', mtInformation, [mbOK], 0);
      Exit;
    end;
    edtPasClaw.Text := Tmp.PasClawDir;
    edtLazarus.Text := Tmp.LazarusDir;
    edtFpc.Text     := Tmp.FpcDir;
  finally
    Tmp.Free;
  end;
  RefreshStatus;
end;

procedure TfmPasClawSettings.btnResetClick(Sender: TObject);
begin
  edtPasClaw.Text := '';
  edtLazarus.Text := '';
  edtFpc.Text     := '';
  RefreshStatus;
end;

procedure TfmPasClawSettings.FormShow(Sender: TObject);
begin
  { 页签真正拿到大小是在显示之后，这里再排一次，别指望 OnResize 一定来 }
  LayoutToolchainPage;
  LayoutAgentPage;
  RefreshStatus;
end;

procedure TfmPasClawSettings.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    ModalResult := mrCancel;
    Key := 0;
  end;
end;

{ SelectDirectory 的封装：空路径时给一个合理的起始目录 }
function TfmPasClawSettings.PickDir(const APrompt, ACurrent: string): string;
var
  Start: string;
begin
  Result := '';
  Start := Trim(ACurrent);
  if (Start = '') or (not DirectoryExists(Start)) then
    Start := ExtractFileDir(FExeName);
  if not SelectDirectory(APrompt, Start, Result) then
    Result := '';
end;

end.
