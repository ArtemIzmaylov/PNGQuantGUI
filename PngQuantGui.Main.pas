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
  ACL.Classes.Timer,
  ACL.FastCode,
  ACL.FileFormats.INI,
  ACL.Geometry,
  ACL.Graphics.Ex,
  ACL.Graphics.Ex.Gdip,
  ACL.Graphics.Images,
  ACL.Threading,
  ACL.Threading.Pool,
  ACL.UI.Application,
  ACL.UI.Controls.ActivityIndicator,
  ACL.UI.Controls.BaseControls,
  ACL.UI.Controls.Bevel,
  ACL.UI.Controls.Buttons,
  ACL.UI.Controls.CompoundControl,
  ACL.UI.Controls.FormattedLabel,
  ACL.UI.Controls.GroupBox,
  ACL.UI.Controls.Labels,
  ACL.UI.Controls.Panel,
  ACL.UI.Controls.ScrollBox,
  ACL.UI.Controls.Slider,
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
    optChangeDelayTimer: TACLTimer;
    optMaxValue: TACLSlider;
    optMinValue: TACLSlider;
    optOptimization: TACLSlider;
    pbPreview: TPaintBox;
    sbPreview: TACLScrollBox;

    procedure actSaveExecute(Sender: TObject);
    procedure actSaveUpdate(Sender: TObject);
    procedure btnCancelClick(Sender: TObject);
    procedure btnSwitchViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure btnSwitchViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure optChangeDelayTimerHandler(Sender: TObject);
    procedure optQualityChanged(Sender: TObject);
    procedure pbPreviewPaint(Sender: TObject);
  public const
    AppCaption = 'PNGQuant GUI';
  strict private
    FBackgroundTask: THandle;
    FImages: array [0..2] of TACLBitmapLayer;
    FMaxDifference: Integer;
    FOptimizedImageSize: Int64;
    FOriginalImageSize: Int64;
    FSourceFileName: string;
    FTempFileName: string;
    FViewMode: Integer;

    function GetImage(const Index: Integer): TACLBitmapLayer;
  protected
    procedure ConfigLoad;
    procedure ConfigSave;
    procedure OnOptimized;
    procedure OptimizeImage;
    procedure ScaleFactorChanged; override;
    procedure SetViewMode(AValue: Integer);
    procedure UpdatePreview;
    procedure UpdateState;
    procedure UpdateStatistics;

    property ImageDifferences: TACLBitmapLayer index 2 read GetImage;
    property ImageOptimized: TACLBitmapLayer index 0 read GetImage;
    property ImageOriginal: TACLBitmapLayer index 1 read GetImage;
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

procedure ImportPngImage(ALayer: TACLBitmapLayer; const AFileName: string);
begin
  with TACLImage.Create(AFileName) do
  try
    ALayer.Resize(Width, Height);
    ALayer.Reset;
    Draw(ALayer.Handle, ALayer.ClientRect);
  finally
    Free;
  end;
end;

function BuildImageDifferenceMap(AOptimized, AOriginal, ADifference: TACLBitmapLayer): Byte;
var
  AColor: PRGBQuad;
  AColor1: PRGBQuad;
  AColor2: PRGBQuad;
  AColorCount: Integer;
begin
  Result := 0;
  if AOriginal.Empty then
    Exit;

  if (AOptimized.Width <> AOriginal.Width) or (AOptimized.Height <> AOriginal.Height) then
  begin
    ADifference.Resize(AOriginal.Width, AOriginal.Height);
    GpFillRect(ADifference.Handle, ADifference.ClientRect, TAlphaColors.Red);
    Exit(MaxByte);
  end;

  ADifference.Assign(AOriginal);

  // Make it lighten
  AColorCount := ADifference.ColorCount;
  AColor := @ADifference.Colors^[0];
  while AColorCount > 0 do
  begin
    AColor^.rgbRed   := 255 - (255 - AColor^.rgbRed)   div 4;
    AColor^.rgbGreen := 255 - (255 - AColor^.rgbGreen) div 4;
    AColor^.rgbBlue  := 255 - (255 - AColor^.rgbBlue)  div 4;
    Dec(AColorCount);
    Inc(AColor);
  end;

  // highligth the differences
  AColorCount := AOriginal.ColorCount;
  AColor  := @ADifference.Colors^[0];
  AColor2 := @AOptimized.Colors^[0];
  AColor1 := @AOriginal.Colors^[0];
  while AColorCount > 0 do
  begin
    if DWORD(AColor1^) <> DWORD(AColor2^) then // just a fast check
    begin
      Result := Max(Result, FastAbs(AColor1^.rgbBlue - AColor2^.rgbBlue));
      Result := Max(Result, FastAbs(AColor1^.rgbRed - AColor2^.rgbRed));
      Result := Max(Result, FastAbs(AColor1^.rgbGreen - AColor2^.rgbGreen));
      DWORD(AColor^) := $FFFF0000;
    end;
    Dec(AColorCount);
    Inc(AColor1);
    Inc(AColor2);
    Inc(AColor);
  end;
end;

{ TfrmMain }

constructor TfrmMain.Create(AOwner: TComponent);
begin
  for var I := Low(FImages) to High(FImages) do
    FImages[I] := TACLBitmapLayer.Create;
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
    LoadPosition(AConfig)
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
    SavePosition(AConfig);
  finally
    AConfig.Free;
  end;
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
        TProcessHelper.Execute(Format(PngQuantCmdLine, [acSelfPath, AMinQuality, AMaxQuality, FTempFileName]), [eoWaitForTerminate]);
        TProcessHelper.Execute(Format(OptiPngCmdLine, [acSelfPath, AOptimization, FTempFileName]), [eoWaitForTerminate]);
        ImportPngImage(ImageOptimized, FTempFileName);
        FMaxDifference := BuildImageDifferenceMap(ImageOptimized, ImageOriginal, ImageDifferences);
        FOptimizedImageSize := acFileSize(FTempFileName);
      finally
        FBackgroundTask := 0;
      end;
    end,
    OnOptimized, tmcmSync);
end;

procedure TfrmMain.ScaleFactorChanged;
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
begin
  pbPreview.SetBounds(pbPreview.Left, pbPreview.Top,
    ScaleFactor.Apply(ImageOriginal.Width),
    ScaleFactor.Apply(ImageOriginal.Height));
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

function TfrmMain.GetImage(const Index: Integer): TACLBitmapLayer;
begin
  Result := FImages[Index];
end;

procedure TfrmMain.actSaveExecute(Sender: TObject);
begin
  if acFileExists(FTempFileName) then
  begin
    if (FOptimizedImageSize > 0) and (FOptimizedImageSize < FOriginalImageSize) then
    begin
      ShellDeleteFile(FSourceFileName); // Remove original file to recycle bin
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

procedure TfrmMain.btnSwitchViewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    SetViewMode((Sender as TComponent).Tag);
end;

procedure TfrmMain.btnSwitchViewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  SetViewMode(0);
end;

procedure TfrmMain.pbPreviewPaint(Sender: TObject);
begin
  GetImage(FViewMode).DrawBlend(pbPreview.Canvas.Handle, pbPreview.ClientRect);
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

end.
