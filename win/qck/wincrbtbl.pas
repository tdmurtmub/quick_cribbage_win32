{ (C) 2009 Wesley Steiner }

{$MODE FPC}

{$ifdef DEBUG}
{!$define AUTOPLAY_ROUND}
{!$define TEST_END_GAME}
{!$define TEST_HISHEELS}
{!$define TEST_HISNOBS}
{!$define TEST_HOLES}
{!$define VIEWALLHANDS}
{$endif DEBUG}

unit wincrbtbl;

{$I std.inc}
{$R wincrbtbl.res}

interface

uses
	std,
	windows,
	objects,
	cards,
	cribbage,
	winqcktbl;

const
	SID_DISCARDCOMPLETE=1001;
	CBMINHOLEINDEX=-1;
	CBMAXHOLEINDEX=MAX_SCORE;
	CBSKUNKINDEX=CRIBSKUNKSCORE;

	CM_HINT=295;

	WM_NEXTPLAY=WM_NEXT+1; { next player to play }
	WM_SAVEGAMESCORE=WM_NEXT+2;
	
type
	tTrackId=(OUTSIDE_TRACK,MIDDLE_TRACK,INSIDE_TRACK);
	CBHoleIndex=CBMINHOLEINDEX..CBMAXHOLEINDEX;
	
	OCribboardProp=object(Hotspot)
		constructor Construct(w,h:integer);
		destructor Destruct; virtual;
		function GetAnchorPoint(table_width,table_height:word):xypair; virtual;
		procedure InsertPeg(aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
		procedure Redraw(dc:HDC; x,y:integer); virtual;
		procedure RemovePeg(aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
	private
		myTrackHiPegs:array[tTrackId] of CBHoleIndex;
//		function Title(a_pBuffer:PChar):PChar;
		procedure DCInsertPeg(aDC:HDC; aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
		procedure DCRemovePeg(aDC:HDC; aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
//		procedure ResetTitle;
		procedure UpdateTrackHiPeg(aTrackId:tTrackId; aHoleNum:CBHoleIndex);
	end;

	HandcardPropP=^HandcardProp;
	HandcardProp=object(OCardpileProp)
		constructor Construct(aOrdinal:integer);
		function CanGrabCardAt(aIndex:integer):boolean; virtual;
		procedure Help; virtual;
	end;

	OMainTabletop=object(winqcktbl.OTabletop)
		function Create(frame:HWND;w,h:number):HWND; virtual;
	end;
	OMainTabletop_ptr=^OMainTabletop;

const
	show_play_count:boolean=TRUE;

var
	cribboard:^OCribboardProp; 
	game_recorder:GameRecorder;
	aWinner:boolean; { has somebody won? }
	
function OnNextPlay:LONG;
function PegScore(aPlayer:playerindex):integer;
function TrailerScore(aPlayer:playerindex):integer;

procedure AbortGame;
procedure Deal;
procedure doHint;
procedure HumanDiscards;
procedure NewGame;
procedure OnNewGame;
procedure ProcessDiscards;
procedure Start;

implementation

uses
	sysutils,
	stringsx,
	windowsx,
	gdiex,
	qcktbl,
	winCardFactory,
	odlg;

const
	MSDELAY_VISUAL_ACTION={$ifdef AUTOPLAY_ROUND}0{$else}300{$endif};
	{$ifdef TEST_END_GAME} TEST_STARTING_SCORE={$ifdef TEST_HISHEELS} 120 {$else} 107 {$endif}; {$endif}
	
type
	OpponentCardPropP=^OpponentCardProp;
	OpponentCardProp=object(HandcardProp)
		function GetAnchorPoint(aNewWd,aNewHt:word):xypair; virtual;
	end;

	OPlayerCardProp=object(HandcardProp)
		function GetAnchorPoint(aNewWd,aNewHt:word):xypair; virtual;
		function OnTopcardTapped:boolean; virtual;
		function TryPlaying(nth:integer):boolean;
	end;
	OPlayerCardProp_ptr=^OPlayerCardProp;

	OStarterpile=object(OCardpileProp)
		function GetAnchorPoint(table_width,table_height:word):xypair; virtual;
	end;
	OStarterpile_ptr=^OStarterpile;

	CribPile=object(OCardpileProp)
		function GetAnchorPoint(table_width,table_height:word):xypair; virtual;
	end;
	CribPileP=^CribPile;
	
	OCribboardProp_ptr=^OCribboardProp;

	CribTabletopGame=object(winqcktbl.Game)
		function PileRows:word; virtual;
	end;

	OPlaypileProp=object(OCardpileProp)
		constructor Construct(aPlayerTag:playerindex);
		function GetAnchorPoint(aNewWd,aNewHt:word):xypair; virtual;
	private
		myPlayerTag:playerindex;
	end;
	OPlaypileProp_ptr=^OPlaypileProp;

const
	the_crib_prop:CribPileP=nil;
	theStarterPile:^OStarterpile=nil;

var
	cameFrom:array[1..2] of integer;
	discardCounter:integer;
	indicArrow:HBITMAP; { indicator arrow image bitmap }
	n_discards:integer; { # of cards in the tmp crib display area while discarding }
	Probs:array[TACE..TKING] of integer; { Value 0,1,2,3 or 4 indicating the number of each Pip left in play that the program records during the hand. }
	PCChoice:array[1..2] of integer;
	ptr:integer;
	selectedCardNo:integer; { card number selected for discard/play that was picked }
	tabletop_game:CribTabletopGame;
	thePlayPile:array[playerindex] of OPlaypileProp_ptr;
	thePlayerCards:array[playerindex] of array[1..CRIBDEALSIZE] of HandcardPropP;
	the_winner:playerindex; { who won the current game when aWinner is true }
	Thrown:array[playerindex,1..6] OF BOOLEAN;
	tabletop:^OMainTabletop;
	
function cardDeltaX:integer;
begin
	cardDeltaX:=(CurrentWidth + MIN_EDGE_MARGIN);
end;

function cribX:integer;
begin
	CribX:=MIN_EDGE_MARGIN + CardDeltaX * 4 + ((CardDeltaX * 2 - OptXSpace * 3 - CurrentWidth) div 2);
end;

function starterX:integer;
begin
	StarterX:=CribX + PipHSpace * 3;
end;

function playAreaY:integer;
begin
	with the_crib_prop^.MyTabletop^ do playAreaY:=Integer(Centered(CurrentHeight,Top,Bottom));
end;

function PlayerY(p:playerindex):integer;
begin
	if p=pc then
		playerY:=MIN_EDGE_MARGIN
	else
		playerY:=the_crib_prop^.MyTabletop^.Bottom-CurrentHeight;
end;

function CribPile.GetAnchorPoint(table_width,table_height:word):xypair;
begin
	GetAnchorPoint:=MakeXYPair(CribX,PlayerY(CribState.WhosCrib));
end;

constructor HandcardProp.Construct(aOrdinal:integer);
begin
	inherited Construct(1);
	Ordinal:=aOrdinal;
end;

function OpponentCardProp.GetAnchorPoint(aNewWd,aNewHt:word):xypair;
begin
	GetAnchorPoint:=MakeXYPair(MIN_EDGE_MARGIN+(Ordinal-1)*CardDeltaX,PlayerY(PC));
end;

constructor OPlaypileProp.Construct(aPlayerTag:playerindex);
begin
	inherited Construct(4);
	myPlayerTag:=aPlayerTag;
end;

function OPlaypileProp.GetAnchorPoint(aNewWd,aNewHt:word):xypair;
begin
	SetCardDx(CardDeltaX);
	GetAnchorPoint:=MakeXYPair(
		MIN_EDGE_MARGIN+(CurrentWidth div 2),
		Center(CurrentHeight,
			Q(myPlayerTag=PC, MIN_EDGE_MARGIN+CurrentHeight, aNewHt div 2),
			Q(myPlayerTag=PC, aNewHt div 2, aNewHt-(MIN_EDGE_MARGIN+CurrentHeight))));
end;

function PointerY(who:playerIndex;n:integer):integer;
begin
	PointerY:=Q(n=5,PlayAreaY,thePlayPile[who]^.GetAnchorY)-GetBitmapHt(indicArrow)-1;
end;

procedure MoveDiscards(who:playerindex;i1,i2:integer);
begin
	thePlayerCards[who,i1]^.TopcardTo(thePlayPile[who]); 
	thePlayerCards[who,i2]^.TopcardTo(thePlayPile[who]); 
	{$IFDEF VIEWALLHANDS}
	if who=pc then begin
	end;
	{$ENDIF}
end;

procedure PCDiscards;
{ Do the computer's discards. }
var
	i,j:integer;
begin
	ChooseDiscards(PC,pcChoice[1],pcChoice[2]);
	CribState.TheCrib.Ref(1)^:=CardsGet(CribState.Players[pc].TheHand, pcChoice[1]);
	CribState.TheCrib.Ref(2)^:=CardsGet(CribState.Players[pc].TheHand, pcChoice[2]);
	moveDiscards(pc,pcChoice[1],pcChoice[2]);
	{ adjust the pc's hand }
	j:=1;
	for i:=1 TO CRIBDEALSIZE do
		IF (PCChoice[1]<>i) AND (PCChoice[2]<>i) then begin
			CribState.Players[PC].TheHand.Ref(j)^:=CardsGet(CribState.Players[pc].TheHand, i);
			if (i<>j) then begin
				thePlayerCards[PC,i]^.TopcardTo(thePlayerCards[PC,j]);
				delay(cardPlayDelay);
			end;
			j:=j+1;
		end;
	CribState.Players[PC].CardCount:=4;
	Inc(n_discards,2); { 2 cards in the temp crib display }
end;

procedure Deal;
var
	i,n:integer;
	First,Second:playerindex;
begin
	CSFDealHand(CribState);
	
	{$ifdef VIEWALLHANDS} 
	CribState.Players[PC].TheHand.flipAllFaceup;
	{$endif}

	{$ifdef TEST_HISNOBS}
	CribState.Players[HUMAN].TheHand.ref(3)^:=MakeCard(TJACK, THEARTS) and (not FACEUP_BIT);
	{$endif}

	{ now display it visually }
	IF CribState.WhosCrib=PC then begin
		First:=HUMAN;
		Second:=PC;
	end
	ELSE begin
		First:=PC;
		Second:=HUMAN;
	end;

	for i:=0 to CRIBDEALSIZE-1 DO begin
		thePlayerCards[First,i+1]^.AddCard(CardFacedown(CribState.Players[First].TheHand.Get(i+1)));
		delay(cardPlayDelay div 2);
		thePlayerCards[Second,i+1]^.AddCard(CardFacedown(CribState.Players[Second].TheHand.Get(i+1)));
		delay(cardPlayDelay div 2);
	end;

	for n:=1 to CRIBDEALSIZE do begin
		{$ifdef VIEWALLHANDS} 
		thePlayerCards[PC,n]^.FlipTopcard; 
		{$endif}
		thePlayerCards[HUMAN,n]^.FlipTopcard;
		delay(cardPlayDelay);
	end;

	{$ifdef VIEWALLHANDS} 
	InvalidateRect(Handle,NIL,True);
	UpdateWindow(Handle);
	{$endif}

	{ adjust probabilities for the PC }
	for i:=1 to CRIBDEALSIZE DO probs[CardPip(CardsGet(CribState.Players[pc].TheHand, (i)))]:=
		pred(Probs[CardPip(CardsGet(CribState.Players[pc].TheHand, i))]);

	FillChar(Thrown,SizeOf(Thrown),#0);
	PCDiscards;
end;

function messageY:integer;
begin
	messageY:=playAreaY + CurrentHeight + SysFontHt;
end;

procedure ClearCribTable;
var
	n:integer;
begin
	if the_crib_prop<>nil then with the_crib_prop^ do begin
		discard;
		Hide;
	end;
	if theStarterPile<>nil then with theStarterPile^ do begin
		discard;
		Hide;
	end;
	n_discards:=0;
	thePlayPile[PC]^.Discard;
	thePlayPile[HUMAN]^.Discard;
	CribState.Players[PC].CardCount:=0;
	for n:=1 to CRIBDEALSIZE do thePlayerCards[PC,n]^.Discard;
	CribState.Players[HUMAN].CardCount:=0;
	for n:=1 to CRIBDEALSIZE do thePlayerCards[HUMAN,n]^.Discard;
end;

procedure NewHand;
var
	i:integer;
begin //writeln('NewHand');
	CribState.Players[pc].CardCount:=0;
	CribState.Players[Human].CardCount:=0;
	n_discards:=0;
	for i:=TACE to TKING DO Probs[i]:=4;
	CSFNewHand(CribState);
end;

var
	bmCribBoard:TBitmap; { bitmap data record for the crib board image }
	pegImage:array[playerindex] of HBITMAP; { peg image bitmaps }
	peghole_image:HBITMAP;
	cbImage:HBITMAP;
	
const
	PegImageWd=9;
	PegImageHt=9;
	{ crib board hole coordinates + screen offset }
	startHoleY=563; { Y pixel offset to lowest start hole. }
	startHoleDY=14; { delta Y pixels between holes }
	colHoleY=501; { Y offset to the bottom hole of columns 1,3. }
	col2HoleY=97; { Y offset to the top hole of column 2. }
	colHoleDY=11; { Y pixel space between holes in a 5 hole set. }
	colHoleHY=5; { extra Y pixel space between 5-hole sets }
	col1X:array[playerindex] of integer=(530,502); { X offset to first col }
	col2X:array[playerindex] of integer=(614,642); { X offset to next col }
	col3X:array[playerindex] of integer=(586,558); { X offset to last col }
	topHoleX:array[playerindex,36..45] of integer=(
		(530,534,541,551,564, 580,593,603,610,614),
		(502,508,519,537,558, 586,607,625,636,642));
	topHoleY:array[playerindex,36..45] of integer=(
		(81,69,58,50,46, 46,50,58,69,81),
		(81,59,40,26,18, 18,26,40,59,81));
	bottomHoleX:array[playerindex,81..85] of integer=(
		(614,608,600,592,586),
		(639,626,600,574,561));
	bottomHoleY:array[playerindex,81..85] of integer=(
		(515,521,524,521,515),
		(524,542,551,542,524));
	winHoleX=572;
	winHoleY=81;

procedure holeXY(who:playerindex; h:integer; var x:integer; var y:integer);
{ Return the screen (x,y) coordinates of whole number "h" for "who". }
begin
	case h of
		-2..0:begin
			x:=col1X[who];
			y:=startHoleY-(h+2)*startHoleDY;
		end;
		1..35:begin
			x:=col1X[who];
			y:=colHoleY-(h-1)*colHoleDY-((h-1) div 5)*colHoleHY;
		end;
		36..45:begin
			x:=topHoleX[who,h];
			y:=topHoleY[who,h];
		end;
		46..80:begin
			x:=col2X[who];
			y:=col2HoleY+(h-46)*colHoleDY+((h-46) div 5)*colHoleHY;
		end;
		81..85:begin
			x:=bottomHoleX[who,h];
			y:=bottomHoleY[who,h];
		end;
		86..120:begin
			x:=col3X[who];
			y:=colHoleY-(h-86)*colHoleDY-((h-86) div 5)*colHoleHY;
		end;
		CBMaxHoleIndex:begin
			x:=winHoleX;
			y:=winHoleY;
		end;
	end;
	{ now offset to screen }
	x:=x-492;
	y:=y-7;
end;

function Track2Who(a_aTrackId:tTrackId):playerindex;
begin
	case a_aTrackId of
		OUTSIDE_TRACK:Track2Who:=Human;
		INSIDE_TRACK:Track2Who:=PC;
	end;
end;

function Who2Track(Who:playerindex):tTrackId;
begin
	case Who of
		Human:Who2Track:=OUTSIDE_TRACK;
		PC:Who2Track:=INSIDE_TRACK;
	end;
end;

function TrailerScore(aPlayer:playerindex):integer;
begin
	TrailerScore:=player_scores[aPlayer].BackPeg;
end;

function PegScore(aPlayer:playerindex):integer;
begin
	PegScore:=player_scores[aPlayer].FrontPeg;
end;

constructor OCribboardProp.Construct(w, h:integer);
begin
	inherited Construct(w, h);
	FillChar(myTrackHiPegs, SizeOf(myTrackHiPegs), #0);
end;

destructor OCribboardProp.Destruct;
begin
	DeleteObject(PegImage[Human]);
	DeleteObject(PegImage[pc]);
	DeleteObject(peghole_image);
end;

function OCribboardProp.GetAnchorPoint(table_width, table_height:word):xypair;
begin
	GetAnchorPoint:=MakeXYPair(Center(Width, StarterX + CurrentWidth, table_width), Center(Height, 0, table_height));
end;

procedure OCribboardProp.DCRemovePeg(aDC:HDC; aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
var
	x,y:integer;
begin
	HoleXY(aPlayerIndex, aHoleNum, x, y);
	PutBitmap(aDC, peghole_image, Left + x, Top + y, SRCAND)
end;

procedure RemovePeg(Who:cribbage.playerindex;HoleNo:integer);
begin
	cribboard^.RemovePeg(Who, CBHoleIndex(HoleNo));
end;

procedure OCribboardProp.RemovePeg(aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
var
	aDC:HDC;
begin //writeln('OCribboardProp.RemovePeg(',aPlayerIndex,',',aHoleNum,')');
	aDC:=GetDC(MyTabletop^.handle);
	DCRemovePeg(aDC, aPlayerIndex, aHoleNum);
	ReleaseDC(MyTabletop^.handle, aDC);
end;

procedure OCribboardProp.DCInsertPeg(aDC:HDC; aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
var
	i,x,y:integer;
begin
	HoleXY(aPlayerIndex, aHoleNum, x, y);
	PutBitmap(aDC, peghole_image, Left + x, Top + y, SRCAND);
	PutBitmap(aDC, pegImage[aPlayerIndex], Left + x, Top + y, SRCPAINT);
end;

procedure OCribboardProp.InsertPeg(aPlayerIndex:playerindex; aHoleNum:CBHoleIndex);
var
	aDC:HDC;
begin //writeln('OCribboardProp.InsertPeg(',aPlayerIndex,',',aHoleNum,')');
	aDC:=GetDC(MyTabletop^.handle);
	DCInsertPeg(aDC, aPlayerIndex, aHoleNum);
	ReleaseDC(MyTabletop^.handle, aDC);
	UpdateTrackHiPeg(Who2Track(aPlayerIndex), aHoleNum);
//	ResetTitle;
end;

procedure OCribboardProp.Redraw(dc:HDC; x,y:integer);
var
	dc2:HDC;
begin
	dc2:=CreateCompatibleDC(dc);
 	SelectObject(dc2, cbimage);
	BitBlt(dc, x, y, bmCribBoard.bmWidth, bmCribBoard.bmHeight, dc2, 0, 0, SRCCOPY);
	DeleteDC(dc2);
	DCInsertPeg(dc, HUMAN, PegScore(HUMAN));
	DCInsertPeg(dc, HUMAN, trailerScore(HUMAN));
	DCInsertPeg(dc, PC, PegScore(PC));
	DCInsertPeg(dc, PC, trailerScore(PC));
end;

procedure OCribboardProp.UpdateTrackHiPeg(aTrackId:tTrackId; aHoleNum:CBHoleIndex);
begin
	if aHoleNum = 0
		then myTrackHiPegs[aTrackId]:= 0 { reset }
		else myTrackHiPegs[aTrackId]:= Max(myTrackHiPegs[aTrackId], aHoleNum);
end;

function OMainTabletop.Create(frame:HWND;w,h:number):HWND;
begin
	Create:=inherited Create(frame,w,h);
	tabletop:=@self;
	cribboard:=New(OCribboardProp_ptr, Construct(bmCribBoard.bmWidth, bmCribBoard.bmHeight));
	cribboard^.Hide;
	CSFInit(CribState,CribMode2Player);
	tabletop_game.Construct(@self);
	AddProp(cribboard);
	the_crib_prop:=New(CribPileP, Construct(4));
	the_crib_prop^.m_Outlined:=FALSE;
	AddProp(the_crib_prop);
	theStarterPile:=New(OStarterpile_ptr, Construct(1));
	with theStarterPile^ do begin
		Anchor.X:=StarterX;
		Anchor.Y:=PlayAreaY;
	end;
	AddProp(theStarterPile);
	thePlayPile[PC]:=OPlaypileProp_ptr(AddProp(New(OPlaypileProp_ptr,Construct(PC))));
	thePlayPile[HUMAN]:=OPlaypileProp_ptr(AddProp(New(OPlaypileProp_ptr,Construct(HUMAN))));
end;

function WinnerMsg:string;
begin
	if the_winner=HUMAN 
		then WinnerMsg:='Congratulations! You WIN.'
		else WinnerMsg:='Game over. I WIN!';
end;

procedure Winner(host:HWND);
var
	buffer:stringbuffer;
begin
	DefaultWinnerSound;
	{$ifndef AUTOPLAY_ROUND}
	MessageBox(host, StrPCopy(buffer, WinnerMsg), 'Winner', MB_ICONINFORMATION or MB_OK);
	{$endif}
end;

procedure doHint;
{ Function to execute when the hint button is selected. }
var
	c1,c2:integer;
begin
	chooseDiscards(human,c1,c2);
	moveDiscards(human,c1,c2);
	CribState.Players[Human].CardCount:=4;
	Inc(n_discards,2);
	selectedCardNo:=0;
	thrown[human,c1]:=true;
	thrown[human,c2]:=true;
	cameFrom[1]:=c1;
	cameFrom[2]:=c2;
	discardCounter:=2;
	CribState.TheCrib.Ref(3)^:=CardsGet(CribState.Players[human].TheHand, c1);
	CribState.TheCrib.Ref(4)^:=CardsGet(CribState.Players[human].TheHand, c2);
end;

function CribTabletopGame.PileRows:word;
begin
	PileRows:=5;
end;

function HandcardProp.CanGrabCardAt(aIndex:integer):boolean;
begin
	CanGrabCardAt:=FALSE;
end;

procedure HandcardProp.Help;
begin
end;

function CreateBoardImage:HBITMAP;
var
	bm2:HBITMAP;
	oBR,hBR:HBRUSH;
	SysDC,dc2:HDC;
	cw,ch:integer;
	R:RECT;

	procedure ResBitmapDisplayXY(id:PChar;aDC:HDC;x,y:integer;Rop:LongInt); { at x,y }
	{ Load/Display/Free a bitmap resource "id" at (x,y) in "aDC". }
	var
		hdcAbout:HDC;
		a_hbitmap:HBITMAP;
		hdcBitmap:HBITMAP;
	begin
		a_hbitmap:=LoadBitmap(hInstance,id);
		hdcAbout:=CreateCompatibleDC(aDC);
		hdcBitmap:=SelectObject(hdcAbout,a_hbitmap);
		BitBlt(aDC,x,y,GetBitmapWd(a_hbitmap),GetBitmapHt(a_hbitmap),hdcAbout,0,0,Rop);
		SelectObject(hdcAbout,hdcBitmap);
		DeleteDC(hdcAbout);
		DeleteObject(a_hbitmap);
	end;

begin
	cw:=169;
	ch:=561;
	SysDC:=GetDC(GetDesktopWindow);
	bm2:=CreateCompatibleBitmap(SysDC,cw,ch);
	dc2:=CreateCompatibleDC(SysDC);
	ReleaseDC(GetDesktopWindow,SysDC);
 	SelectObject(dc2,bm2);
	SetRect(R, 0, 0, cw, ch);
	FillRect(dc2, R, GetStockObject(WHITE_BRUSH));
	ResBitmapDisplayXY('BOARD', dc2, 7, 7, SRCCOPY);
	hBR:=CreateSolidBrush(RGB(230,191,138));
	oBR:=SelectObject(dc2, hBR);
	FloodFill(dc2, 1, 1, RGB(0,0,0));
	SelectObject(dc2, oBR);
	SelectObject(dc2, GetStockObject(NULL_BRUSH));
	Rectangle(dc2, 0, 0, cw, ch);
	DeleteObject(hBR);
	DeleteDC(dc2);
	CreateBoardImage:=bm2;
end;
	
function OStarterpile.GetAnchorPoint(table_width,table_height:word):xypair;
begin
	GetAnchorPoint:=MakeXYPair(StarterX, PlayAreaY);
end;

procedure InsertPeg(Who:cribbage.playerindex;HoleNo:integer);
begin
	cribboard^.InsertPeg(Who, CBHoleIndex(HoleNo));
end;

procedure InsertPegs;
begin
	InsertPeg(HUMAN,trailerScore(HUMAN));
	InsertPeg(HUMAN,PegScore(HUMAN));
	InsertPeg(PC,trailerScore(PC));
	InsertPeg(PC,PegScore(PC));
end;

procedure CribShuffle;
begin
	tabletop^.player_prompt.Hide;
	CardsShuffle(CribState.Pack, Shuffles);
end;

Procedure RemovePegs;
begin
	RemovePeg(HUMAN,trailerScore(HUMAN));
	RemovePeg(HUMAN,PegScore(HUMAN));
	RemovePeg(PC,trailerScore(PC));
	RemovePeg(PC,PegScore(PC));
end;

{$ifdef TEST_HOLES}
procedure TestCribBoardHolePositions;
var
	i:CBHoleIndex;
begin
	RemovePegs;
	for i:=CBMinHoleIndex to CBMaxHoleIndex do begin
		cribboard^.InsertPeg(PC,i);
		cribboard^.InsertPeg(Human,i);
		Delay(20);
		cribboard^.RemovePeg(Human,i);
		cribboard^.RemovePeg(PC,i);
	end;
	InsertPegs;
end;
{$endif}

procedure Start;
var
	n:integer;
begin
	cribboard^.Show;
	InsertPegs;
	CribShuffle;

	{ if no game to restore then start a new one }
	if (player_scores[HUMAN].FrontPeg=0) and (player_scores[PC].FrontPeg=0) then begin
		DrawForFirstCrib;
		NewGame;
	end;

	for n:=1 to CRIBDEALSIZE do begin
		thePlayerCards[PC,n]:=HandcardPropP(tabletop^.AddProp(New(OpponentCardPropP, Construct(n))));
		thePlayerCards[HUMAN,n]:=HandcardPropP(tabletop^.AddProp(New(OPlayerCardProp_ptr, Construct(n))));
	end;
	wincrbtbl.Newhand;
	game_recorder.BeginHand(CribState.WhosCrib);
	
	{$ifdef TEST_END_GAME}
	RemovePegs;
	player_scores[PC].FrontPeg:=TEST_STARTING_SCORE;
	player_scores[Human].FrontPeg:=TEST_STARTING_SCORE;
	InsertPegs;
	{$endif}
	
	{$ifdef TEST_HOLES} 
	TestCribBoardHolePositions; 
	{$endif}
end;

procedure NewGame;
begin //writeln('NewGame');
	CSFNewGame(CribState);
	CBPreGame;
	aWinner:=False;
	game_recorder.BeginGame;
	{$ifdef TEST_END_GAME}
	player_scores[PC].FrontPeg:=TEST_STARTING_SCORE;
	player_scores[Human].FrontPeg:=TEST_STARTING_SCORE;
	{$endif}
	InsertPegs;
end;

procedure Tally(whom:cribbage.playerindex; p:integer);
var
	i:integer;
	fpeg,bpeg:integer;
begin
	game_recorder.AddPoints(Whom,p);
	fpeg:=PegScore(Whom);
	bpeg:=TrailerScore(whom);
	for i:=1 to p do begin
		RemovePeg(whom,bpeg);
		bpeg:=fpeg+i;
		InsertPeg(whom, bpeg);
		Delay(BASEDELAY*4);
		if bpeg=MAX_SCORE then begin
			aWinner:=true;
			the_winner:=whom;
			bpeg:=fpeg;
			fpeg:=MAX_SCORE;
			Winner(tabletop^.Handle);
			tabletop^.player_prompt.Hide;
			ClearCribTable;
			RemovePeg(HUMAN, CBMAXHOLEINDEX);
			exit;
		end;
	end;
	TallyPoints(Whom,p);
	{$ifndef TEST_END_GAME}
	System.Assert(game_recorder.Score(Whom)=PegScore(Whom),'GameRecord Score does not match with internal score!');
	{$endif}
end;

function Pronoun(a_aCribPlayerIndex:cribbage.playerindex):string;
begin
	if a_aCribPlayerIndex =PC
		then Pronoun:='me'
		else Pronoun:='you';
end;

procedure TallyPlayPoints(who:cribbage.playerindex;p:integer;s:string);
var
	title:string;
	z,ztitle:stringBuffer;
begin
	title:='Points for ' + Capitalize(Pronoun(who));
	{$ifndef AUTOPLAY_ROUND}
	MessageBox(tabletop^.Handle, StrPCopy(z, s), StrPCopy(ztitle, title), MB_ICONINFORMATION or MB_OK);
	{$endif}
	tally(who,p);
end;

procedure PostStarter(Who:cribbage.playerindex);
{ Evaluate the starter card and continue play after one has been selected by either player. }
var
	s:string;
begin
	CSFPostStarter(CribState);
	pend:=0;
	pStart:=1;
	{ Test for a JACK turned up }
	if {$ifdef TEST_HISHEELS} TRUE {$else} CardPip(theStarterPile^.thePile^.gettop)=TJACK {$endif} then begin
		s:='2 points for "His Heels"';
		if Who=PC then Who:=HUMAN else Who:=PC;
		TallyPlayPoints(who, 2, s);
	end;
	FillChar(Thrown,SizeOf(Thrown),#0);
	if not aWinner then windows.PostMessage(windows.GetParent(tabletop^.Handle), WM_NEXTPLAY, 0, 0);
end;

procedure EndPick(Who:cribbage.playerindex);
var
	Starter:TCard;
	aRect:TRect;
	aDC:hDC;
begin
	tabletop^.player_prompt.Hide;
	delay(MSDELAY_VISUAL_ACTION);
	{$ifdef TEST_HISNOBS}
	Starter:=MakeCard(TDEUCE, THEARTS) and (not FACEUP_BIT);
	{$else}
	Starter:=CardsRemove(CribState.Pack, SelectedCardNo);
	{$endif}
	with theStarterPile^ do begin
		Anchor.X:=StarterX;
		Anchor.Y:=PlayAreaY;
	end;
	theStarterPile^.Show;
	theStarterPile^.thePile^.add(starter);
	with theStarterPile^ do if (TopFacedown) then theStarterPile^.FlipTopcard;
	CardsAdd(CribState.StarterPile, Starter);
	PostStarter(Who);
	dec(Probs[CardPip(Starter)]);
end;

procedure PickStarter(Who:cribbage.playerindex);
begin
	if
		(not PlayDuplicate)
		or
		(PlayDuplicate and (not IsDupGame))
		or
		(PlayDuplicate and IsDupGame and DupOverflow)
	then begin
		SelectedCardNo:=RandomPick(DECK_SIZE-CRIBDEALSIZE*2);
		if Who=PC
			then EndPick(HUMAN)
			else EndPick(PC);
	end
	else begin
		theStarterPile^.thePile^.Add(CribState.StarterPile.ListPtr^.List[0]);
		theStarterPile^.Show;
		theStarterPile^.FlipTopcard;
		PostStarter(Who);
	end;
end;

function PossesivePronoun(a_aCribPlayerIndex:cribbage.playerindex):string;
begin
	if a_aCribPlayerIndex =PC
		then PossesivePronoun:='my'
		else PossesivePronoun:='your';
end;

{$ifdef TESTIT}
procedure TestPossesivePronoun;
begin
	punit.Assert.EqualStr('my', PossesivePronoun(PC));
	punit.Assert.EqualStr('your', PossesivePronoun(HUMAN));
end;
{$endif}

procedure ProcessDiscards;
{ Process the two current discard selections. }
var
	i,j:integer;
	aStrToTextBuffer:stringBuffer;
	aPlayerTag:cribbage.playerindex;
begin
	if
		{$ifdef AUTOPLAY_ROUND}
		TRUE
		{$else}
		MessageBox(tabletop^.Handle, StrPCopy(aStrToTextBuffer,'Discard these two cards to '+PossesivePronoun(CribState.WhosCrib)+' Crib?'),
			'Verify Discards',MB_YESNO or MB_ICONQUESTION)=IDYES
		{$endif}
	then begin
		windows.SendMessage(windows.GetParent(tabletop^.Handle), WM_SIGNAL, SID_DISCARDCOMPLETE, 0);
		tabletop^.player_prompt.Hide;
		thePlayPile[HUMAN]^.Flip;
		Delay(CardPlayDelay);

		{ adjust the human's hand }
		j:=1;
		for i:=1 TO CRIBDEALSIZE DO begin
			IF NOT Thrown[human,i] then begin
				CribState.Players[HUMAN].TheHand.Ref(j)^:=CardsGet(CribState.Players[human].TheHand,i);
				if i<>j then begin
					thePlayercards[HUMAN,i]^.TopcardTo(thePlayercards[HUMAN,j]);
					delay(cardPlayDelay);
				end;
				j:=j+1;
			end;
			Thrown[human,i]:=(i>4);
		end;

		{ adjust the internal hand }
		CardsRemovetop(CribState.Players[PC].TheHand);
		CardsRemovetop(CribState.Players[PC].TheHand);
		CardsRemovetop(CribState.Players[Human].TheHand);
		CardsRemovetop(CribState.Players[Human].TheHand);

		{ move the discarded cards to the crib }
		with the_crib_prop^ do SetPosition(GetAnchorPoint(tabletop^.ClientAreaWd, tabletop^.ClientAreaHt));
		the_crib_prop^.Show;
		with thePlayPile[PC]^ do while Size>0 do begin
			CardAtTo(1, the_crib_prop); // hack: necessary to preserve counting order
			Delay(CardPlayDelay);
		end;
		with thePlayPile[HUMAN]^ do while Size>0 do begin
			TopcardTo(the_crib_prop);
			Delay(CardPlayDelay);
		end;

		CribState.Players[Human].CardCount:=4;
		n_discards:=0; { no cards left in the center area }
		{$ifdef AUTOPLAY_ROUND}
		PickStarter(HUMAN);
		{$else}
		PickStarter(CribState.WhosCrib);
		{$endif}
	end
	else begin
		for Ptr:=1 to CRIBDEALSIZE do if Thrown[Human,Ptr] then begin
			thePlayPile[HUMAN]^.TopcardTo(thePlayercards[HUMAN,cameFrom[discardCounter]]);
			Dec(discardCounter);
			Thrown[human,ptr]:=FALSE;
		end;
		n_discards:=2;
		CribState.Players[Human].CardCount:=6;
		EnableMenuItem(GetMenu(tabletop^.GetParent), CM_HINT, MF_BYCOMMAND or MF_ENABLED);
	end;
end;

procedure HumanDiscards;
{ Human's turn to discard 2 cards to the crib. }
var
	i,j:integer;
	ch:char;
	procedure DisplayInfoText(s:string);
	var
		p:array[0..255] of Char;
	begin
		tabletop^.player_prompt.SetText(StrPCopy(p,s));
		tabletop^.player_prompt.Show;
	end;
begin
	for i:=1 to CRIBDEALSIZE do thePlayercards[HUMAN,i]^.Enable;
	discardCounter:=0;
	ptr:=1;
	DisplayInfoText('Discard two (2) cards to ' + Capitalize(PossesivePronoun(CribState.WhosCrib)) + ' Crib.');
	{$ifdef AUTOPLAY_ROUND}
	DoHint;
	ProcessDiscards;
	{$endif}
end;

function TableExtent:integer;
{ Return the X coordinate of the extent (last pixel) of the play area. }
begin
	TableExtent:=MIN_EDGE_MARGIN+CardDeltaX*6;
end;

procedure clearPointCards(who:playerIndex);
var
	R:RECT;
begin
	Setrect(R, 0, pointerY(who,1), tableExtent, pointerY(who,1)+GetBitmapHt(indicArrow));
	InvalidateRect(tabletop^.Handle, @R, True);
	tabletop^.UpdateWindow;
	Setrect(R,0,pointerY(who,5),tableExtent,pointerY(who,5)+GetBitmapHt(indicArrow));
	InvalidateRect(tabletop^.Handle, @R, True);
	tabletop^.UpdateWindow;
end;

const
	IDC_SCORINGDIALOG_LIST=102;

type
	ScoringDialog=object(StickyDialog)
		constructor Construct(aParent:OMainTabletop_ptr; who:playerIndex);
		function OnInitDialog:boolean; virtual;
		function OnEndDialog(aCmdId:UINT):boolean; virtual;
		function OnCmd(aCmdId:UINT):LONG; virtual;
		procedure showPointCards(who:playerIndex;s:integer);
	private
		tabletop:OMainTabletop_ptr;
		myWho:playerIndex;
	end;

var
	ttl:string[40];

constructor ScoringDialog.Construct(aParent:OMainTabletop_ptr; who:playerIndex);
begin
	inherited Construct(aParent^.Handle, 901, 'ScoringDialog');
	tabletop:=aParent;
	myWho:=who;
end;

procedure ScoringDialog.showPointCards(who:playerIndex;s:integer);
{ Point out which cards make up the points for area "s". 
  This function gets called whenever a different picklist item is pointed at. }
var
	i,n:integer;
	aDC:hDC;
begin
	aDC:=GetDC(tabletop^.Handle);
	with thePlayPile[who]^ do for i:=1 to 7 DO IF showp[s].refer[i]>0 then begin
		IF showp[s].refer[i]=5
			then n:=StarterX
			else n:=GetAnchorX+GetCardX(showp[s].refer[i]);
		PutBitmap(aDC,IndicArrow,
			n+((cardDeltaX-GetBitmapWd(indicArrow)) div 2),
			pointerY(who,showp[s].refer[i]),SrcPaint);
	end;
	ReleaseDC(tabletop^.Handle,aDC);
end;

function ScoringDialog.OnCmd(aCmdId:UINT):LONG;
var
	aList:OListBox;
	selection:LRESULT;
begin
	aList.Handle:=GetDlgItem(IDC_SCORINGDIALOG_LIST);
	ClearPointCards(myWho);
	selection:=aList.SendMessage(LB_GETCURSEL,0,0);
	if selection<>LB_ERR then ShowPointCards(myWho,selection+1);
	OnCmd:=inherited OnCmd(aCmdId);
end;

var
	PointStr:string[40];

function ScoringDialog.OnEndDialog(aCmdId:UINT):boolean;
begin
	ClearPointCards(myWho);
	OnEndDialog:=inherited OnEndDialog(aCmdId);
end;

function ScoringDialog.OnInitDialog:boolean;
var
	sz:array[0..40] of Char;
	i,j,k:integer;
	b:string;
	aList:OListBox;
begin
	OnInitDialog:=inherited OnInitDialog;
	StrPCopy(sz,PointStr);
	SetDlgItemText(handle,101,sz);
	StrPCopy(sz,ttl);
	SetWindowText(sz);
	aList.Handle:=GetDlgItem(IDC_SCORINGDIALOG_LIST);
	k:=0;
	for j:=1 to showi-1 DO begin
		k:=k+showp[j].points;
		str(k,b);
		aList.AddString(showp[j].message + ' is ' + b);
	end;
end;

procedure countAll;
var
	i:integer;
	First,Second:cribbage.playerindex;
	buf:stringBuffer;

	procedure showit(whom:cribbage.playerindex;title:string);
	{ Display the total score for this hand. }
	var
		i,j,k,n:integer;
		b:string[10];
		aDlg:ScoringDialog;
	begin
		k:=0;
		for j:=1 to showi-1 do k:=k+showp[j].points;
		str(k, b);
		PointStr:='A total of ' + b;
		{$ifndef AUTOPLAY_ROUND}
		aDlg.Construct(tabletop, whom);
		aDlg.Modal;
		{$endif}
		tabletop^.UpdateWindow;
	end;

	procedure moveCrib(Whom:cribbage.playerindex);

	{ Move the crib from it's original position into the counting area. }

	var
		c:TCard;
		i,j:integer;

	begin
		for i:=CRIBHANDSIZE downto 1 do begin
			CribState.Players[Whom].TheHand.Ref(i)^:=CardsGet(CribState.TheCrib, i);
		end;
		with the_crib_prop^ do while Size>0 do begin
			CardAtTo(1,thePlayPile[whom]);
			thePlayPile[whom]^.FlipTopcard;
			Delay(cardPlayDelay);
		end;
	end;

	procedure localScorehand(whom:cribbage.playerindex;crib:boolean);

	{ whom --- whom am I scoring for
		crib --- is this the crib I am scoring }

	const
		nothingMsg='Nothing!';

	var
		i,j:integer;
		zStr:array[0..50] of Char;

	begin
		ttl:='Points in ' + PossesivePronoun(whom);
		if crib then ttl:=ttl+' Crib' else ttl:=ttl+' Hand';
		showi:=1;
		for i:=1 to 15 DO for j:=1 to 7 DO showp[i].refer[j]:=0;
		CribState.Players[Whom].TheHand.Ref(5)^:=theStarterPile^.thePile^.gettop;
		if Crib 
			then i:=CSFGetCribScore(CribState)
			else i:=cribbage.ScoreHand(thePlayPile[whom]^.Thepile^,theStarterPile^.Topcard);
		IF i>0 { more than nothing ? } then begin
				showit(whom,ttl);
				delay(MSDELAY_VISUAL_ACTION); 
				tally(Whom,i);
			end
		ELSE begin
			{$ifndef AUTOPLAY_ROUND}
			MessageBox(tabletop^.Handle, nothingMsg, StrPCopy(zStr,ttl), MB_ICONINFORMATION or MB_OK);
			{$endif}
			game_recorder.AddPoints(whom,0);
		end;
		Delay(cardPlayDelay);
		with thePlayPile[whom]^ do while Size>0 do begin
			DiscardTop;
			Delay(cardPlayDelay);
		end;
	end;

	procedure CloseDupGame;

	{ finish a duplicate game. }

	begin
		FreeDupList;
	end;

	procedure SetupDupRound; begin SetupDupGame; end;
	procedure closeDupRound; begin CloseDupGame; end;

	procedure CSFEndGame(var aState:CribStateRec);

	{ end this game }

	var
		pnum,pnum2:cribbage.playerindex;

	begin
		if PlayDuplicate then begin
			{ if we are playing a game of duplicate crib then toggle the
				duplicate round flag. }
			Toggle(IsDupGame);
			if IsDupGame then
				SetupDupGame
			else
				CloseDupGame;
		end
		else
			FreeDupList; { don't needem after all }
		with aState do begin
			Inc(SessionGameCount);
			SessionHandCount:=SessionHandCount+HandsPlayed;
			for pnum:=1 to CribNumPlayers do with Players[pnum] do
				if player_scores[pnum].FrontPeg = MAX_SCORE then begin
					WhosCrib:= NextPlayerClockwise(pnum);
					Inc(WinCount);
					{ check for the players that were skunked }
					for pnum2:=1 to CribNumPlayers do
						if (pnum2<>pnum) and (player_scores[pnum2].FrontPeg<=CribSkunkScore) then
							Inc(SkunkCount);
				end;
		end;
	end;

begin
	show:=true; { this time show the counting }
	IF CribState.WhosCrib=PC then begin
		First:=HUMAN;
		Second:=PC
	end
	ELSE begin
		First:=PC;
		Second:=HUMAN
	end;
	if not aWinner then begin
		CribState.Players[First].CardCount:=0;
		for i:=1 to 4 do Thrown[First, i]:=TRUE;
		localScoreHand(First,FALSE);
		if not aWinner then begin
			CribState.Players[Second].CardCount:=0;
			for i:=1 to 4 do Thrown[Second, i]:=TRUE;
			localScoreHand(Second,FALSE);
			if not aWinner then begin
				MoveCrib(Second);
				localScoreHand(Second,true);
			end
			else begin
				show:=FALSE;
				game_recorder.AddPoints(second,CSFGetCribScore(CribState));
				show:=TRUE;
			end;
		end
		else begin
			show:=FALSE;
			game_recorder.AddPoints(second,CSFGetHandScore(CribState,second));
			game_recorder.AddPoints(second,CSFGetCribScore(CribState));
			show:=TRUE;
		end
	end
	else begin
		show:=FALSE;
		game_recorder.AddPoints(first,CSFGetHandScore(CribState,first));
		game_recorder.AddPoints(second,CSFGetHandScore(CribState,second));
		game_recorder.AddPoints(second,CSFGetCribScore(CribState));
		show:=TRUE;
	end;
	game_recorder.EndHand;
	windows.SendMessage(tabletop^.GetParent, WM_SAVEGAMESCORE, 0, 0);
	CSFEndHand(CribState);
	tabletop^.player_prompt.Hide;
	if not aWinner then begin
		ClearCribTable;
		with the_crib_prop^ do begin
			Hide;
			SetPosition(GetAnchorPoint(tabletop^.ClientAreaWd, tabletop^.ClientAreaHt));
		end;
		theStarterPile^.Hide;
	end
	else begin
		CSFEndGame(CribState);
		ClearCribTable;
		RemovePegs;
		{$ifdef AUTOPLAY_ROUND} 
		Halt(the_winner);
		{$endif AUTOPLAY_ROUND}
		NewGame;
	end;
	Show:=False;
	wincrbtbl.Newhand;
	game_recorder.BeginHand(CribState.WhosCrib);
	windows.PostMessage(tabletop^.GetParent, WM_DEAL, 0, 0);
end;

procedure WriteCount;
{ Update the count in the count window. }
var
	zStr:stringBuffer;
begin
	if CribState.NextToPlay=HUMAN 
		then StrCopy(zStr, 'Your turn to play.')
		else zStr[0]:=#0;
	if show_play_count then StrPCopy(StrEnd(zStr),' Count is '+IntToStr(CribState.PlayCount)+'.');
	tabletop^.player_prompt.SetText(zStr);
	tabletop^.player_prompt.Show;
end;

var
	FPeg,BPeg:integer;

procedure xtally(whom:cribbage.playerindex;p:integer);
{ Tally up "p" points for "whom". }
var
	i:integer;
	t:boolean;
begin
	game_recorder.AddPoints(Whom,p);
	{$ifdef DEBUG}
	{$ifndef TEST_END_GAME}
	System.Assert(game_recorder.Score(Whom)=PegScore(Whom),'GameRecord Score does not match with internal score!');
	{$endif}
	{$endif}
	for i:=1 to p DO begin
		RemovePeg(whom,bpeg);
		bpeg:=fpeg + i;
		InsertPeg(whom, bpeg);
		Delay(BASEDELAY*4);
		IF bpeg=MAX_SCORE then begin
			aWinner:=true;
			the_winner:=whom;
			bpeg:=fpeg;
			fpeg:=MAX_SCORE;
			{delay(MSDELAY_VISUAL_ACTION);}
			Winner(tabletop^.Handle);
			tabletop^.player_prompt.Hide;
			ClearCribTable;
			{delay(MSDELAY_VISUAL_ACTION);}
			exit;
		end;
	end;
end;

procedure xtallyPlayPoints(who:cribbage.playerindex;p:integer;s:string);
{ Display and tally up "p" play points for "whom". These are points scored during play only, not for hand counting. }
var
	title:string;
	zs, ztitle:array[0..100] of char;
begin
	title:='Points For ' + Capitalize(Pronoun(who));
	{$ifndef AUTOPLAY_ROUND}
	MessageBox(tabletop^.Handle, StrPCopy(zs, s), StrPCopy(ztitle, title), MB_ICONINFORMATION or MB_OK);
	{$endif}
	xtally(who, p);
end;

procedure showpoints(whom:cribbage.playerindex;p:integer);
var
	i:integer;
	s,b:string;
begin
	IF p>0 then begin
		str(CribState.PlayCount,s);
		str(p,b);
		s:=s+' for '+b;
		xtallyPlayPoints(whom,p,s);
	end;
end;

procedure EndPlay;
var
	i:integer;

	function AllHandsEmpty(const aState:CribStateRec):boolean;
	var
		pnum:cribbage.playerindex;
	begin
		AllHandsEmpty:=TRUE;
		for pnum:=1 to CribNumPlayers do
			if not aState.Players[pnum].TheHand.IsEmpty then begin
				AllHandsEmpty:=FALSE;
				Break;
			end;
	end;

	function DonePlaying(const aState:CribStateRec):boolean;
	begin
		DonePlaying:=(CSFWinner(aState) or AllHandsEmpty(aState));
	end;

begin
	tabletop^.UpdateWindow;
	if DonePlaying(CribState) then begin
		if ShouldCountLastCard then TallyPlayPoints(CribState.NextToPlay,1,'1 for the Last Card');
		CSFEndPLay(CribState);
		tabletop^.player_prompt.Hide;
		Showi:=1;
		FillChar(Thrown, sizeof(Thrown), #0); { so that they will repaint }
		CountAll;
	end
	else windows.PostMessage(windows.GetParent(tabletop^.Handle), WM_NEXTPLAY, 0, 0);
end;

procedure PlayIt;
{ play the chosen card }
var
	i,j:integer;
begin
	if CSFPlayPoints(CribState)>0 then TallyPoints(CribState.NextToPlay,CSFPlayPoints(CribState));
	with CribState do LastToPlay:=NextToPlay;
	{ figure out which card on the screen matches the one just played }
	j:=0;
	for i:=1 to 4 do begin
		if not Thrown[CribState.NextToPlay,i] then Inc(j);
		if j=CPMPlayedNo then Break;
	end;
	CardsRef(CribState.PlayPile, CribState.PlayPile.size)^:=CardsGettop(CribState.PlayPile) or FACEUP_BIT;
	thePlayerCards[CribState.NextToPlay,i]^.TopcardTo(thePlayPile[CribState.NextToPlay]);
	if CribState.NextToPlay=PC then thePlayPile[CribState.NextToPlay]^.FlipTopcard;
	Thrown[CribState.NextToPlay,i]:=True;
	if CSFPlayPoints(CribState)>0 then begin
		tabletop^.player_prompt.Hide;
		ShowPoints(CribState.NextToPlay, CSFPlayPoints(CribState));
	end;
	EndPlay;
end;

function OPlayerCardProp.TryPlaying(nth:integer):boolean;
var
	I,Count:integer;
begin
	{ match the selected card on the screen to one in the logical hand }
	Count:=0;
	for I:=1 to 4 do if not Thrown[Human,I] then begin
		Inc(Count);
		if I=nth then break;
	end;
	if CribState.PlayCount + CardValue(CardPip(CardsGet(CribState.Players[HUMAN].TheHand, Count)))<=31 then begin
		MyTabletop^.player_prompt.Hide;
		CSFPlayCard(CribState,Count); { logically play the card }
		PlayIt;
	end;
	TryPlaying:=TRUE;
end;

function DiscardSelect(n,selectedArea:integer):boolean;
begin
	EnableMenuItem(tabletop^.GetParent, CM_HINT, MF_BYCOMMAND or MF_GRAYED);
	selectedCardNo:=selectedArea;
	ptr:=selectedCardNo;
	thePlayercards[HUMAN,ptr]^.TopcardTo(thePlayPile[HUMAN]); 
	inc(discardCounter);
	Inc(n_discards);
	Thrown[HUMAN,ptr]:=true;
	cameFrom[discardCounter]:=ptr; { save the position in the hand where it came from in case we put it back }
	CribState.TheCrib.Ref(2+discardCounter)^:=CardsGet(CribState.Players[human].TheHand, ptr);
	ptr:=Ptr+1;
	if Ptr>CRIBDEALSIZE then Ptr:=1;
	if DiscardCounter=2 then begin
		ProcessDiscards;
		if aWinner then CountAll;
	end;
	DiscardSelect:=TRUE;
end;

function OPlayerCardProp.OnTopcardTapped:boolean;
begin //writeln('OPlayerCardProp.OnTopcardTapped');
	if n_discards=0 
		then TryPlaying(self.Ordinal)
		else DiscardSelect(CRIBDEALSIZE,self.Ordinal);
	OnTopcardTapped:=TRUE;
end;

function OnNextPlay:LONG;
var
	i,j:integer;
	zStr:array[0..80] of Char;

	procedure TakeTheGo;
	begin
		with CribState do if PlayCount=31 then begin
			TallyPoints(NextToPlay,2);
			xtallyPlayPoints(CribState.NextToPlay,2,'31 for 2')
		end
		else begin
			TallyPoints(NextToPlay,1);
			xtally(CribState.NextToPlay, 1);
		end;
		the_go_flag:=TRUE;
	end;
begin
	Delay(MSDELAY_VISUAL_ACTION);
	with CribState do begin
		FPeg:=player_scores[NextPlayerClockwise(NextToPlay)].FrontPeg;
		BPeg:=player_scores[NextPlayerClockwise(NextToPlay)].BackPeg;
	end;
	with cribState do begin
		NextToPlay:=NextPlayerClockwise(NextToPlay);
		if (PlayCount=31) or the_go_flag then CSFNewGo(CribState);
		if Players[NextToPlay].TheHand.IsEmpty then begin
			if (NextToPlay=LastToPlay) then TakeTheGo;
			EndPlay;
		end
		else begin
			if IsGo(CribState,NextToPlay) then begin
				if (FirstToGo=NONE) then begin
					StrCopy(zStr,'That'#39's a Go for ');
					if CribState.NextToPlay=PC then StrCat(zStr,'Me.') else StrCat(zStr,'You.');
					{$ifndef AUTOPLAY_ROUND}
					MessageBox(tabletop^.Handle, zStr, 'GO!', MB_ICONINFORMATION or MB_OK);
					{$endif}
					FirstToGo:=NextToPlay;
				end
				else if (NextToPlay=LastToPlay) then TakeTheGo;
				EndPlay;
			end
			else begin
				if NextToPlay=pc then begin
					CPFPlay(CribState,NextToPlay);
					PlayIt;
				end
				else begin
					WriteCount;
					{$ifdef AUTOPLAY_ROUND}
					CPFPlay(CribState,NextToPlay);
					PlayIt;
					{$endif}
				end;
			end;
		end;
	end;
	OnNextPlay:=0;
end;

procedure AbortGame;
begin
	tabletop^.player_prompt.Hide;
	ClearCribTable;
	RemovePegs;
	CSFNewGame(CribState);
	CBPreGame;
end;

function OPlayerCardProp.GetAnchorPoint(aNewWd,aNewHt:word):xypair;
begin
	GetAnchorPoint:=MakeXYPair(MIN_EDGE_MARGIN+(Ordinal-1)*CardDeltaX,PlayerY(HUMAN));
end;

procedure OnNewGame;
begin
	CSFNewSession(CribState);
	n_discards:=0;
	CribShuffle;
	DrawForFirstCrib;
	NewGame;
	NewHand;
	game_recorder.BeginHand(CribState.WhosCrib);
	windows.PostMessage(tabletop^.GetParent, WM_DEAL, 0, 0);
end;

begin
	cbImage:=CreateBoardImage;
	GetObject(cbImage, SizeOf(bmCribBoard), @bmCribBoard);
	IndicArrow:=LoadBitmap(hInstance,PChar(798));
	PegImage[pc]:=LoadBitmap(hInstance,PChar(794));
	PegImage[Human]:=LoadBitmap(hInstance,PChar(795));
	peghole_image:=LoadBitmap(hInstance, 'PEGHOLE');
end.
