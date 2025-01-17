{
   Double Commander Components
   -------------------------------------------------------------------------
   Path edit class with auto complete feature

   Copyright (C) 2012-2022 Alexander Koblov (alexx2000@mail.ru)

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License as
   published by the Free Software Foundation; either version 2 of the
   License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program. If not, see <http://www.gnu.org/licenses/>.
}

unit KASPathEdit;

{$mode delphi}

interface

uses
  Classes, SysUtils, LResources, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ShellCtrls, LCLType, LCLVersion;

type

  { TKASPathEdit }

  TKASPathEdit = class(TEdit)
  private
    FKeyDown: Word;
    FBasePath: String;
    FListBox: TListBox;
    FPanel: THintWindow;
    FAutoComplete: Boolean;
    FStringList: TStringList;
    FObjectTypes: TObjectTypes;
    FFileSortType: TFileSortType;
  private
    procedure AutoComplete(const Path: String);
    procedure SetObjectTypes(const AValue: TObjectTypes);
    procedure FormChangeBoundsEvent(Sender: TObject);
    procedure ListBoxClick(Sender: TObject);
    procedure ListBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
  private
    procedure ShowListBox;
    procedure HideListBox;
  protected
{$IF DEFINED(LCLWIN32)}
    procedure CreateWnd; override;
{$ENDIF}
    procedure DoExit; override;
    procedure VisibleChanged; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUpAfterInterface(var Key: Word; Shift: TShiftState); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property ObjectTypes: TObjectTypes read FObjectTypes write SetObjectTypes;
    property FileSortType: TFileSortType read FFileSortType write FFileSortType;
  end;

procedure Register;

implementation

uses
  LazUTF8, Math, LazFileUtils, Masks
  {$IF DEFINED(LCLWIN32)}
  , ComObj
  {$ENDIF}
  {$IF DEFINED(MSWINDOWS)}
  , Windows
  {$ENDIF}
  ;

{$IF DEFINED(LCLWIN32)}

const
  SHACF_AUTOAPPEND_FORCE_ON  = $40000000;
  SHACF_AUTOSUGGEST_FORCE_ON = $10000000;
  SHACF_FILESYS_ONLY         = $00000010;
  SHACF_FILESYS_DIRS         = $00000020;

function SHAutoComplete(hwndEdit: HWND; dwFlags: DWORD): HRESULT; stdcall; external 'shlwapi.dll';

function SHAutoCompleteX(hwndEdit: HWND; ObjectTypes: TObjectTypes): Boolean;
var
  dwFlags: DWORD;
begin
  if (ObjectTypes = []) then Exit(False);
  dwFlags := SHACF_AUTOAPPEND_FORCE_ON or SHACF_AUTOSUGGEST_FORCE_ON;
  if (otNonFolders in ObjectTypes) then
    dwFlags := dwFlags or SHACF_FILESYS_ONLY
  else if (otFolders in ObjectTypes) then
    dwFlags := dwFlags or SHACF_FILESYS_DIRS;
  Result:= (SHAutoComplete(hwndEdit, dwFlags) = 0);
end;

{$ENDIF}

procedure Register;
begin
  RegisterComponents('KASComponents', [TKASPathEdit]);
end;

function FilesSortAlphabet(List: TStringList; Index1, Index2: Integer): Integer;
begin
  Result:= CompareFilenames(List[Index1], List[Index2]);
end;

function FilesSortFoldersFirst(List: TStringList; Index1, Index2: Integer): Integer;
var
  Attr1, Attr2: IntPtr;
begin
  Attr1:= IntPtr(List.Objects[Index1]);
  Attr2:= IntPtr(List.Objects[Index2]);
  if (Attr1 and faDirectory <> 0) and (Attr2 and faDirectory <> 0) then
    Result:= CompareFilenames(List[Index1], List[Index2])
  else begin
    if (Attr1 and faDirectory <> 0) then
      Result:= -1
    else begin
      Result:=  1;
    end;
  end;
end;

procedure GetFilesInDir(const ABaseDir: String; AMask: String; AObjectTypes: TObjectTypes;
                        AResult: TStringList; AFileSortType: TFileSortType);
var
  ExcludeAttr: Integer;
  SearchRec: TSearchRec;
{$IF DEFINED(MSWINDOWS)}
  ErrMode : LongWord;
{$ENDIF}
begin
{$IF DEFINED(MSWINDOWS)}
  ErrMode:= SetErrorMode(SEM_FAILCRITICALERRORS or SEM_NOALIGNMENTFAULTEXCEPT or SEM_NOGPFAULTERRORBOX or SEM_NOOPENFILEERRORBOX);
  try
{$ENDIF}
  if FindFirst(ABaseDir + AMask, faAnyFile, SearchRec) = 0 then
  begin
    ExcludeAttr:= 0;

    if not (otHidden in AObjectTypes) then
      ExcludeAttr:= ExcludeAttr or faHidden;
    if not (otFolders in AObjectTypes) then
      ExcludeAttr:= ExcludeAttr or faDirectory;

    repeat
      if (SearchRec.Attr and ExcludeAttr <> 0) then
        Continue;
      if (SearchRec.Name = '.') or (SearchRec.Name = '..')then
        Continue;
      if (SearchRec.Attr and faDirectory = 0) and not (otNonFolders in AObjectTypes) then
        Continue;

      AResult.AddObject(SearchRec.Name, TObject(IntPtr(SearchRec.Attr)));
    until FindNext(SearchRec) <> 0;

    if AResult.Count > 0 then
    begin
      case AFileSortType of
        fstAlphabet:     AResult.CustomSort(@FilesSortAlphabet);
        fstFoldersFirst: AResult.CustomSort(@FilesSortFoldersFirst);
      end;
    end;
  end;
  SysUtils.FindClose(SearchRec);
{$IF DEFINED(MSWINDOWS)}
  finally
    SetErrorMode(ErrMode);
  end;
{$ENDIF}
end;

{ TKASPathEdit }

procedure TKASPathEdit.AutoComplete(const Path: String);
{$IF LCL_FULLVERSION >= 2020000}
const
  AFlags: array[Boolean] of TMaskOptions = (
    [moDisableSets], [moDisableSets, moCaseSensitive]
  );
{$ENDIF}
var
  I: Integer;
  AMask: TMask;
  BasePath: String;
begin
  FListBox.Clear;
  if Pos(PathDelim, Path) = 0 then
    HideListBox
  else begin
    BasePath:= ExtractFilePath(Path);
    if CompareFilenames(FBasePath, BasePath) <> 0 then
    begin
      FStringList.Clear;
      FBasePath:= BasePath;
      GetFilesInDir(BasePath, AllFilesMask, FObjectTypes, FStringList, FFileSortType);
    end;
    if (FStringList.Count > 0) then
    begin
      FListBox.Items.BeginUpdate;
      try
        // Check mask and make absolute file name
        AMask:= TMask.Create(ExtractFileName(Path) + '*',
{$IF LCL_FULLVERSION >= 2020000}
                             AFlags[FileNameCaseSensitive]
{$ELSE}
                             FileNameCaseSensitive
{$ENDIF}
          );
        for I:= 0 to FStringList.Count - 1 do
        begin
          if AMask.Matches(FStringList[I]) then
            FListBox.Items.Add(BasePath + FStringList[I]);
        end;
        AMask.Free;
      finally
        FListBox.Items.EndUpdate;
      end;
      if FListBox.Items.Count > 0 then
      begin
        ShowListBox;
        // Calculate ListBox height
        with FListBox.ItemRect(0) do
        I:= Bottom - Top; // TListBox.ItemHeight sometimes don't work under GTK2
        with FListBox do
        begin
          if Items.Count = 1 then
            FPanel.ClientHeight:= Self.Height
          else
            FPanel.ClientHeight:= I * IfThen(Items.Count > 10, 11, Items.Count + 1);
        end;
      end;
    end;
  end;
end;

procedure TKASPathEdit.SetObjectTypes(const AValue: TObjectTypes);
begin
  if FObjectTypes = AValue then Exit;
  FObjectTypes:= AValue;
{$IF DEFINED(LCLWIN32)}
  if HandleAllocated then RecreateWnd(Self);
  if FAutoComplete then
{$ENDIF}
  FAutoComplete:= (FObjectTypes <> []);
end;

procedure TKASPathEdit.FormChangeBoundsEvent(Sender: TObject);
begin
  HideListBox;
end;

procedure TKASPathEdit.ListBoxClick(Sender: TObject);
begin
  if FListBox.ItemIndex >= 0 then
  begin
    Text:= FListBox.Items[FListBox.ItemIndex];
    SelStart:= UTF8Length(Text);
    HideListBox;
    SetFocus;
  end;
end;

procedure TKASPathEdit.ListBoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FListBox.ItemIndex:= FListBox.ItemAtPos(Classes.Point(X, Y), True);
end;

procedure TKASPathEdit.ShowListBox;
begin
  if (FPanel = nil) then
  begin
    FPanel:= THintWindow.Create(Self);
    FPanel.Color:= clDefault;
    FListBox.Parent:= FPanel;

    with Parent.ClientToScreen(CLasses.Point(Left, Top)) do
    begin
      FPanel.Left:= X;
      FPanel.Top:= Y + Height;
    end;

    FPanel.Width:= Width;
    FPanel.Visible:= True;

    Application.AddOnDeactivateHandler(FormChangeBoundsEvent, True);
    GetParentForm(Self).AddHandlerOnChangeBounds(FormChangeBoundsEvent, True);
  end;
end;

procedure TKASPathEdit.HideListBox;
begin
  if (FPanel <> nil) then
  begin
    FPanel.Visible:= False;
    FListBox.Parent:= nil;
    FreeAndNil(FPanel);
    Application.RemoveOnDeactivateHandler(FormChangeBoundsEvent);
    GetParentForm(Self).RemoveHandlerOnChangeBounds(FormChangeBoundsEvent);
  end;
end;

{$IF DEFINED(LCLWIN32)}

procedure TKASPathEdit.CreateWnd;
begin
  inherited CreateWnd;
  FAutoComplete:= not SHAutoCompleteX(Handle, FObjectTypes);
end;

{$ENDIF}

procedure TKASPathEdit.DoExit;
begin
  HideListBox;
  inherited DoExit;
end;

procedure TKASPathEdit.VisibleChanged;
begin
  FBasePath:= EmptyStr;
  inherited VisibleChanged;
end;

procedure TKASPathEdit.KeyDown(var Key: Word; Shift: TShiftState);
begin
  FKeyDown:= Key;
  case Key of
    VK_ESCAPE,
    VK_RETURN,
    VK_SELECT:
      begin
        HideListBox;
      end;
    VK_UP:
      if Assigned(FPanel) then
      begin
        Key:= 0;
        if FListBox.ItemIndex = -1 then
          FListBox.ItemIndex:= FListBox.Items.Count - 1
        else if FListBox.ItemIndex - 1 < 0 then
          FListBox.ItemIndex:= - 1
        else
          FListBox.ItemIndex:= FListBox.ItemIndex - 1;

        if FListBox.ItemIndex >= 0 then
          Text:= FListBox.Items[FListBox.ItemIndex]
        else
          Text:= ExtractFilePath(Text);
        SelStart:= UTF8Length(Text);
      end;
    VK_DOWN:
      if Assigned(FPanel) then
      begin
        Key:= 0;
        if FListBox.ItemIndex + 1 >= FListBox.Items.Count then
          FListBox.ItemIndex:= -1
        else if FListBox.ItemIndex = -1 then
          FListBox.ItemIndex:= IfThen(FListBox.Items.Count > 0, 0, -1)
        else
          FListBox.ItemIndex:= FListBox.ItemIndex + 1;

        if FListBox.ItemIndex >= 0 then
          Text:= FListBox.Items[FListBox.ItemIndex]
        else
          Text:= ExtractFilePath(Text);
        SelStart:= UTF8Length(Text);
      end;
  end;
  inherited KeyDown(Key, Shift);
{$IFDEF LCLGTK2}
  // Workaround for GTK2 - up and down arrows moving through controls.
  if Key in [VK_UP, VK_DOWN] then Key:= 0;
{$ENDIF}
end;

procedure TKASPathEdit.KeyUpAfterInterface(var Key: Word; Shift: TShiftState);
begin
  if (FKeyDown = Key) and FAutoComplete and not (Key in [VK_ESCAPE, VK_RETURN, VK_SELECT, VK_UP, VK_DOWN]) then
  begin
    if Modified then
    begin
      Modified:= False;
      AutoComplete(Text);
    end;
  end;
  inherited KeyUpAfterInterface(Key, Shift);
{$IF DEFINED(LCLWIN32)}
  // Windows auto-completer eats the TAB so LCL doesn't get it and doesn't move to next control.
  if not FAutoComplete and (Key = VK_TAB) then
    GetParentForm(Self).SelectNext(Self, True, True);
{$ENDIF}
end;

constructor TKASPathEdit.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);

  FStringList:= TStringList.Create;

  FListBox:= TListBox.Create(Self);
  FListBox.TabStop:= False;
  FListBox.Align:= alClient;
  FListBox.ParentFont:= False;
  FListBox.ClickOnSelChange:= False;
  FListBox.OnClick:= ListBoxClick;
  FListBox.OnMouseMove:= ListBoxMouseMove;

  FAutoComplete:= True;
  FFileSortType:= fstFoldersFirst;
  FObjectTypes:= [otNonFolders, otFolders];
end;

destructor TKASPathEdit.Destroy;
begin
  inherited Destroy;
  FStringList.Free;
end;

end.
