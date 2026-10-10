{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit PasClawIDEPlugin;

{$warn 5023 off : no warning about unused units}
interface

uses
  PasClawReg, PasClawSession, PasClawChatWindow, PasClawConfig, 
  PasClawSettingsDlg, PasClawAgentLog, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('PasClawReg', @PasClawReg.Register);
end;

initialization
  RegisterPackage('PasClawIDEPlugin', @Register);
end.
