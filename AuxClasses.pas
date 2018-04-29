unit AuxClasses;

{$IF defined(CPUX86_64) or defined(CPUX64)}
  {$DEFINE x64}
{$ELSEIF defined(CPU386)}
  {$DEFINE x86}
{$ELSE}
  {$DEFINE PurePascal}
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

type
  TNotifyEvent    = procedure(Sended: TObject) of object;
  TNotifyCallback = procedure(Sended: TObject);

  TIntegerEvent    = procedure(Sended: TObject; Value: Integer) of object;
  TIntegerCallback = procedure(Sended: TObject; Value: Integer);

  TFloatEvent    = procedure(Sended: TObject; Value: Double) of object;
  TFloatCallback = procedure(Sended: TObject; Value: Double);

  TCustomObject = class(TObject)
  private
    fUserIntData: PtrInt;
    fUserPtrData: Pointer;
  public
    property UserIntData: PtrInt read fUserIntData write fUserIntData;
    property UserPtrData: Pointer read fUserPtrData write fUserPtrData;
    property UserData: PtrInt read fUserIntData write fUserIntData;
  end;

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

  TGrowMode = (gmSlow, gmLinear, gmFast, gmFastAttenuated);
  TShrinkMode = (smKeepCap, smNormal, smToCount);

  TCustomListObject = class(TCustomObject)
  private
    fGrowMode:    TGrowMode;
    fGrowFactor:  Double;
    fGrowLimit:   Integer;
    fShrinkMode:  TShrinkMode;
  protected
    Function GetCapacity: Integer; virtual; abstract;
    procedure SetCapacity(Value: Integer); virtual; abstract;
    Function GetCount: Integer; virtual; abstract;
    procedure Grow; virtual;
    procedure Shrink; virtual;
  public
    constructor Create;
    property GrowMode: TGrowMode read fGrowMode write fGrowMode;
    property GrowFactor: Double read fGrowFactor write fGrowFactor;
    property GrowLimit: Integer read fGrowLimit write fGrowLimit;
    property ShrinkMode: TShrinkMode read fShrinkMode write fShrinkMode;
    property Capacity: Integer read GetCapacity write SetCapacity;
    property Count: Integer read GetCount;
  end;

implementation

uses
  SysUtils;

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

Function TCustomRefCountedObject.GetRefCount: Int32;
begin
Result := InterlockedExchangeAdd(fRefCount,0);
end;

constructor TCustomRefCountedObject.Create;
begin
inherited Create;
fRefCount := 0;
fFreeOnRelease := False;
end;

Function TCustomRefCountedObject.Acquire: Int32;
begin
Result := InterlockedExchangeAdd(fRefCount,1);
Inc(Result);
end;

Function TCustomRefCountedObject.Release: Int32;
begin
Result := InterlockedExchangeAdd(fRefCount,-1);
Dec(Result);
If fFreeOnRelease and (Result <= 0) then
  Self.Free;
end;

const
  CAPACITY_GROW_INIT = 32;

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

procedure TCustomListObject.Shrink;
begin
If Capacity > 0 then
  case fShrinkMode of
    smNormal:
      If (Capacity > 256) and (Count < (Capacity shr 2)) then
        Capacity := Count shr 1;
    smToCount:
      Capacity := Count;
  else
    {smKeepCap}
    //do nothing
  end;
end;

constructor TCustomListObject.Create;
begin
inherited;
fGrowMode := gmFast;
fGrowFactor := 2.0;
fGrowLimit := 128 * 1024 * 1024;
fShrinkMode := smNormal;
end;

end.
