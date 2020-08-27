unit uMainForm;

{$mode objfpc}{$H+}

interface

{ TODO : compile and run }

uses
  Classes, SysUtils, DB, sqlite3conn, sqldb, Forms, Controls, Graphics, DBGrids, ActnList, ExtCtrls, StdCtrls, Grids,
  AsyncProcess, LazUTF8, uMenuItem, process;

type

  TFormMode = (FMNormal, FMCentral);

  { TMainForm }

  TMainForm = class(TForm)
    acList: TActionList;
    acDebug: TAction;
    acRun: TAction;
    acFind: TAction;
    acKeepOpen: TAction;
    acGlobalSearch: TAction;
    AsyncProcess1: TAsyncProcess;
    edFind: TEdit;
    MainGrid: TDBGrid;
    MainGridSubmenu: TDBGrid;
    MainGridShortCut: TDBGrid;
    MenuDS: TDataSource;
    MenuDB: TSQLite3Connection;
    MenuItemDS: TDataSource;
    pnlFind: TPanel;
    Process1: TProcess;
    SQLMenu: TSQLQuery;
    SQLMenuItems: TSQLQuery;
    SQLMenuItemsMaxWidth: TSQLQuery;
    SQLMenuItemsShortcut: TSQLQuery;
    SQLTransaction: TSQLTransaction;
    ThrTimer: TTimer;
    procedure acDebugExecute(Sender: TObject);
    Procedure acFindExecute(Sender: TObject);
    procedure acGlobalSearchExecute(Sender: TObject);
    procedure acGlobalSearchUpdate(Sender: TObject);
    Procedure acKeepOpenExecute(Sender: TObject);
    procedure acRunExecute(Sender: TObject);
    Procedure edFindKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure edFindKeyUp(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure FormActivate(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    Procedure FormDestroy(Sender: TObject);
    Procedure MainGridCellClick(Column: TColumn);
    Procedure MainGridDrawColumnCell(Sender: TObject; Const Rect: TRect; DataCol: Integer; Column: TColumn; State: TGridDrawState);
    Procedure MainGridKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure MainGridKeyPress(Sender: TObject; Var Key: char);
    Procedure MainGridKeyUp(Sender: TObject; Var Key: Word; Shift: TShiftState);
    Procedure MainGridSubmenuDrawColumnCell(Sender: TObject; Const Rect: TRect; DataCol: Integer; Column: TColumn; State: TGridDrawState);
    procedure SQLMenuAfterInsert(DataSet: TDataSet);
    procedure SQLMenuAfterScroll(DataSet: TDataSet);
    Procedure ThrTimerTimer(Sender: TObject);
  private
    FExtraParam: string;
    FFormMode: TFormMode;
    FRecNo: LongInt;
    FKeepOpen: Boolean;
    FKeyStop: Boolean;
    FSearchCount: LongInt;
    FLastResNo: Integer; // for navigation over separators
    FLastFind: String;
    Procedure AppDeactivate(Sender: TObject);
    Procedure closeFindPanel(Const aForce: Boolean = false);
    Procedure FindSwitch;
    Function GetMaxWidth: Integer;
    Function GetTextWidth(Const aText: String): Integer;
    function isExternalSearch: Boolean;
    function canExternalSearch: Boolean;
    Procedure LoadMenuFromLines(Const aLines: TStringList);
    Procedure LoadMenuFromProcess(Const aCmd: String);
    Procedure RunAsync(Const aCmd: string);
    Procedure setMenuShortcut(Const lId: String; aKeySet: String = '');
    Procedure SetSearchCount(Const aValue: LongInt);
    Procedure SetSeparatorRow(Const State: TGridDrawState; Const Column: TColumn; Const DataCol: Integer; Const Rect: TRect;
      Const aGrid: TDBGrid);
    Procedure showMenu;
    procedure SetFormSize;
    procedure NavigateUp;
    { private declarations }
  public
    function AddMenu(aName: string; aUpMenuId: longint; aCmd: string = ''; aPath: string = ''; aReloadInterval: integer = 0): integer;
    Function setActiveMenu(const aIdMenu: longint): Boolean;
    procedure AddMenuItem(var lMenuItemParser: TMenuItemParser);
    procedure LoadMenuFromFile(const aFile: string);

    Property FormMode: TFormMode Read FFormMode Write FFormMode;
    Property SearchCount: LongInt Read FSearchCount Write SetSearchCount;
    Property extraParam: string Read FExtraParam Write FExtraParam;
  end;

var
  MainForm: TMainForm;

implementation

uses strutils, debugForm, StreamIO, LCLType, Dialogs, lconvencoding;

{$R *.lfm}

{ TMainForm }

Procedure TMainForm.FormCreate(Sender: TObject);
begin
  MainForm.Constraints.MaxHeight := round(Screen.Height * 0.9);
  MainForm.Constraints.MaxWidth := round(Screen.Width * 0.9);

  FFormMode := FMNormal;
  // color

  // sure create DB
  MenuDB.Close;
  //DeleteFile('/tmp/debugMenu.db'); // uncoment only for developnet (real DB for object inspector and design in lazarus)
  //MenuDB.DatabaseName := '/tmp/debugMenu.db'; // uncoment only for developnet (real DB for object inspector and design in lazarus)
  MenuDB.DatabaseName := ':memory:';
  MenuDB.Open;
  MenuDB.ExecuteDirect('PRAGMA encoding="UTF-8"');
  MenuDB.ExecuteDirect('CREATE TABLE IF NOT EXISTS menu (id INTEGER PRIMARY KEY , upMenuId INTEGER, name NOT NULL, cmd, path, load INTEGER, reloadInterval INTEGER)');
  MenuDB.ExecuteDirect('CREATE TABLE IF NOT EXISTS menuItem (id INTEGER PRIMARY KEY , menuId INTEGER NOT NULL, itemType, name, search, shortcut, cmd, subMenuPath, subMenuCmd, subMenuReloadInterval INTEGER, subMenuId INTEGER, subMenuChar, width INTEGER DEFAULT 100, FOREIGN KEY(menuId) REFERENCES menu(id))');
  MenuDB.Transaction.Commit;

  SQLMenu.Active := True;
  SQLMenuItems.Active := True;

  // fill root menu
  AddMenu('ROOT', 0);
  SQLMenu.First;

  // commandline parameters
  if Application.HasOption('c', 'center') then
  begin
    MainForm.Width := 500; {TODO -oLebeda -cNone: umožnit zvolit}
    MainForm.Height := 563;
    MainForm.Position := poScreenCenter;
    MainForm.FormMode := FMCentral;
  end;

  if Application.HasOption('s', 'search') then
    MainForm.SearchCount := StrToInt(Application.GetOptionValue('s', 'search'))
  else
    MainForm.SearchCount := MainForm.Constraints.MaxHeight div MainGrid.DefaultRowHeight;

  if Application.HasOption('f', 'file') then
  begin
    SQLMenu.Edit;
    SQLMenu.FieldByName('path').AsString := Application.GetOptionValue('f', 'file');
    SQLMenu.CheckBrowseMode;
    LoadMenuFromFile(SQLMenu.FieldByName('path').AsString);
  end;

  if Application.HasOption('r', 'reload') then
  begin
    SQLMenu.Edit;
    SQLMenu.FieldByName('Load').AsInteger := -1;
    SQLMenu.FieldByName('reloadInterval').AsInteger := -1 * StrToInt(Application.GetOptionValue('r', 'reload'));
    SQLMenu.CheckBrowseMode;
  End;

  if Application.HasOption('p', 'process') then
  begin
    SQLMenu.Edit;
    SQLMenu.FieldByName('cmd').AsString := Application.GetOptionValue('p', 'process');
    SQLMenu.CheckBrowseMode;
    LoadMenuFromProcess(SQLMenu.FieldByName('cmd').AsString);
  end;

  if Application.HasOption('x', 'extra') then
    MainForm.extraParam := Application.GetOptionValue('x', 'extra');

  MenuDB.Transaction.Commit;

  // open grid data
  SQLMenu.Active := True;
  SQLMenu.First;

  MainGrid.DataSource.DataSet.Active := False;
  MainGrid.DataSource.DataSet.Active := True;

  if not Application.HasOption('k', 'keep') then
  begin
    Application.OnDeactivate:=@AppDeactivate;
    FKeepOpen := False;
  End
  else
    FKeepOpen := True;
end;

Procedure TMainForm.FormDestroy(Sender: TObject);
Begin

end;

Procedure TMainForm.AppDeactivate(Sender: TObject);
begin
  if not FKeepOpen then
    MainForm.Close;
end;

Procedure TMainForm.closeFindPanel(Const aForce: Boolean);
Begin
  if (edFind.Text <> '') or aForce then
  begin
    edFind.Text := '';
    showMenu;
    MainGrid.SetFocus;
    pnlFind.Visible := false;
  End;
End;

Procedure TMainForm.FindSwitch;
Begin
  if MainGrid.Focused then
    pnlFind.Visible := True
  else If Not pnlFind.Visible Then
    pnlFind.Visible := True
  Else If pnlFind.Visible And ((edFind.Text = '') or (edFind.Text = '*')) Then
  begin
    pnlFind.Visible := False;
    if (edFind.Text = '*') then
    begin
      edFind.Text := '';
      showMenu;
    end;
  end;

  If pnlFind.Visible And Not edFind.Focused Then
  Begin
    edFind.SetFocus;
  End
  Else
  Begin
    MainGrid.SetFocus;
  End;

  SetFormSize;
End;

Function TMainForm.GetMaxWidth: Integer;
Begin
  if SQLMenuItemsMaxWidth.Active and (SQLMenuItemsMaxWidth.RecordCount = 1) and not SQLMenuItemsMaxWidth.FieldByName('width').IsNull then
    Result := SQLMenuItemsMaxWidth.FieldByName('width').AsInteger + 10
  else
    Result := 500;
End;

Function TMainForm.GetTextWidth(Const aText: String): Integer;
var
  W: integer;
  BM: TBitmap;
Begin
  BM := TBitmap.Create;
  try
    BM.Canvas.Font := MainGrid.Font;
    W := BM.Canvas.TextWidth(aText);
  Finally
    BM.Free;
  End;

  Result := W + 8;
  //Result := Length(aText) * 30
End;

Function TMainForm.isExternalSearch: Boolean;
Var
  lReloadInterval: LongInt;
  lCmd: String;
  lDynCmd: SizeInt;
Begin
  lReloadInterval := SQLMenu.FieldByName('reloadInterval').AsInteger;
  lCmd := SQLMenu.FieldByName('cmd').AsString;
  lDynCmd := Pos('%s', lCmd);
  Result := (lReloadInterval < 0) And (lDynCmd > 0)
End;

Function TMainForm.canExternalSearch: Boolean;
Var
  lReloadInterval: LongInt;
  lCmd: String;
  lDynCmd: SizeInt;
Begin
  lReloadInterval := SQLMenu.FieldByName('reloadInterval').AsInteger;
  lCmd := SQLMenu.FieldByName('cmd').AsString;
  lDynCmd := Pos('%s', lCmd);
  Result := (lReloadInterval < 0) And (Length(edFind.Text) >= abs(lReloadInterval)) And (lDynCmd > 0)
End;

Procedure TMainForm.MainGridCellClick(Column: TColumn);
Begin
  acRun.Execute;
end;

Procedure TMainForm.MainGridDrawColumnCell(Sender: TObject; Const Rect: TRect; DataCol: Integer; Column: TColumn; State: TGridDrawState);
Begin
  SetSeparatorRow(State, Column, DataCol, Rect, MainGrid);
end;

Procedure TMainForm.MainGridSubmenuDrawColumnCell(Sender: TObject; Const Rect: TRect; DataCol: Integer; Column: TColumn;
  State: TGridDrawState);
Begin
  SetSeparatorRow(State, Column, DataCol, Rect, MainGridSubmenu);
end;

Procedure TMainForm.MainGridKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  // navigation over separators
  FLastResNo := SQLMenuItems.RecNo;

  if (Key = VK_Return) then
  begin
    FRecNo := SQLMenuItems.RecNo;
    SQLMenuItems.Prior; // ugly hack - enter goes to next
  End;
end;

Procedure TMainForm.MainGridKeyPress(Sender: TObject; Var Key: char);
Begin
  SQLMenuItemsShortcut.Close;
  SQLMenuItemsShortcut.ParamByName('idMenu').AsInteger := SQLMenu.FieldByName('id').AsInteger;
  SQLMenuItemsShortcut.ParamByName('shortcut').AsString := key;
  SQLMenuItemsShortcut.Open;

  if (SQLMenuItemsShortcut.RecordCount = 1) and SQLMenuItems.Locate('id', SQLMenuItemsShortcut.FieldByName('id').AsInteger, []) then
  begin
    acRun.Execute;
    key := #0;
  End
  else if (SQLMenuItemsShortcut.RecordCount > 1) then
  begin
    if not SQLMenuItems.EOF then
      SQLMenuItems.next
    else
      SQLMenuItems.first;

    while not SQLMenuItems.EOF do
    begin
      if SQLMenuItems.FieldByName('shortcut').AsString = key then
        exit;
      SQLMenuItems.Next;
    end;
    SQLMenuItems.Locate('shortcut', key, []);
  end
end;

Procedure TMainForm.MainGridKeyUp(Sender: TObject; Var Key: Word; Shift: TShiftState);
Var
  lItemType: TMenuItemType;
begin
  if SQLMenuItems.RecordCount > 0 then
    lItemType := strToMit(SQLMenuItems.FieldByName('itemType').AsString)
  else
    lItemType := MITNone;

  if (Key = VK_Return) and (FRecNo <> SQLMenuItems.RecNo) and (FRecNo > 0) then
  begin
    SQLMenuItems.RecNo := FRecNo;
  end;

  if (Key = VK_Return) or ((Key = VK_RIGHT) and (lItemType in [MITmenu, MITmenuprog, MITmenufile, MITmenuprogreload])) then
  begin
    if not FKeyStop then
    begin
      acRun.Execute;
    end
    else
    begin
      FKeyStop := false;
    end
  End
  else if ((Key = VK_LEFT) or (Key = VK_BACK) or (Key = VK_ESCAPE)) and (SQLMenu.FieldByName('upMenuId').AsInteger > 0) then
  begin
    NavigateUp
  End
  else if (Key = VK_ESCAPE) and (SQLMenu.FieldByName('upMenuId').AsInteger = 0) then
    MainForm.Close
  else if (key = VK_UP) and SQLMenuItems.BOF then
  begin
    SQLMenuItems.Last;
    FLastResNo := SQLMenuItems.RecNo + 1;
  end
  else if (key = VK_DOWN) and SQLMenuItems.EOF then
  begin
    SQLMenuItems.First;
    FLastResNo := SQLMenuItems.RecNo - 1;
  end;

  if (SQLMenuItems.RecordCount > 0) and (strToMit(SQLMenuItems.FieldByName('itemType').AsString) = MITseparator) then
    if SQLMenuItems.RecNo > FLastResNo then
      SQLMenuItems.Next
    else
      SQLMenuItems.Prior;
end;

Procedure TMainForm.acDebugExecute(Sender: TObject);
var
  lForm: TDebugForm;
begin
  lForm := TDebugForm.Create(self);
  try
    lForm.ShowModal;
  finally
    FreeAndNil(lForm);
  end;
end;

Procedure TMainForm.acFindExecute(Sender: TObject);
Begin
  FindSwitch;
end;

procedure TMainForm.acGlobalSearchExecute(Sender: TObject);
begin
  FindSwitch;
  If pnlFind.Visible And (edFind.Text = '') then
  begin
    edFind.Text := '*';
    edFind.SelStart := Length(edFind.Text);
  end;
end;

procedure TMainForm.acGlobalSearchUpdate(Sender: TObject);
begin
  (Sender as TAction).Enabled := not pnlFind.Visible;
end;

Procedure TMainForm.acKeepOpenExecute(Sender: TObject);
Begin
  FKeepOpen := not FKeepOpen;
  if FKeepOpen then
  begin
    Self.BorderStyle := bsDialog;
    Self.FormStyle := fsNormal;
  End
  else
  begin
    Self.BorderStyle := bsNone;
    Self.FormStyle := fsSystemStayOnTop;
  End;
end;

Procedure TMainForm.RunAsync(Const aCmd: string);
var
  sl, slCmd: TStringList;
  lParams, lCmd, lPath, l, s, lPreCmd: string;
  lExe: RawByteString;
Const
  BEGIN_SL = 0;
begin
  sl := TStringList.Create;
  try
    lPreCmd := ReplaceText(aCmd, '%s', extraParam);
    lPreCmd := ReplaceText(lPreCmd, '''', '"'); {TODO -oLebeda -cNone: ???? - not functional in all cases!!!}
    slCmd := tStringList.Create;
    slCmd.Delimiter := ' ';
    slCmd.DelimitedText := lPreCmd;
    lCmd := slCmd[BEGIN_SL];
    slCmd.Delete(BEGIN_SL);

    ////sl.StrictDelimiter := true;
    //sl.Delimiter := ' ';
    //sl.DelimitedText := lParams;
    //slCmd.AddStrings(sl);

    // expand path
    if FileExists(lCmd) then
      lExe := lCmd
    else
    begin
      lPath := GetEnvironmentVariable('PATH');
      lExe := ExeSearch(lCmd, lPath);

      {$IFDEF Windows}
      // on windows try search with extension .exe
      if lExe = '' then
         lExe := ExeSearch(lCmd + '.exe', lPath);
      {$ENDIF}
    End;

    //for s in slCmd do
    //  lParams := lParams + s;

    AsyncProcess1.Executable := lExe;
    AsyncProcess1.Parameters.Clear;
    AsyncProcess1.Parameters.AddStrings(slCmd);
    AsyncProcess1.Execute;

  finally
    FreeAndNil(slCmd);
    sl.Free;
  end;
end;

Procedure TMainForm.setMenuShortcut(Const lId: String; aKeySet: String = '');
Var
  lShCut: Char;
  s: Char;
  lMenuCount: LongInt;
Begin
  SQLMenuItems.First;
  While Not SQLMenuItems.EOF Do
  Begin
    If (SQLMenuItems.FieldByName('shortcut').AsString = '') And (strToMit(SQLMenuItems.FieldByName('itemType').AsString) <> MITseparator) Then
    Begin
      if Length(aKeySet) = 0 then
        aKeySet := SQLMenuItems.FieldByName('name').AsString;
      For s In aKeySet Do
      Begin
        lShCut := LowerCase(s);

        SQLMenuItemsShortcut.Close;
        SQLMenuItemsShortcut.ParamByName('idMenu').AsString := lId;
        SQLMenuItemsShortcut.ParamByName('shortcut').AsString := lShCut;
        SQLMenuItemsShortcut.Open;
        lMenuCount := SQLMenuItemsShortcut.RecordCount;

        If (lShCut <> '') And (lMenuCount = 0) And (lShCut In ['a' .. 'z', '0' .. '9']) Then
        Begin
          SQLMenuItems.Edit;
          SQLMenuItems.FieldByName('shortcut').AsString := lShCut;
          SQLMenuItems.CheckBrowseMode;
          SQLMenuItems.ApplyUpdates;
          break;
        End;
      End;
    End;
    SQLMenuItems.Next;
  End;
End;

Procedure TMainForm.SetSearchCount(Const aValue: LongInt);
Begin
  If FSearchCount = aValue Then Exit;
  FSearchCount := aValue;
End;

Procedure TMainForm.SetSeparatorRow(Const State: TGridDrawState; Const Column: TColumn; Const DataCol: Integer; Const Rect: TRect;
  Const aGrid: TDBGrid);
Begin
  If SQLMenuItems.Active And (SQLMenuItems.RecordCount > 0) Then
  Begin
    If strToMit(SQLMenuItems.FieldByName('itemType').AsString) = MITseparator Then
    Begin
      aGrid.Canvas.Font.Bold := true;
      aGrid.Canvas.Brush.Color := clSilver;

      aGrid.Canvas.FillRect(Rect);
      aGrid.DefaultDrawColumnCell(Rect, DataCol, Column, State);
    End;
  End;
End;

Procedure TMainForm.acRunExecute(Sender: TObject);
Var
  lItemType: TMenuItemType;
  lSubMenuId, lMenuItemId, lLoad, lReload, lTime, lInterval: LongInt;
begin
  lItemType := strToMit(SQLMenuItems.FieldByName('itemType').AsString);

  if lItemType in [MITprog, MITrunonce] then {TODO -oLebeda -cNone: for runonce check running program}
  begin
    RunAsync(SQLMenuItems.FieldByName('cmd').AsString);
    // AsyncProcess1.CommandLine := SQLMenuItems.FieldByName('cmd').AsString;
    //AsyncProcess1.Execute;
    if not FKeepOpen then
      MainForm.Close;
  End
  else if lItemType =  MITmenuprogreload then
  begin
    lSubMenuId := SQLMenuItems.FieldByName('subMenuId').AsInteger;
    lMenuItemId := SQLMenuItems.FieldByName('id').AsInteger;

    if lSubMenuId = 0 then
    begin
      // create menu
      lSubMenuId := AddMenu(
          SQLMenuItems.FieldByName('name').AsString,
          SQLMenu.FieldByName('id').AsInteger,
          SQLMenuItems.FieldByName('subMenuCmd').AsString,
          '',
          SQLMenuItems.FieldByName('subMenuReloadInterval').AsInteger
      );
      MenuDB.ExecuteDirect('update menuItem set subMenuId = ' + IntToStr(lSubMenuId) + ' where id = ' + IntToStr(lMenuItemId));
      LoadMenuFromProcess(SQLMenu.FieldByName('cmd').AsString);
    End
    else
    begin
      setActiveMenu(lSubMenuId);

      lLoad := SQLMenu.FieldByName('Load').AsInteger;
      lReload := SQLMenu.FieldByName('reloadInterval').AsInteger;
      lTime := DateTimeToTimeStamp(time).Time div 1000;
      lInterval := lTime - lLoad;
      if lInterval > lReload then
      begin
        MenuDB.ExecuteDirect('delete from menuItem where menuId = ' + IntToStr(lSubMenuId));
        LoadMenuFromProcess(SQLMenu.FieldByName('cmd').AsString);
      End;

    End;
    setActiveMenu(lSubMenuId); // reload after build
  End
  else if lItemType =  MITmenu then
  begin
    setActiveMenu(SQLMenuItems.FieldByName('subMenuId').AsInteger);
  End;

  closeFindPanel;
end;

Procedure TMainForm.edFindKeyDown(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  if (Key = VK_DOWN) then
  begin
    if SQLMenuItems.EOF then
      SQLMenuItems.First
    else
      SQLMenuItems.Next;

    //SQLMenuItems.First;
    //MainGrid.SetFocus;
    key := 0;
  End
  else if (Key = VK_UP) then
  begin
    if SQLMenuItems.BOF then
      SQLMenuItems.Last
    else
      SQLMenuItems.Prior;

    //SQLMenuItems.Last;
    //MainGrid.SetFocus;
    key := 0;
  End
  else if (Key = VK_Return) then
  begin
    //MainGrid.SetFocus;
    acRun.Execute;
    Key := 0;
  End;
  if (Key = VK_Return) then
    FKeyStop := True;
end;

Procedure TMainForm.edFindKeyUp(Sender: TObject; Var Key: Word; Shift: TShiftState);
Begin
  if (Key = VK_ESCAPE) then
  begin
    if SQLMenu.FieldByName('upMenuId').AsInteger = 0 then
      MainForm.Close;

    closeFindPanel(true);
    NavigateUp;
  End
  {TODO -oLebeda -cNone: realy???}
  //else if ((Key = VK_DELETE) or (Key = VK_BACK)) and (edFind.Text = '')  then
  //  acFind.Execute
  else if not((Key = VK_DOWN) or (Key = VK_UP) or (Key = VK_Return)) and (FLastFind <> edFind.Text) then
  begin
    if isExternalSearch then
    begin
      // restart timer
      ThrTimer.Enabled := false;
      ThrTimer.Enabled := True;
    End
    else
    begin
      showMenu;
      FLastFind := edFind.Text;
    End;
  End;
end;

Procedure TMainForm.FormActivate(Sender: TObject);
Begin
  {TODO -oLebeda -cNone: reload menu ??}
end;

Procedure TMainForm.SQLMenuAfterInsert(DataSet: TDataSet);
begin
  SQLMenu.FieldByName('Load').AsInteger := DateTimeToTimeStamp(time).Time div 1000;
end;

Procedure TMainForm.SQLMenuAfterScroll(DataSet: TDataSet);
begin
 if not SQLMenu.Modified then
    showMenu;
end;

Procedure TMainForm.ThrTimerTimer(Sender: TObject);
Begin
  showMenu;
  FLastFind := edFind.Text;
  ThrTimer.Enabled := False;
end;

Procedure TMainForm.LoadMenuFromLines(Const aLines: TStringList);
var
  lLine: String;
  i: integer;
  lMenuItemParser: TMenuItemParser;
begin
  // insert into menu
  for i := 0 to aLines.Count - 1 do
  begin
    lLine := Trim(aLines[i]);
    lLine := DelSpace1(lLine);
    if (lLine <> '') and (not AnsiStartsStr('#', lLine) or AnsiStartsStr('#!', lLine)) then
    begin
      if AnsiStartsStr('#!', lLine) then
        Delete(lLine, 1, 2);

      lMenuItemParser := TMenuItemParser.Create(lLine);
      try
        if not(lMenuItemParser.itemType in [MITEndMenu, MITNone]) then
          AddMenuItem(lMenuItemParser);
      finally
        FreeAndNil(lMenuItemParser);
      end;
    end;
  end;
end;

Procedure TMainForm.LoadMenuFromProcess(Const aCmd: String);
Var
  lSl: TStringList;
  j: Integer;
  //F:TextFile;
  F:TextFile;
  lLine: WideString;
  lVal, lEncCon, lEncDef: String;
  lExt, lCan: Boolean;
  c: WideChar;
Begin
  lExt := isExternalSearch;
  lCan := canExternalSearch;
  if not lExt or lCan then
  begin
    // load data from process
    //Process1.Options := [poWaitOnExit, poNoConsole, poUsePipes];
    Process1.CurrentDirectory := GetEnvironmentVariable('HOME');
    Process1.CommandLine := aCmd;
    Process1.Execute;

    lSl := TStringList.Create;
    Try
      //Process1.WaitOnExit;
      //lSl.LoadFromStream(Process1.Output);
      AssignStream(F, Process1.Output);
      Reset(F);
      while not Eof(F) do
      begin
        Readln(F, lLine);

        // ugly hack, but only works - for czech only :-(
        //{$IFDEF Windows}
        lVal := ReplaceStr(lLine, '├í', 'á');
        lVal := ReplaceStr(lVal, '─Ź', 'č');
        lVal := ReplaceStr(lVal, '─Ć', 'ď');
        lVal := ReplaceStr(lVal, '├ę', 'é');
        lVal := ReplaceStr(lVal, '─Ť', 'ě');
        lVal := ReplaceStr(lVal, '├ş', 'í');
        lVal := ReplaceStr(lVal, '┼ł', 'ň');
        lVal := ReplaceStr(lVal, '├│', 'ó');
        lVal := ReplaceStr(lVal, '┼Ö', 'ř');
        lVal := ReplaceStr(lVal, '┼í', 'š');
        lVal := ReplaceStr(lVal, '┼ą', 'ť');
        lVal := ReplaceStr(lVal, '├║', 'ú');
        lVal := ReplaceStr(lVal, '┼»', 'ů');
        lVal := ReplaceStr(lVal, '├Ż', 'ý');
        lVal := ReplaceStr(lVal, '┼ż', 'ž');
        lVal := ReplaceStr(lVal, '├ü', 'Á');
        lVal := ReplaceStr(lVal, '─î', 'Č');
        lVal := ReplaceStr(lVal, '─Ä', 'Ď');
        lVal := ReplaceStr(lVal, '├ë', 'É');
        lVal := ReplaceStr(lVal, '─Ü', 'Ě');
        lVal := ReplaceStr(lVal, '├Ź', 'Í');
        lVal := ReplaceStr(lVal, '┼ç', 'Ň');
        lVal := ReplaceStr(lVal, '├ô', 'Ó');
        lVal := ReplaceStr(lVal, '┼ś', 'Ř');
        lVal := ReplaceStr(lVal, '┼á', 'Š');
        lVal := ReplaceStr(lVal, '┼Ą', 'Ť');
        lVal := ReplaceStr(lVal, '├Ü', 'Ú');
        lVal := ReplaceStr(lVal, '┼«', 'Ů');
        lVal := ReplaceStr(lVal, '├Ł', 'Ý');
        lVal := ReplaceStr(lVal, '┼Ż', 'Ž');
        //{$ENDIF}

        lSl.Append(lVal);
        //ShowMessage(lSl[0]);
      End;
      CloseFile(F);

      LoadMenuFromLines(lSl);
      //lsl.SaveToFile('/tmp/menu.txt');

    Finally
      FreeAndNil(lSl);
    End;

  end;

  SQLMenu.Edit;
  SQLMenu.FieldByName('Load').AsInteger := DateTimeToTimeStamp(time).Time div 1000;
  SQLMenu.Post;
  SQLMenu.ApplyUpdates;
End;

Procedure TMainForm.showMenu;
Var
  lSql: String;
  lId, lCmd: String;
  lSearchText: String;
  lGlobalSearch: Boolean;
Begin
  // initialize local variables
  lGlobalSearch := false;
  lSearchText := '';

  // check global search
  if Length(edFind.Text) > 0 then
  begin
    if edFind.Text[1] = '*' then
    begin
      lGlobalSearch := true;
      lSearchText :=  copy(edFind.Text, 2, Integer.MaxValue);
    end
    else
    begin
      lGlobalSearch := false;
      lSearchText := edFind.Text;
    end
  end;


  // regenerate if reloadInterval < 0 and lSearchText and command contains %s
  if isExternalSearch and (lSearchText <> FLastFind) then
  begin
    MenuDB.ExecuteDirect('delete from menuItem where menuId = ' + SQLMenu.FieldByName('id').AsString);
    lCmd := ReplaceText(SQLMenu.FieldByName('cmd').AsString, '%s', '"' + lSearchText + '"');
    LoadMenuFromProcess(lCmd);

    SQLMenu.Edit;
    SQLMenu.FieldByName('Load').AsInteger := -1;
    SQLMenu.CheckBrowseMode;
    SQLMenu.ApplyUpdates;
  End;

  // open Main menu
  MenuItemDS.DataSet := nil;
  SQLMenuItems.Close;
  lId := SQLMenu.FieldByName('id').AsString;
  lSql := 'select id, menuId, itemType, name, search, shortcut, '
                     + ' cmd, subMenuPath, subMenuCmd, subMenuReloadInterval, subMenuId, subMenuChar, width '
                     + ' from menuItem where 1=1 ';

  if not lGlobalSearch then
    lSql := lSql + ' and menuId = ''' + lId + ''' ';

  If (lSearchText <> '') and not isExternalSearch Then
    lSql := lSql + ' and search like ''%' + lSearchText + '%'' ';

  lSql := lSql + ' Order by id';

  SQLMenuItems.SQL.Text := lSql;
  SQLMenuItems.Open;

  // open max width query
  SQLMenuItemsMaxWidth.Close;
  SQLMenuItemsMaxWidth.ParamByName('id').AsString := lId;
  SQLMenuItemsMaxWidth.Open;

  // fill implicit shortcut
  if FSearchCount > SQLMenuItems.RecordCount then
  begin
    setMenuShortcut(lId);
    setMenuShortcut(lId, 'abcdefghijklmnopqrstuvwxyz0123456789');
    SQLMenuItems.First;
  End;

  MenuItemDS.DataSet := SQLMenuItems;

  if (((FSearchCount > 0) and (FSearchCount <= SQLMenuItems.RecordCount)) or isExternalSearch) and (Not pnlFind.Visible) then
  begin
    // find panel visibility
    pnlFind.Visible := True;
    ActiveControl := edFind;
    if MainForm.CanFocus then
      edFind.SetFocus;
  End
  else

  if pnlFind.Visible then
    ActiveControl := edFind;

  // form size
  SetFormSize;
End;

Procedure TMainForm.SetFormSize;
var
  lHeight, lWidth: integer;
begin
  MainForm.Caption := SQLMenu.FieldByName('name').AsString;

  // height
  lHeight := MainGrid.DefaultRowHeight * SQLMenuItems.RecordCount + (2* MainForm.BorderWidth);

  if pnlFind.Visible then
    lHeight := lHeight + pnlFind.Height;

  if MainForm.Constraints.MaxHeight >= lHeight then
  begin
    MainGridSubmenu.ScrollBars := ssNone;
    MainForm.Constraints.MinHeight := lHeight;
  end
  else
    MainGridSubmenu.ScrollBars := ssAutoVertical;

  MainForm.Height := lHeight;

  // width
  lWidth := GetMaxWidth + MainGridSubmenu.Width + MainGridShortCut.Width + (2* MainForm.BorderWidth);
   MainForm.Width := lWidth;

  // centralization
  if FFormMode = FMCentral then
  begin
    Top := (Screen.Height div 2) - (MainForm.Height div 2);
    Left := (Screen.Width div 2) - (MainForm.Width div 2);;
  End;

  // mouse to menu if isn't
  if Mouse.CursorPos.Y < top then
    Mouse.CursorPos := Point(Mouse.CursorPos.X ,top +10);

  if Mouse.CursorPos.Y > (top + MainForm.Height) then
    Mouse.CursorPos := Point(Mouse.CursorPos.X , (top + MainForm.Height) - 10);
end;

Procedure TMainForm.NavigateUp;
Var
  lMenuId: LongInt;
Begin
  closeFindPanel;
  lMenuId := SQLMenu.FieldByName('id').AsInteger;
  setActiveMenu(SQLMenu.FieldByName('upMenuId').AsInteger);
  SQLMenuItems.Locate('subMenuId', lMenuId, []);
End;

Function TMainForm.AddMenu(aName: string; aUpMenuId: longint; aCmd: string; aPath: string; aReloadInterval: integer): integer;
begin
  SQLMenu.Insert;

  SQLMenu.FieldByName('name').AsString := aName;
  SQLMenu.FieldByName('upMenuId').AsInteger := aUpMenuID;
  SQLMenu.FieldByName('cmd').AsString := aCmd;
  SQLMenu.FieldByName('path').AsString := aPath;
  SQLMenu.FieldByName('reloadInterval').AsInteger := aReloadInterval;

  SQLMenu.Post;
  SQLMenu.ApplyUpdates;

  Result := SQLMenu.FieldByName('id').AsInteger;
end;

Function TMainForm.setActiveMenu(Const aIdMenu: longint): Boolean;
Begin
  Result := SQLMenu.Locate('id', aIdMenu, []);
End;

Procedure TMainForm.AddMenuItem(Var lMenuItemParser: TMenuItemParser);
begin
  SQLMenuItems.Insert;
  //id, menuId, itemType, name, search, shortcut, cmd, subMenuPath, subMenuCmd, subMenuReloadInterval, subMenuId, subMenuChar
  SQLMenuItems.FieldByName('menuId').AsInteger := lMenuItemParser.menuId;
  SQLMenuItems.FieldByName('itemType').AsString := MitToStr(lMenuItemParser.itemType);
  SQLMenuItems.FieldByName('name').AsWideString := lMenuItemParser.Name;
  SQLMenuItems.FieldByName('search').AsString := lMenuItemParser.search;
  SQLMenuItems.FieldByName('shortcut').AsString := lMenuItemParser.shortcut;
  SQLMenuItems.FieldByName('cmd').AsString := lMenuItemParser.cmd;
  SQLMenuItems.FieldByName('subMenuPath').AsString := lMenuItemParser.subMenuPath;
  SQLMenuItems.FieldByName('subMenuCmd').AsString := lMenuItemParser.subMenuCmd;
  SQLMenuItems.FieldByName('subMenuReloadInterval').AsInteger := lMenuItemParser.subMenuReloadInterval;
  SQLMenuItems.FieldByName('subMenuId').AsInteger := lMenuItemParser.subMenuId;
  SQLMenuItems.FieldByName('subMenuChar').AsString := lMenuItemParser.subMenuChar;
  SQLMenuItems.FieldByName('width').AsInteger := GetTextWidth(lMenuItemParser.Name);
  SQLMenuItems.Post;
  SQLMenuItems.ApplyUpdates;
end;

Procedure TMainForm.LoadMenuFromFile(Const aFile: string);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(aFile);
    LoadMenuFromLines(sl);
  finally
    FreeAndNil(sl);
  end;
end;

end.
