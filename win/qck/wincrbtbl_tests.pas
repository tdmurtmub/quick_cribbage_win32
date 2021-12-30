{ (C) 2011 Wesley Steiner }

{$MODE FPC}

unit wincrbtbl_tests;

interface

implementation

uses
	punit,
	cards,
	windows,
	cribbage,
	wincrbtbl;
	
procedure handcard_not_grabbable;
var
	prop:HandcardProp;
begin
	prop.Construct(0);
	prop.AddCard(MakeCard(TACE, TSPADE) or FACEUP_BIT);
	AssertIsFalse(prop.CanGrabCardAt(1));
end;

begin
	Suite.Add(@handcard_not_grabbable);
//	Suite.Add(@TestPossesivePronoun);
//	Suite.Add(@TestPronoun);
	Suite.Run('wincrbtbl_tests');
end.
