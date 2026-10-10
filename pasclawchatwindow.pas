unit PasClawChatWindow;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls, ComCtrls, ExtCtrls, Dialogs,
  PasClawSession;

type
  TfmPasClawChat = class(TForm)
  private
    FSessionCounter: Integer;
    pcSessions: TPageControl;
    pnlToolbar: TPanel;
    btnNewTab: TButton;
    btnCloseTab: TButton;
    procedure BuildUI;
    function  CreateSession(const ACaption: string): TSessionFrame;
    procedure CloseCurrentSession;
    procedure btnNewTabClick(Sender: TObject);
    procedure btnCloseTabClick(Sender: TObject);
    procedure FormCloseHandler(Sender: TObject; var CloseAction: TCloseAction);
    procedure SessionTitleChange(Sender: TObject);
    procedure pcSessionsMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
  public
    constructor Create(TheOwner: TComponent); override;
    destructor  Destroy; override;
    class function GetPosition: TPoint;
  end;

implementation

{ ---------------- 构造 / 析构 ---------------- }

constructor TfmPasClawChat.Create(TheOwner: TComponent);
begin
  inherited CreateNew(TheOwner);
  Caption := 'PasClaw AI Assistant';
  Width  := 820;
  Height := 580;
  FSessionCounter := 0;
  BuildUI;
  CreateSession('会话 1');
end;

destructor TfmPasClawChat.Destroy;
begin
  while pcSessions.PageCount > 0 do
  begin
    if pcSessions.Pages[0].ControlCount > 0 then
      pcSessions.Pages[0].Controls[0].Free;
    pcSessions.Pages[0].Free;
  end;
  inherited Destroy;
end;

procedure TfmPasClawChat.BuildUI;
begin
  pnlToolbar := TPanel.Create(Self);
  pnlToolbar.Parent := Self;
  pnlToolbar.Align := alTop;
  pnlToolbar.Height := 32;
  pnlToolbar.BevelOuter := bvNone;

  btnNewTab := TButton.Create(Self);
  btnNewTab.Parent := pnlToolbar;
  btnNewTab.Caption := '＋ 新建会话';
  btnNewTab.SetBounds(4, 4, 110, 24);
  btnNewTab.OnClick := @btnNewTabClick;

  btnCloseTab := TButton.Create(Self);
  btnCloseTab.Parent := pnlToolbar;
  btnCloseTab.Caption := '关闭当前';
  btnCloseTab.SetBounds(120, 4, 90, 24);
  btnCloseTab.OnClick := @btnCloseTabClick;

  pcSessions := TPageControl.Create(Self);
  pcSessions.Parent := Self;
  pcSessions.Align := alClient;
  pcSessions.OnMouseDown := @pcSessionsMouseDown;

  OnClose := @FormCloseHandler;
end;

class function TfmPasClawChat.GetPosition: TPoint;
begin
  Result := Point(200, 200);
end;

{ ---------------- 会话管理 ---------------- }

function TfmPasClawChat.CreateSession(const ACaption: string): TSessionFrame;
var
  Tab: TTabSheet;
begin
  Tab := pcSessions.AddTabSheet;
  Tab.Caption := ACaption;
  Tab.Hint := '双击可重命名此会话';

  Result := TSessionFrame.Create(Tab, ACaption);
  Result.Parent := Tab;
  Result.Align  := alClient;
  Result.OnTitleChange := @SessionTitleChange;
  Result.Show;

  pcSessions.ActivePage := Tab;
end;

procedure TfmPasClawChat.SessionTitleChange(Sender: TObject);
var
  Sess: TSessionFrame;
begin
  Sess := TSessionFrame(Sender);
  if Sess.Parent is TTabSheet then
    TTabSheet(Sess.Parent).Caption := Sess.TabCaption;
end;

{ ---------------- 双击 Tab 重命名 ---------------- }

procedure TfmPasClawChat.pcSessionsMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Idx: Integer;
  Tab: TTabSheet;
  Sess: TSessionFrame;
  NewName: string;
begin
  if not (ssDouble in Shift) then Exit;

  Idx := pcSessions.IndexOfTabAt(X, Y);
  if Idx < 0 then Exit;

  Tab := pcSessions.Pages[Idx];
  NewName := Tab.Caption;

  if InputQuery('重命名会话', '请输入新的会话标题：', NewName) then
  begin
    NewName := Trim(NewName);
    if NewName = '' then Exit;

    Tab.Caption := NewName;

    if Tab.ControlCount > 0 then
    begin
      Sess := TSessionFrame(Tab.Controls[0]);
      Sess.SetCaptionManual(NewName);
    end;
  end;
end;

procedure TfmPasClawChat.CloseCurrentSession;
var
  Tab: TTabSheet;
begin
  if pcSessions.PageCount <= 1 then
  begin
    ShowMessage('至少保留一个会话。');
    Exit;
  end;

  Tab := pcSessions.ActivePage;
  if Assigned(Tab) then
  begin
    if Tab.ControlCount > 0 then
      Tab.Controls[0].Free;
    Tab.Free;
  end;
end;

procedure TfmPasClawChat.btnNewTabClick(Sender: TObject);
begin
  Inc(FSessionCounter);
  CreateSession('会话 ' + IntToStr(FSessionCounter + 1));
end;

procedure TfmPasClawChat.btnCloseTabClick(Sender: TObject);
begin
  CloseCurrentSession;
end;

procedure TfmPasClawChat.FormCloseHandler(Sender: TObject;
  var CloseAction: TCloseAction);
begin
  CloseAction := caHide;
end;

end.
