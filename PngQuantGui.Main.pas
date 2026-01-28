unit PngQuantGui.Main;

interface

uses
  Winapi.Messages,
  Winapi.Windows,
  // Vcl
  Vcl.ActnList,
  Vcl.Controls,
  Vcl.Dialogs,
  Vcl.ExtCtrls,
  Vcl.Forms,
  Vcl.Graphics,
  Vcl.ImgList,
  // System
  System.Actions,
  System.Classes,
  System.ImageList,
  System.Math,
  System.StrUtils,
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Variants,
  // ACL
  ACL.Classes,
  ACL.FastCode,
  ACL.FileFormats.INI,
  ACL.Geometry,
  ACL.Graphics,
  ACL.Graphics.Ex,
  ACL.Graphics.Ex.Gdip,
  ACL.Graphics.Images,
  ACL.Threading,
  ACL.Threading.Pool,
  ACL.Timers,
  ACL.UI.Application,
  ACL.UI.Controls.ActivityIndicator,
  ACL.UI.Controls.Base,
  ACL.UI.Controls.BaseEditors,
  ACL.UI.Controls.Bevel,
  ACL.UI.Controls.Buttons,
  ACL.UI.Controls.CompoundControl,
  ACL.UI.Controls.GroupBox,
  ACL.UI.Controls.Labels,
  ACL.UI.Controls.Panel,
  ACL.UI.Controls.ScrollBox,
  ACL.UI.Controls.Slider,
  ACL.UI.Controls.SpinEdit,
  ACL.UI.Forms,
  ACL.UI.ImageList,
  ACL.Utils.Common,
  ACL.Utils.FileSystem,
  ACL.Utils.Shell;

type

  { TfrmMain }

  TfrmMain = class(TACLForm)
    Actions: TActionList;
    ActivityIndicator: TACLActivityIndicator;
    actSave: TAction;
    ApplicationController: TACLApplicationController;
    btnCancel: TACLButton;
    btnOK: TACLButton;
    btnViewDifferences: TACLButton;
    btnViewOriginal: TACLButton;
    bvlSeparator: TACLBevel;
    gbBottom: TACLPanel;
    gbPreview: TACLGroupBox;
    gbSettings: TACLGroupBox;
    ilImages: TACLImageList;
    ilImages125: TACLImageList;
    ilImages150: TACLImageList;
    ilImages200: TACLImageList;
    lbAbout: TACLLabel;
    lbMaxQuality: TACLLabel;
    lbMinQuality: TACLLabel;
    lbOptimization: TACLLabel;
    lbResultInfo: TACLFormattedLabel;
    lbPreviewZoom: TACLLabel;
    optChangeDelayTimer: TACLTimer;
    optMaxValue: TACLSlider;
    optMinValue: TACLSlider;
    optOptimization: TACLSlider;
    pbPreview: TPaintBox;
    sbPreview: TACLScrollBox;
    sePreviewZoom: TACLSpinEdit;

    procedure actSaveExecute(Sender: TObject);
    procedure actSaveUpdate(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnSwitchViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure btnSwitchViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure optChangeDelayTimerHandler(Sender: TObject);
    procedure optQualityChanged(Sender: TObject);
    procedure pbPreviewPaint(Sender: TObject);
    procedure sbPreviewMouseWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
    procedure sePreviewZoomChange(Sender: TObject);
  public const
    AppCaption = 'PNGQuant GUI';
  strict private
    FBackgroundTask: THandle;
    FImages: array [0..2] of TACLDib;
    FMaxDifference: Integer;
    FOptimizedImageSize: Int64;
    FOriginalImageSize: Int64;
    FSourceFileName: string;
    FTempFileName: string;
    FViewMode: Integer;

    function GetImage(const Index: Integer): TACLDib;
  protected
    function GetToolsPath: string; virtual;
    procedure ConfigLoad;
    procedure ConfigSave;
    procedure OnOptimized;
    procedure OptimizeImage;
    procedure DpiChanged; override;
    procedure SetViewMode(AValue: Integer);
    procedure UpdatePreview;
    procedure UpdateState;
    procedure UpdateStatistics;

    property ImageDifferences: TACLDib index 2 read GetImage;
    property ImageOptimized: TACLDib index 0 read GetImage;
    property ImageOriginal: TACLDib index 1 read GetImage;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Initialize(const AFileName: string);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

function OpenConfig: TACLIniFile;
begin
  Result := TACLIniFile.Create(acChangeFileExt(acSelfExeName, '.ini'));
end;

procedure ImportPngImage(ALayer: TACLDib; const AFileName: string);
begin
  with TACLImage.Create(AFileName) do
  try
    SaveToDib(ALayer);
//    ALayer.Resize(Width, Height);
//    ALayer.Reset;
//    Draw(ALayer.Canvas, ALayer.ClientRect);
  finally
    Free;
  end;
end;

function BuildImageDifferenceMap(AOptimized, AOriginal, ADifference: TACLDib): Byte;
var
  LColor: PACLPixel32;
  LColor1: PACLPixel32;
  LColor2: PACLPixel32;
  LColorCount: Integer;
begin
  Result := 0;
  if AOriginal.Empty then
    Exit;

  if (AOptimized.Width <> AOriginal.Width) or (AOptimized.Height <> AOriginal.Height) then
  begin
    ADifference.Resize(AOriginal.Width, AOriginal.Height);
    acFillRect(ADifference.Canvas, ADifference.ClientRect, TAlphaColors.Red);
    Exit(MaxByte);
  end;

  ADifference.Assign(AOriginal);

  // Make it lighten
  LColorCount := ADifference.ColorCount;
  LColor := ADifference.Colors;
  while LColorCount > 0 do
  begin
    LColor^.R := 255 - (255 - LColor^.R) div 4;
    LColor^.G := 255 - (255 - LColor^.G) div 4;
    LColor^.B := 255 - (255 - LColor^.B) div 4;
    Dec(LColorCount);
    Inc(LColor);
  end;

  // highligth the differences
  LColorCount := AOriginal.ColorCount;
  LColor  := ADifference.Colors;
  LColor2 := AOptimized.Colors;
  LColor1 := AOriginal.Colors;
  while LColorCount > 0 do
  begin
    if DWORD(LColor1^) <> DWORD(LColor2^) then // just a fast check
    begin
      Result := Max(Result, FastAbs(LColor1^.B - LColor2^.B));
      Result := Max(Result, FastAbs(LColor1^.R - LColor2^.R));
      Result := Max(Result, FastAbs(LColor1^.G - LColor2^.G));
      DWORD(LColor^) := $FFFF0000;
    end;
    Dec(LColorCount);
    Inc(LColor1);
    Inc(LColor2);
    Inc(LColor);
  end;
end;

{ TfrmMain }

constructor TfrmMain.Create(AOwner: TComponent);
begin
  for var I := Low(FImages) to High(FImages) do
    FImages[I] := TACLDib.Create;
  inherited;
  FTempFileName := acTempFileName('PNGQuantGUI');
  ConfigLoad;
end;

destructor TfrmMain.Destroy;
begin
  ConfigSave;
  if FBackgroundTask <> 0 then
    TaskDispatcher.Cancel(FBackgroundTask, True);
  for var I := Low(FImages) to High(FImages) do
    FreeAndNil(FImages[I]);
  acDeleteFile(FTempFileName);
  inherited;
end;

procedure TfrmMain.ConfigLoad;
var
  AConfig: TACLIniFile;
begin
  AConfig := OpenConfig;
  try
    optMaxValue.PositionAsInteger := AConfig.ReadInteger(
      'General', 'MaxQuality', Trunc(optMaxValue.OptionsValue.Default));
    optMinValue.PositionAsInteger := AConfig.ReadInteger(
      'General', 'MinQuality', Trunc(optMinValue.OptionsValue.Default));
    optOptimization.PositionAsInteger := AConfig.ReadInteger(
      'General', 'Optimization', Trunc(optOptimization.OptionsValue.Default));
    sePreviewZoom.Value := AConfig.ReadInteger('General', 'PreviewZoom', 100);
    LoadPosition(AConfig);
  finally
    AConfig.Free;
  end;
end;

procedure TfrmMain.ConfigSave;
var
  AConfig: TACLIniFile;
begin
  AConfig := OpenConfig;
  try
    AConfig.WriteInteger('General', 'MaxQuality', optMaxValue.PositionAsInteger);
    AConfig.WriteInteger('General', 'MinQuality', optMinValue.PositionAsInteger);
    AConfig.WriteInteger('General', 'Optimization', optOptimization.PositionAsInteger);
    AConfig.WriteInteger('General', 'PreviewZoom', sePreviewZoom.Value);
    SavePosition(AConfig);
  finally
    AConfig.Free;
  end;
end;

procedure TfrmMain.Initialize(const AFileName: string);
begin
  ImportPngImage(ImageOriginal, AFileName);
  ImageOptimized.Assign(ImageOriginal);
  Caption := AppCaption + ' - [' + AFileName + ']';
  FOriginalImageSize := acFileSize(AFileName);
  FOptimizedImageSize := 0;
  FSourceFileName := AFileName;
  FMaxDifference := 0;
  UpdateStatistics;
  UpdatePreview;
end;

procedure TfrmMain.OnOptimized;
begin
  UpdateStatistics;
  UpdatePreview;
  UpdateState;
end;

procedure TfrmMain.OptimizeImage;
const
  PngQuantCmdLine = '%spngquant.exe --force --ext= --strip --quality=%d-%d "%s"';
  OptiPngCmdLine = '%soptipng.exe -o%d "%s"';
var
  AOptimization: Integer;
  AMinQuality: Integer;
  AMaxQuality: Integer;
begin
  TaskDispatcher.Cancel(FBackgroundTask, True);
  AOptimization := optOptimization.PositionAsInteger;
  AMinQuality := Min(optMinValue.PositionAsInteger, optMaxValue.PositionAsInteger);
  AMaxQuality := Max(optMinValue.PositionAsInteger, optMaxValue.PositionAsInteger);
  FBackgroundTask := TaskDispatcher.Run(
    procedure (Callback: TACLTaskCancelCallback)
    begin
      try
        acCopyFile(FSourceFileName, FTempFileName, False);
        TACLProcess.Execute(Format(PngQuantCmdLine, [GetToolsPath, AMinQuality, AMaxQuality, FTempFileName]), [eoWaitForTerminate]);
        TACLProcess.Execute(Format(OptiPngCmdLine, [GetToolsPath, AOptimization, FTempFileName]), [eoWaitForTerminate]);
        ImportPngImage(ImageOptimized, FTempFileName);
        FMaxDifference := BuildImageDifferenceMap(ImageOptimized, ImageOriginal, ImageDifferences);
        FOptimizedImageSize := acFileSize(FTempFileName);
      finally
        FBackgroundTask := 0;
      end;
    end,
    OnOptimized, tmcmSync);
end;

procedure TfrmMain.DpiChanged;
begin
  inherited;
  UpdatePreview;
end;

procedure TfrmMain.SetViewMode(AValue: Integer);
begin
  FViewMode := EnsureRange(AValue, Low(FImages), High(FImages));
  case FViewMode of
    0: gbPreview.Caption := 'Preview';
    1: gbPreview.Caption := 'Preview - Original';
    2: gbPreview.Caption := 'Preview - Differences (' + IfThen(FMaxDifference > 0, 'Δ' + IntToStr(FMaxDifference), 'Equals') + ')';
  end;
  pbPreview.Invalidate;
end;

procedure TfrmMain.UpdateStatistics;
var
  B: TStringBuilder;
begin
  B := TStringBuilder.Create;
  try
    B.AppendLine('[b]Old Size[/b]: ' + IntToStr(FOriginalImageSize) + ' Bytes');
    if FOptimizedImageSize > 0 then
    begin
      B.AppendLine('[b]New Size[/b]: ' + IntToStr(FOptimizedImageSize) + ' Bytes');
      B.AppendLine('[b]Saved[/b]: ' + IntToStr(FOriginalImageSize - FOptimizedImageSize) + ' Bytes');
      B.AppendLine('[b]Compression[/b]: ' + FormatFloat('0.0', 100 * FOptimizedImageSize / Max(FOriginalImageSize, 1)) + ' %');
    end;
    lbResultInfo.Caption := B.ToString;
  finally
    B.Free;
  end;
end;

procedure TfrmMain.UpdatePreview;
var
  AZoomFactor: Integer;
begin
  AZoomFactor := sePreviewZoom.Value;
  pbPreview.SetBounds(pbPreview.Left, pbPreview.Top,
    MulDiv(ImageOriginal.Width, AZoomFactor, 100),
    MulDiv(ImageOriginal.Height, AZoomFactor, 100));
  pbPreview.Invalidate;
end;

procedure TfrmMain.UpdateState;
begin
  ActivityIndicator.Active := FBackgroundTask <> 0;
  ActivityIndicator.Visible := FBackgroundTask <> 0;
  lbResultInfo.Visible := FBackgroundTask = 0;
  btnViewDifferences.Enabled := FBackgroundTask = 0;
  btnViewOriginal.Enabled := FBackgroundTask = 0;
end;

function TfrmMain.GetImage(const Index: Integer): TACLDib;
begin
  Result := FImages[Index];
end;

function TfrmMain.GetToolsPath: string;
begin
  Result := acSelfPath;
end;

procedure TfrmMain.actSaveExecute(Sender: TObject);
begin
  if acFileExists(FTempFileName) then
  begin
    if (FOptimizedImageSize > 0) and (FOptimizedImageSize < FOriginalImageSize) then
    begin
      TACLRecycleBin.Delete(FSourceFileName); // Remove original file to recycle bin
      acCopyFile(FTempFileName, FSourceFileName, False);
    end;
    Close;
  end;
end;

procedure TfrmMain.actSaveUpdate(Sender: TObject);
begin
  actSave.Enabled := not optChangeDelayTimer.Enabled and (FBackgroundTask = 0);
end;

procedure TfrmMain.btnCancelClick(Sender: TObject);
begin
  Close;
end;

procedure TfrmMain.btnSwitchViewMouseDown(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    SetViewMode((Sender as TComponent).Tag);
end;

procedure TfrmMain.btnSwitchViewMouseUp(Sender: TObject;
  Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  SetViewMode(0);
end;

procedure TfrmMain.pbPreviewPaint(Sender: TObject);
begin
  GetImage(FViewMode).DrawBlend(pbPreview.Canvas, pbPreview.ClientRect, MaxByte, True);
end;

procedure TfrmMain.sbPreviewMouseWheel(Sender: TObject;
  Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  Handled := ssCtrl in Shift;
  if Handled then
    sePreviewZoom.Value := sePreviewZoom.Value +
      (WheelDelta div WHEEL_DELTA) * sePreviewZoom.OptionsValue.IncCount;
end;

procedure TfrmMain.optChangeDelayTimerHandler(Sender: TObject);
begin
  optChangeDelayTimer.Enabled := False;
  OptimizeImage;
  UpdateState;
end;

procedure TfrmMain.optQualityChanged(Sender: TObject);
begin
  optChangeDelayTimer.Restart;
end;

procedure TfrmMain.sePreviewZoomChange(Sender: TObject);
begin
  UpdatePreview;
end;

end.
