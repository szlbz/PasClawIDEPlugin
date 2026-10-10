unit PasClawReg;

{$mode objfpc}{$H+}

interface

uses
  LCLType,Classes, SysUtils, Forms, Dialogs,
  MenuIntf, IDECommands, IDEWindowIntf,
  LazIDEIntf,
  PasClawConfig, PasClawSettingsDlg, PasClawChatWindow;

procedure Register;

implementation

const
  PasClawWindowID = 'PasClawChatWindow';

var
  PasClawForm: TfmPasClawChat = nil;
  Handler: TObject = nil;
  MyPkgAICreator: TIDEWindowCreator; // set by Register procedure


type
  { 用一个类来承载命令处理方法，
    RegisterIDECommand 需要的是 procedure(TObject) of object，
    不能直接传全局过程。 }
  TPasClawCommandHandler = class
  public
    procedure ShowWindow(Sender: TObject);
    procedure ShowSettings(Sender: TObject);
  end;

procedure TPasClawCommandHandler.ShowWindow(Sender: TObject);
begin
  //if not Assigned(PasClawForm) then
  //  PasClawForm := TfmPasClawChat.Create(nil);
  //PasClawForm.Show;
  //PasClawForm.BringToFront;
  if not Assigned(PasClawForm) then
  begin
    PasClawForm := TfmPasClawChat.Create(nil);
  end;
  IDEWindowCreators.ShowForm(MyPkgAICreator.FormName,true);
  //PasClawForm.Show;
  //PasClawForm.BringToFront;
end;

procedure TPasClawCommandHandler.ShowSettings(Sender: TObject);
begin
  ShowPasClawSettings(nil);
end;

procedure CreateMyPkgAI(Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
begin
  // sanity check to avoid *****ing with another package that has registered a window with the same name
  if CompareText(aFormName, 'MyPkgAI1')<>0 then begin
    //DebugLn(['ERROR: CreateMyPkgAI: there is already a form with this name']);
    exit;
  end;
  IDEWindowCreators.CreateForm(AForm, TfmPasClawChat, DoDisableAutoSizing,
    LazarusIDE.OwningComponent);
  AForm.Name:=aFormName;
  PasClawForm:=AForm as TfmPasClawChat;
end;

procedure Register;
var
  CmdShow: TIDECommand;
  CmdSettings: TIDECommand;
  CmdHandler: TPasClawCommandHandler;
  Cat: TIDECommandCategory;
  Key: TIDEShortCut;  // 先声明快捷键变量
begin
  CmdHandler := TPasClawCommandHandler.Create;
  Handler := CmdHandler;

  // 创建分类
  Cat := IDECommandList.CreateCategory(
    nil,
    'PasClawCategory',
    'PasClaw AI Assistant',
    IDECmdScopeSrcEditOnly
  );

  // 构造快捷键记录
  Key := IDEShortCut(Ord('P'), [ssCtrl, ssShift], VK_UNKNOWN, []);

  // 关键：第4个参数是 Key，第5个是处理过程
  CmdShow := RegisterIDECommand(
    Cat,                                    // 1. 分类
    'PasClawShowChat',                      // 2. 名称
    'Open PasClaw Chat',                    // 3. 描述
    Key,                                    // 4. TIDEShortCut 类型
    @CmdHandler.ShowWindow                  // 5. 处理过程
  );

  // 注册菜单项
  RegisterIDEMenuCommand(
    itmSecondaryTools,
    'PasClawChat',
    'PasClaw AI Assistant',
    nil,
    nil,
    CmdShow,
    ''
  );
(*
  // 设置对话框：Tools > PasClaw Settings
  Key := IDEShortCut(VK_UNKNOWN, [], VK_UNKNOWN, []);
  CmdSettings := RegisterIDECommand(
    Cat,
    'PasClawShowSettings',
    'PasClaw Settings',
    Key,
    @CmdHandler.ShowSettings
  );

  RegisterIDEMenuCommand(
    itmSecondaryTools,
    'PasClawSettings',
    'PasClaw Settings...',
    nil,
    nil,
    CmdSettings,
    '配置 PasClaw / Lazarus / FPC 目录'
  );
*)
  //注册停靠窗口
  MyPkgAICreator:=IDEWindowCreators.Add(
    'MyPkgAI1',//唯一标识 注意：这个名称不能与form同名
    @CreateMyPkgAI, nil,
    '100', '100', '800', '600'  // default place at left=100, top=100, right=300, bottom=300
      // you can also define percentage values of screen or relative positions, see wiki
    );

end;

finalization
  FreePasClawSettings;

end.
