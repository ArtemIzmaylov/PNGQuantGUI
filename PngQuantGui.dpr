program PngQuantGui;

uses
  Vcl.Forms,
  ACL.UI.Dialogs,
  PngQuantGui.Main in 'PngQuantGui.Main.pas' {frmMain};

{$R *.res}

var
  AFileName: UnicodeString;
begin
  AFileName := ParamStr(1);
  if AFileName = '' then
    with TACLFileDialog.Create(nil) do
    try
      Title := TfrmMain.AppCaption + ': Select Image to Optimize';
      Filter := 'PNG Images (*.png;)|*.png;';
      if Execute(False) then
        AFileName := Files[0];
    finally
      Free;
    end;

  if AFileName <> '' then
  begin
    Application.Initialize;
    Application.MainFormOnTaskbar := True;
    Application.CreateForm(TfrmMain, frmMain);
    frmMain.Initialize(AFileName);
    Application.Run;
  end;
end.
