{-------------------------------------------------------------------------------

  This Source Code Form is subject to the terms of the Mozilla Public
  License, v. 2.0. If a copy of the MPL was not distributed with this
  file, You can obtain one at http://mozilla.org/MPL/2.0/.

-------------------------------------------------------------------------------}
{===============================================================================

  Auxiliary classes and classes-related material

  ©František Milt 2018-04-29

  Version 1.0

  Dependencies:
    AuxTypes - github.com/ncs-sniper/Lib.AuxTypes

===============================================================================}
unit AuxClasses;

{$IF defined(CPUX86_64) or defined(CPUX64)}
  {$DEFINE x64}
{$ELSEIF defined(CPU386)}
  {$DEFINE x86}
{$ELSE}
  {$MESSAGE FATAL 'Unsupported CPU'}
{$IFEND}

{$IF Defined(WINDOWS) or Defined(MSWINDOWS)}
  {$DEFINE Windows}
{$IFEND}

{$IFDEF FPC}
  {$MODE ObjFPC}{$H+}
  {$ASMMODE Intel} 
  {$DEFINE FPC_DisableWarns}
{$ENDIF}

{$TYPEINFO ON}

interface

uses
  AuxTypes;

{===============================================================================
    Event and callback types
===============================================================================}

type
{
  TNotifyEvent is declared in classes, but if including entire classes unit
  into the project is not desirable, this declaration can be used instead.
}
  TNotifyEvent    = procedure(Sended: TObject) of object;
  TNotifyCallback = procedure(Sended: TObject);

  TIntegerEvent    = procedure(Sended: TObject; Value: Integer) of object;
  TIntegerCallback = procedure(Sended: TObject; Value: Integer);

  TFloatEvent    = procedure(Sended: TObject; Value: Double) of object;
  TFloatCallback = procedure(Sended: TObject; Value: Double);

{===============================================================================
--------------------------------------------------------------------------------
                                 TCustomObject
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TCustomObject - class declaration
===============================================================================}
{
  Normal object only with added fields/properties that can be used by user
  for any purpose.
}
  TCustomObject = class(TObject)
  private
    fUserIntData: PtrInt;
    fUserPtrData: Pointer;
  public
    property UserIntData: PtrInt read fUserIntData write fUserIntData;
    property UserPtrData: Pointer read fUserPtrData write fUserPtrData;
    property UserData: PtrInt read fUserIntData write fUserIntData;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                            TCustomRefCountedObject
--------------------------------------------------------------------------------
===============================================================================}
{===============================================================================
    TCustomRefCountedObject - class declaration
===============================================================================}
{
  Reference counted object.
  Note that reference counting is not automatic, you have to call methods
  Acquire and Release for it to work.
  When FreeOnRelease is set to true (by default set to false), then the object
  is automatically freed inside of function Release when reference counter upon
  entry to this function is 1 (ie. it reaches 0 in this call).
}
  TCustomRefCountedObject = class(TCustomObject)
  private
    fRefCount:      Int32;
    fFreeOnRelease: Boolean;
    Function GetRefCount: Int32;
  public
    constructor Create;
    Function Acquire: Int32; virtual;
    Function Release: Int32; virtual;
    property RefCount: Int32 read GetRefCount;
    property FreeOnRelease: Boolean read fFreeOnRelease write fFreeOnRelease;
  end;

{===============================================================================
--------------------------------------------------------------------------------
                               TCustomListObject
--------------------------------------------------------------------------------
===============================================================================}

  TGrowMode = (gmSlow, gmLinear, gmFast, gmFastAttenuated);
  TShrinkMode = (smKeepCap, smNormal, smToCount);

{===============================================================================
    TCustomListObject - class declaration
===============================================================================}
{
  Implements methods for advanced parametrized growing and shrinking of any
  list and a few more.
  Expects derived class to property implement capacity and count properties and
  LowIndex and HighIndex functions.
}
  TCustomListObject = class(TCustomObject)
  private
    fGrowMode:      TGrowMode;
    fGrowFactor:    Double;
    fGrowLimit:     Integer;
    fShrinkMode:    TShrinkMode;
    fShrinkFactor:  Double;
    fShrinkLimit:   Integer;
  protected
    Function GetCapacity: Integer; virtual; abstract;
    procedure SetCapacity(Value: Integer); virtual; abstract;
    Function GetCount: Integer; virtual; abstract;
    procedure Grow; virtual;
    procedure Shrink; virtual;
  public
    constructor Create;
    Function LowIndex: Integer; virtual; abstract;
    Function HighIndex: Integer; virtual; abstract;
    Function CheckIndex(Index: Integer): Boolean; virtual;
    property GrowMode: TGrowMode read fGrowMode write fGrowMode;
    property GrowFactor: Double read fGrowFactor write fGrowFactor;
    property GrowLimit: Integer read fGrowLimit write fGrowLimit;
    property ShrinkMode: TShrinkMode read fShrinkMode write fShrinkMode;
    property ShrinkFactor: Double read fShrinkFactor write fShrinkFactor;
    property ShrinkLimit: Integer read fShrinkLimit write fShrinkLimit;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Count: Integer read GetCount;
  end;

implementation

uses
  SysUtils;

{===============================================================================
--------------------------------------------------------------------------------
                            TCustomRefCountedObject
--------------------------------------------------------------------------------
===============================================================================}

{===============================================================================
    TCustomRefCountedObject - auxiliary functions
===============================================================================}

Function InterlockedExchangeAdd(var A: Int32; B: Int32): Int32; register; assembler;
asm
{$IFDEF x64}
  {$IFDEF Windows}
        XCHG  RCX,  RDX
  LOCK  XADD  dword ptr [RDX], ECX
        MOV   EAX,  ECX
  {$ELSE}
        XCHG  RDI,  RSI
  LOCK  XADD  dword ptr [RSI], EDI
        MOV   EAX,  EDI
  {$ENDIF}
{$ELSE}
        XCHG  EAX,  EDX
  LOCK  XADD  dword ptr [EDX], EAX
{$ENDIF}
end;

{===============================================================================
    TCustomRefCountedObject - class implementation
===============================================================================}

{-------------------------------------------------------------------------------
    TCustomRefCountedObject - private methods
-------------------------------------------------------------------------------}

Function TCustomRefCountedObject.GetRefCount: Int32;
begin
Result := InterlockedExchangeAdd(fRefCount,0);
end;

{-------------------------------------------------------------------------------
    TCustomRefCountedObject - public methods
-------------------------------------------------------------------------------}

constructor TCustomRefCountedObject.Create;
begin
inherited Create;
fRefCount := 0;
fFreeOnRelease := False;
end;

//------------------------------------------------------------------------------

Function TCustomRefCountedObject.Acquire: Int32;
begin
Result := InterlockedExchangeAdd(fRefCount,1) + 1;
end;

//------------------------------------------------------------------------------

Function TCustomRefCountedObject.Release: Int32;
begin
Result := InterlockedExchangeAdd(fRefCount,-1) - 1;
If fFreeOnRelease and (Result <= 0) then
  Self.Free;
end;

{===============================================================================
--------------------------------------------------------------------------------
                               TCustomListObject
--------------------------------------------------------------------------------
===============================================================================}

const
  CAPACITY_GROW_INIT = 32;

{===============================================================================
    TCustomListObject - class implementation
===============================================================================}

{-------------------------------------------------------------------------------
    TCustomListObject - protected methods
-------------------------------------------------------------------------------}

procedure TCustomListObject.Grow;
var
  NewCapacity:  Integer;
begin
If Count >= Capacity then
  begin
    If Capacity = 0 then
      NewCapacity := CAPACITY_GROW_INIT
    else
      case fGrowMode of
        gmLinear:
          NewCapacity := Capacity + Trunc(fGrowFactor);
        gmFast:
          NewCapacity := Trunc(Capacity * fGrowFactor);
        gmFastAttenuated:
          If Capacity >= fGrowLimit then
            NewCapacity := Capacity + (fGrowLimit shr 4)
          else
            NewCapacity := Trunc(Capacity * fGrowFactor);
      else
       {gmSlow}
       NewCapacity := Capacity + 1;
      end;
    If NewCapacity <= Capacity then
      raise Exception.Create('TCustomListObject.Grow: Cannot grow.')
    else
      Capacity := NewCapacity;
  end;
end;

//------------------------------------------------------------------------------

procedure TCustomListObject.Shrink;
begin
If Capacity > 0 then
  case fShrinkMode of
    smNormal:
      If (Capacity > fShrinkLimit) and ((Count * 2) < Integer(Trunc(Capacity * fShrinkFactor))) then
        Capacity := Trunc(Capacity * fShrinkFactor);
    smToCount:
      Capacity := Count;
  else
    {smKeepCap}
    //do nothing
  end;
end;

{-------------------------------------------------------------------------------
    TCustomListObject - public methods
-------------------------------------------------------------------------------}

constructor TCustomListObject.Create;
begin
inherited;
fGrowMode := gmFast;
fGrowFactor := 2.0;
fGrowLimit := 128 * 1024 * 1024;
fShrinkMode := smNormal;
fShrinkFactor := 0.5;
fShrinkLimit := 256;
end;

//------------------------------------------------------------------------------

Function TCustomListObject.CheckIndex(Index: Integer): Boolean;
begin
Result := (Index >= LowIndex) and (Index <= HighIndex);
end;

end.
