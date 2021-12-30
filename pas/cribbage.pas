(* (C) 2009 Wesley Steiner *)

{$MODE FPC}

unit cribbage;

interface

uses
	objects,
	std,cards;
	
const
	MAX_SCORE=121;
	SKUNK_SCORE=90;
	CRIBMAXPLAYERS=2;
	PC=1;HUMAN=CRIBMAXPLAYERS;

type
	playerIndex=1..CRIBMAXPLAYERS;
	GameRecorder=object
		procedure AddPoints(who:playerIndex;points:word);
		procedure BeginGame;
		procedure BeginHand(who:playerIndex);
		procedure EndHand;
		procedure FromString(const source:ansistring);
		procedure Initialize;
		function NextCrib:playerIndex;
		function Score(who:playerIndex):integer;
		function ToString:string;
	private
		my_record:ansistring;
		function IsValid(const source:ansistring):boolean;
	end;

function PipValue(p:pip):number;

// deprecated_interface

const
	SHUFFLES=7;
	CRIBDEALSIZE=6;
	CribMode2Player=2;
	maxset=8;								{ MAXIMUM NUMBER OF CARDS IN A SET }
	CRIBHANDSIZE=4;
	CRIBSKUNKSCORE=SKUNK_SCORE; // obsolete
	LIMITS_MAX_SCORE=MAX_SCORE; // obsolete
	max5t2=10; { taking 2 things from 3,4 or 5 }
	max6t4 = 15; { taking 4 things from 5 or 6 }
	NONE=0;

type
	TCribMode=Byte;
	CribStateRec=record { abstracted logical state of a cribbage game }
		Pack:PileOfCards; { the pack of cards }
		StarterPile:PileOfCards; { starter card pile, contains only 1 card }
		TheCrib:PileOfCards; { crib pile }
		PlayPile:PileOfCards; { the pile all players play cards into }
		WhosCrib:playerindex; { who's crib is it }
		Players:array[playerindex] of record
			Comp:boolean; { true if computer controlled }
			TheHand:PileOfCards;
			SessionHandPoints:LongInt;
			OutOfPlay:array[TACE..TKING, TCLUB..TSPADE] of boolean; { true if
				card is known to this player and so is out of play for the
				other players }
			CardCount:integer; { how many cards currently in the hand }
		end;
		NextToPlay:playerindex;
		LastToPlay,FirstToGo:integer; { player that first called GO or 0 }
		PlayCount:Word; { the current total count in the play pile }
		SessionGameCount:integer; { in this session }
		SessionHandCount:LongInt; { played in the session }
		SessionCribPoints:Longint; { total points over "SessionHandCount" played }
		WinCount:Word; { how many games this player has one }
		SkunkCount:Word; { how many extra games this player has won by skunking }
	end;
	cardset=array[1..MAXSET] of TCard; { maximum counting hand can have 7 cards }
	PDupRec=^DupRecType;
	dupRecType=record
		pcHand:cardset;
		humanHand:cardset;
		starter:TCard;
	end;

const
	CribNumPlayers:playerindex=2; { how many players are currently playing }
	PlayDuplicate:boolean=FALSE;
	pStart:integer=1;  { index to the first card in the current build to 31 }
	comb6t4:array[1..max6t4,1..4] of integer = (
	 (1,2,3,4),(1,2,3,5),(1,2,3,6),(1,2,4,5),(1,2,4,6),(1,2,5,6),(1,3,4,5),
	 (1,3,4,6),(1,3,5,6),(1,4,5,6),(2,3,4,5),(2,3,4,6),(2,3,5,6),(2,4,5,6),
	 (3,4,5,6));
	the_go_flag:boolean=FALSE;

var
	IsDupGame:boolean; { true when the current game is the duplicate }
	show:boolean;  											{ specifies that the analysis should be recorded for later display }
	showi:integer; 											{ global index into showp array }
	showp:array[1..15] of record
		message:string[20];
		points:integer;
		refer:array[1..MAXSET] of integer;	{ card pointer references }
	end;
	HandsPlayed:integer; { in this game }
	dupRec:dupRecType;
	DupList:TCollection;
	pend:integer;    { indexes ending card in current playing sequence }
	DupHand:integer; { duplicate hand collection index }
	DupOverFlow:boolean; { true when there are more hands in the current duplicate game than were recorded in the previous game }
	CribState:CribStateRec;
	CPMPlayedNo:integer; { card no that last player played out }
	player_scores:array[playerindex] of record
		FrontPeg,BackPeg:integer;
	end;

function CardValue(aPip:TPip):integer;
function CommonScore(Temp:CardSet):Word;
function CSFGetCribScore(const aState:CribStateRec):Word;
function CSFGetHandScore(const aState:CribStateRec;pnum:playerindex):Word;
function CSFPlayPoints(const aState:CribStateRec):integer;
function CSFWinner(const aState:CribStateRec):boolean; { true when somebody has won the current game }
function FifteenTwo(n:integer;var hand:cardset):boolean;
function Fifteens(n:integer;var hand:cardset):integer;
function IsGo(const aState:CribStateRec;pnum:playerindex):boolean;
function RandomPick(n:integer):integer;
function Run(n:integer;var hand:cardset):boolean;
function Runs(n:integer;var hand:cardset):integer;
function Pairs(n:integer;var Hand:Cardset):integer;
function Flush(n:integer;var Hand:Cardset):boolean;
function HisNob(aPile:PileOfCards;startersuit:byte):boolean;
function NextPlayerClockwise(pnum:playerindex):playerindex;
function playvalue(n:integer;hand:cardset;count:integer):integer;
function ScoreHand(const aPile:PileOfCards;aStarter:tcard):Word;
function ShouldCountLastCard:boolean;

procedure ChooseDiscards(whom:playerindex;var choice1,choice2:integer);
procedure CBPreGame;
procedure CPFPlay(var aState:CribStateRec;pnum:playerindex);
procedure CSFEndHand(var aState:CribStateRec);
procedure CSFEndPlay(var aState:CribStateRec);
procedure CSFInit(var aState:CribStateRec;aMode:TCribMode);
procedure CSFNewGame(var aState:CribStateRec);
procedure CSFNewHand(var aState:CribStateRec);
procedure CSFNewSession(var aState:CribStateRec);
procedure CSFDealHand(var aState:CribStateRec);
procedure CSFNewGo(var aState:CribStateRec);
procedure CSFPlayCard(var aState:CribStateRec;CardNo:integer);
procedure CSFPostStarter(var aState:CribStateRec);
procedure CSMDone;
procedure DealDup(var aState:CribStateRec);
procedure DrawForFirstCrib;
procedure nextsequence(var aState:CribStateRec);
procedure SetupDupGame;
procedure freeDupList;
procedure TallyPoints(pnum:playerindex;nPoints:Word);

implementation

uses
	sysutils,strutils,
	punit;

var
	PlayedFrom:array[1..CRIBMAXPLAYERS*5] of Byte; { who the played cards came from }

function PipValue(p:pip):number;
begin
	case p of
		JACK,QUEEN,KING:PipValue:=10;
		else PipValue:=Ord(p);
	end;
end;

{$ifdef TEST}

procedure test_PipValue;

begin
	AssertAreEqual(1,PipValue(ACE));
	AssertAreEqual(2,PipValue(DEUCE));
	AssertAreEqual(3,PipValue(THREE));
	AssertAreEqual(4,PipValue(FOUR));
	AssertAreEqual(5,PipValue(FIVE));
	AssertAreEqual(6,PipValue(SIX));
	AssertAreEqual(7,PipValue(SEVEN));
	AssertAreEqual(8,PipValue(EIGHT));
	AssertAreEqual(9,PipValue(NINE));
	AssertAreEqual(10,PipValue(TEN));
	AssertAreEqual(10,PipValue(JACK));
	AssertAreEqual(10,PipValue(QUEEN));
	AssertAreEqual(10,PipValue(KING));
end;

{$endif}

function GameRecorder.ToString:string;

begin
	ToString:=my_record;
end;

procedure GameRecorder.BeginGame;

begin
	my_record:='';
end;

procedure GameRecorder.BeginHand(who:playerIndex);

begin
	if Length(my_record)>0 then my_record:=my_record+',';
	if who=PC then my_record:=my_record+'-1' else my_record:=my_record+'1';
end;

procedure GameRecorder.AddPoints(who:playerIndex;points:word);

begin
	my_record:=my_record+','+IntToStr(Integer(Q(who=PC,-points,points)));
end;

procedure GameRecorder.EndHand;

begin
	my_record:=my_record+',99';
end;

procedure GameRecorder.Initialize;

begin
	my_record:='';
end;

{$ifdef TEST}

procedure Test_GameRecorder_AddPoints;

var
	testee:GameRecorder;

begin
	testee.BeginGame;
	testee.BeginHand(HUMAN);
	testee.AddPoints(HUMAN,2);
	punit.Assert.EqualStr('1,2',testee.ToString);
	testee.AddPoints(PC,3);
	punit.Assert.EqualStr('1,2,-3',testee.ToString);
	testee.AddPoints(HUMAN,0);
	punit.Assert.EqualStr('1,2,-3,0',testee.ToString);
	testee.AddPoints(PC,0);
	punit.Assert.EqualStr('1,2,-3,0,0',testee.ToString);
end;

procedure Test_GameRecorder_BeginHand;

var
	testee:GameRecorder;

begin
	testee.BeginGame;
	testee.BeginHand(PC);
	punit.Assert.EqualStr('-1',testee.ToString);
	testee.BeginHand(HUMAN);
	punit.Assert.EqualStr('-1,1',testee.ToString);
end;

procedure Test_GameRecorder_EndHand;

var
	testee:GameRecorder;

begin
	testee.my_record:='1,2,3';
	testee.EndHand;
	punit.Assert.EqualStr('1,2,3,99',testee.ToString);
end;

procedure Test_GameRecorder_string_length;

var
	testee:GameRecorder;
	i:integer;

begin
	testee.BeginGame;
	for i:=1 to 30 do testee.my_record:=testee.my_record+'1234567890';
	punit.Assert.Equal(300,Length(testee.my_record));
end;

{$endif TEST}

function GameRecorder.Score(who:playerIndex):integer;

var
	n,points:integer;
	s:string;
	scores:array[playerIndex] of integer;

	procedure SkipOverCrib;	begin Inc(n); end;

begin
	FillChar(scores,SizeOf(scores),0);
	n:=1;
	SkipOverCrib;
	repeat
		s:=ExtractDelimited(n,my_record,[',']);
		if Length(s)>0 then begin
			points:=Integer(StrToIntDef(s,0));
			if points=99 
				then SkipOverCrib
				else Inc(scores[Q(points<0,PC,HUMAN)],Abs(points));
		end;
		Inc(n);
	until Length(s)=0;
	Score:=Min(MAX_SCORE,scores[who]);
end;

{$ifdef TEST}

procedure Test_GameRecorder_Score;

var
	testee:GameRecorder;

begin
	testee.Initialize;
	punit.Assert.Equal(0,testee.Score(HUMAN));
	testee.BeginGame;
	punit.Assert.Equal(0,testee.Score(HUMAN));
	punit.Assert.Equal(0,testee.Score(PC));
	testee.BeginHand(HUMAN);
	punit.Assert.Equal(0,testee.Score(HUMAN));
	punit.Assert.Equal(0,testee.Score(PC));
	testee.AddPoints(PC,1);
	punit.Assert.Equal(1,testee.Score(PC));
	testee.AddPoints(HUMAN,2);
	punit.Assert.Equal(2,testee.Score(HUMAN));
	testee.AddPoints(PC,3);
	punit.Assert.Equal(4,testee.Score(PC));
	testee.AddPoints(HUMAN,4);
	punit.Assert.Equal(6,testee.Score(HUMAN));
	testee.EndHand;

	testee.BeginHand(PC);
	punit.Assert.Equal(6,testee.Score(HUMAN));
	testee.AddPoints(HUMAN,5);
	punit.Assert.Equal(11,testee.Score(HUMAN));
	testee.AddPoints(PC,6);
	punit.Assert.Equal(10,testee.Score(PC));

	testee.AddPoints(PC,29);
	testee.AddPoints(PC,29);
	testee.AddPoints(PC,29);
	testee.AddPoints(PC,29);
	punit.Assert.Equal(121,testee.Score(PC));
end;

{$endif TEST}

function GameRecorder.IsValid(const source:ansistring):boolean;

	function AllNumbers:boolean;
	var
		n,points:integer;
		s:string;
	begin
		n:=1;
		repeat
			s:=ExtractDelimited(n,source,[',']);
			if (Length(s)=0) and (n=1) then begin
				AllNumbers:=FALSE;
				Exit;
			end;
			if Length(s)>0 then begin
				points:=Integer(StrToIntDef(s,-99));
				if points=-99 then begin
					AllNumbers:=FALSE;
					Exit;
				end;
			end;
			Inc(n);
		until Length(s)=0;
		AllNumbers:=TRUE;
	end;

begin
	IsValid:=(Length(source)>9) and (Copy(source,Length(source)-2,3)=',99') and (AllNumbers);
end;

procedure GameRecorder.FromString(const source:ansistring);
begin
	my_record:='';
	if IsValid(source) then my_record:=source;
end;

{$ifdef TEST}

procedure Test_GameRecorder_FromString;

var
	testee:GameRecorder;

begin
	testee.Initialize;
	testee.FromString('-1,10,-11,99');
	punit.Assert.EqualStr('-1,10,-11,99',testee.my_record);
	testee.FromString('1,0,0,0,99');
	punit.Assert.EqualStr('1,0,0,0,99',testee.my_record);
	testee.FromString(',0,0,0,99');
	punit.Assert.EqualStr('',testee.my_record);
	testee.FromString(',0,0,0,99,1,2,3,4,99');
	punit.Assert.EqualStr('',testee.my_record);
	testee.FromString('1,0,0,0,98');
	punit.Assert.EqualStr('',testee.my_record);
	testee.FromString('1,0,0,0,89');
	punit.Assert.EqualStr('',testee.my_record);
	testee.FromString('1,0,0,0:99');
	punit.Assert.EqualStr('',testee.my_record);
	testee.FromString('1,0,foo,0,99');
	punit.Assert.EqualStr('',testee.my_record);
end;

{$endif TEST}

function GameRecorder.NextCrib:playerIndex;

var
	n,num:integer;
	s:string;
	last_crib:playerIndex;
	gameStart:boolean;

begin
	last_crib:=PC;
	n:=1;
	gameStart:=TRUE;
	repeat
		s:=ExtractDelimited(n,my_record,[',']);
		if Length(s)>0 then begin
			num:=Integer(StrToInt(s));
			if gameStart then begin
				last_crib:=playerIndex(Q(num=1,Ord(HUMAN),Ord(PC)));
				gameStart:=FALSE;
			end;
			if num=99 then gameStart:=TRUE;
		end;
		Inc(n);
	until Length(s)=0;
	NextCrib:=playerIndex(Q(last_crib=PC,Ord(HUMAN),Ord(PC)));
end;

{$ifdef TEST}

procedure Test_GameRecorder_NextCrib;

var
	testee:GameRecorder;

begin
	testee.Initialize;
	punit.Assert.Equal(HUMAN,testee.NextCrib);
	testee.BeginGame;
	testee.BeginHand(PC);
	punit.Assert.Equal(HUMAN,testee.NextCrib);
	testee.BeginGame;
	testee.BeginHand(HUMAN);
	punit.Assert.Equal(PC,testee.NextCrib);
	testee.EndHand;
	testee.BeginHand(PC);
	punit.Assert.Equal(HUMAN,testee.NextCrib);
	testee.EndHand;
	punit.Assert.Equal(HUMAN,testee.NextCrib);
end;

{$endif TEST}

const
	CribModeAuto=$80;

var
	AutoMode:boolean;

procedure CSFNewHand(var aState:CribStateRec);

var
	i:integer;
	aPip:TPip;aSuit:TSuit;

begin
	Show:=False;
	Showi:=1;
	with aState do begin
		CardsEmpty(Pack);
		CardsAddPacks(Pack,NoJoker);
		CardsEmpty(TheCrib);
		CardsEmpty(StarterPile);
		CardsEmpty(PlayPile);
		for i:=1 to CribNumPlayers do begin
			CardsEmpty(Players[i].TheHand);
			with Players[i] do for aPip:=TACE to TKING do for aSuit:=TCLUB to TSPADE do
				OutOfPlay[aPip,aSuit]:=False;
		end;
	end;
end;

procedure CSFNewGame(var aState:CribStateRec);

begin
	with aState do begin
		HandsPlayed:=0;
	end;
	CSFNewHand(aState);
end;

procedure CSFNewSession(var aState:CribStateRec);

var
	i:playerindex;

begin
	with aState do begin
		SessionGameCount:=0;SessionHandCount:=0;
		WinCount:=0;
		SkunkCount:=0;
		for i:=1 to CribNumPlayers do with Players[i] do begin
			SessionHandPoints:=0;
		end;
		SessionCribPoints:=0;
		IsDupGame:=false; { if playing duplicate crib then by default
			this will not be the duplicate game }
		WhosCrib:=Random(CribNumPlayers)+1;
	end;
	CSFNewGame(aState);
end;

procedure CSFInit(var aState:CribStateRec;aMode:TCribMode);

var
	i:integer;

begin
	AutoMode:=(aMode and CribModeAuto)>0;
	with aState do begin
		CardsInit(Pack,TPackSize);
		CardsInit(TheCrib,4);
		CardsSetName(TheCrib,'Crib');
		CardsInit(StarterPile,1);
		CardsSetName(StarterPile,'Starter');
		CardsInit(PlayPile,CribNumPlayers*4);
		CardsSetName(PlayPile,'Played');
		WinCount:=0;
		SkunkCount:=0;
		for i:=1 to CribNumPlayers do with Players[i] do begin
			Comp:=(AutoMode or (i<CribNumPlayers));
			TheHand.Construct(CribDealSize);
			CardCount:=0;
		end;
	end;
	CSFNewSession(aState);
end;

const
	max5t3=10; { taking 3 things from 4 or 5 }
	comb5t2:array[1..max5t2,1..2] of integer =
	((1,2),(1,3),(1,4),(1,5),(2,3),(2,4),(2,5),(3,4),(3,5),(4,5));
	comb5t3:array[1..max5t3,1..3] of integer =
	((1,2,3),(1,2,4),(1,2,5),(1,3,4),(1,3,5),
	 (1,4,5),(2,3,4),(2,3,5),(2,4,5),(3,4,5));

function CardValue(aPip:TPip):integer;

begin
	CardValue:=PipValue(TPipToPip(aPip));
end;

function FifteenTwo(n:integer;var hand:cardset):boolean;

	{ return true if all the cards add up to 15 }

	var
		I,Total:integer;

	begin
		total:=0;
		for i:=1 to n do total:=total+CardValue(CardPip(hand[i]));
		FifteenTwo:=(total=15);
	end;

function Fifteens(n:integer;var hand:cardset):integer;

{ return all combinations of fifteen-2 from a hand of n cards }

var
	i,total:integer;
	work:cardset;

begin
	total:=0;
	for i:= 1 to max5t2 DO IF comb5t2[i,2]<=n then begin
		work[1]:=hand[comb5t2[i,1]];
		work[2]:=hand[comb5t2[i,2]];
		IF fifteenTwo(2,work) then begin
			total:=total+2;
			IF show then begin
				showp[showi].message:='Fifteen Two';
				showp[showi].points:=2;
				showp[showi].refer[1]:=comb5t2[i,1];
				showp[showi].refer[2]:=comb5t2[i,2];
				showi:=showi+1;
			end;
		end;
  end;
  for i:= 1 to max5t3 DO IF comb5t3[i,3]<=n then begin
		work[1]:=hand[comb5t3[i,1]];
		work[2]:=hand[comb5t3[i,2]];
		work[3]:=hand[comb5t3[i,3]];
    IF fifteenTwo(3,work) then begin
      total:=total+2;
			IF show then begin
        showp[showi].message:='Fifteen Two';
				showp[showi].points:=2;
        showp[showi].refer[1]:=comb5t3[i,1];
				showp[showi].refer[2]:=comb5t3[i,2];
        showp[showi].refer[3]:=comb5t3[i,3];
				showi:=showi+1;
			end;
    end;
  end;
  IF n=5 then for i:= 1 to max6t4 DO IF comb6t4[i,4]<=n then begin
		work[1]:=hand[comb6t4[i,1]];
		work[2]:=hand[comb6t4[i,2]];
		work[3]:=hand[comb6t4[i,3]];
		work[4]:=hand[comb6t4[i,4]];
		IF fifteenTwo(4,work) then begin
			total:=total+2;
			IF show then begin
				showp[showi].message:='Fifteen Two';
				showp[showi].points:=2;
				showp[showi].refer[1]:=comb6t4[i,1];
				showp[showi].refer[2]:=comb6t4[i,2];
				showp[showi].refer[3]:=comb6t4[i,3];
				showp[showi].refer[4]:=comb6t4[i,4];
				showi:=showi+1;
			end;
		end;
	end;
	IF fifteenTwo(n,hand) then begin
		total:=total+2;
		IF show then begin
			showp[showi].message:='Fifteen Two';
			showp[showi].points:=2;
			for i:= 1 to n DO showp[showi].refer[i]:=i;
			showi:=showi+1;
		end;
	end;
	fifteens:=total;
end;

function Run(n:integer;var hand:cardset):boolean;

{ check for a run of n cards in hand }

var
	i,j:integer;

begin
	Run:=TRUE;
	for i:=1 TO n-1 DO
		for j:=i+1 TO n DO
			IF CardPip(hand[i])=CardPip(hand[j]) then begin
				Run:=FALSE;
				exit;
			end
			ELSE IF abs(CardPip(hand[i])-CardPip(hand[j]))>=n then begin
				Run:=FALSE;
				exit;
			end;
end;

function Runs(n:integer;var hand:cardset):integer;

{ return the highest run count from a hand of n=(4,5) cards }

var
	i,j,total:integer;
	work:cardset;
	aRun:boolean;

begin
	Runs:=0;
	total:=0;
  aRun:=FALSE;
	IF Run(n,hand) then begin { check for run of all cards }
    Runs:=n;
    IF show then begin
			showp[showi].message:='A Run of '+Chr(48+n);
			showp[showi].points:=n;
      for i:= 1 to n DO showp[showi].refer[i]:=i;
			showi:=showi+1;
    end;
		exit;
  end;
	{ no complete run so check for run of 4 IF hand is 5 cards }

	IF n=5 then for i:= 1 to max6t4 DO IF comb6t4[i,4]<=5 then begin
    for j:= 1 to 4 DO work[j]:=hand[comb6t4[i,j]];
		IF Run(4,work) then begin
      total:=total+4;
      aRun:=true;
      IF show then begin
				showp[showi].message:='A Run of 4';
        showp[showi].points:=4;
				for j:= 1 to 4 DO showp[showi].refer[j]:=comb6t4[i,j];
				showi:=showi+1;
      end;
		end;
  end;
  IF aRun then begin
    Runs:=total;
		exit;
  end;
	{ nothing yet so check for runs of 3 }
	for i:= 1 to max5t3 DO IF comb5t3[i,3]<=n then begin
    for j:= 1 to 3 DO work[j]:=hand[comb5t3[i,j]];
		IF Run(3,work) then begin
      total:=total+3;
			aRun:=true;
			IF show then begin
				showp[showi].message:='A Run of 3';
				showp[showi].points:=3;
				for j:= 1 to 3 DO showp[showi].refer[j]:=comb5t3[i,j];
				showi:=showi+1;
			end;
		end;
	end;
	Runs:=total;
end;

function pairs(n:integer;var Hand:Cardset):integer;

{ Return the count for pairs in the Hand of N cards }

var
	i,j,acc:integer;

begin
	acc:=0;
	for i:=1 to max5t2 DO
    IF comb5t2[i,2]<=n then
			IF CardPip(Hand[comb5t2[i,1]])=CardPip(Hand[comb5t2[i,2]]) then begin
        acc:=acc+2;
        IF show then begin
          showp[showi].message:='A Pair';
					showp[showi].points:=2;
          showp[showi].refer[1]:=comb5t2[i,1];
          showp[showi].refer[2]:=comb5t2[i,2];
          showi:=showi+1;
				end;
			end;
  Pairs:=acc;
end;

function Flush(n:integer;var Hand:Cardset):boolean;

{ do the n cards make a flush? }

var
	i:integer;
	flag:boolean;

begin
	flag:=true;
	for i:=1 to n-1 DO IF CardSuit(Hand[i])<>CardSuit(Hand[i+1]) then flag:=FALSE;
	IF flag then begin
		flush:=true;
		IF show then begin
			showp[showi].message:='A ' + chr(48+n) + '-Flush';
			showp[showi].points:=n;
			for i:= 1 to n DO showp[showi].refer[i]:=i;
			showi:=showi+1;
		end;
	end
	ELSE flush:=FALSE;
end;

function HisNob(aPile:PileOfCards;startersuit:byte):boolean;

var
	i:integer;

begin
	hisNob:=FALSE;
	with aPile do for i:= 1 to Size DO
		IF
			(CardPip(CardsGet(apile,i))=TJACK)
			and
			(CardSuit(CardsGet(aPile,i))=StarterSuit) then begin
			HisNob:=true;
			IF show then begin
				showp[showi].message:='His Nob';
				showp[showi].points:=1;
				showp[showi].refer[1]:=i;
				showp[showi].refer[2]:=5;
				showi:=showi+1;
			end;
			exit;
		end;
end;

function playvalue(n:integer;hand:cardset;count:integer):integer;

	{ Return the value of a played sequence of 'n' cards. }

	var
		i,j,total:integer;
		work:cardset;

	begin
		IF (count=15) or (Count=31)
			then total:=2
			ELSE total:=0;
		i:=n;
		while i>1 DO begin
			for j:= 1 to i DO work[j]:=hand[n+1-j];
			IF i>2 then IF run(i,work) then begin
				playvalue:=total+i;
				exit;
			end;
			IF (i<=4) and (pairs(i,work)=i*(i-1)) then begin
				playvalue:=total+i*(i-1);
				exit;
			end;
			i:=i-1;
		end;
		playvalue:=total;
	end;

function CommonScore(Temp:CardSet):Word;

var
	i:integer;

begin
	i:=
		Fifteens(CRIBHANDSIZE+1,Temp)+
		Runs(CRIBHANDSIZE+1,Temp)+
		Pairs(CRIBHANDSIZE+1,Temp);
	CommonScore:=i;
end;

function ScoreHand(const aPile:PileOfCards;aStarter:tcard):Word;

var
	i:integer;
	Temp:CardSet;

begin
	for i:=1 to CRIBHANDSIZE do Temp[i]:=CardsGet(aPile,i);
	Temp[5]:=aStarter;
	i:=CommonScore(Temp);
	if hisNob(aPile,CardSuit(aStarter)) then i:=i+1;
	IF flush(CRIBHANDSIZE+1,Temp) then
		i:=i+5
	ELSE IF flush(CRIBHANDSIZE,Temp) then
		i:=i+4;
	ScoreHand:=i;
end;

procedure dealNew(var aState:CribStateRec);

{ deal new hands to each player }

var
	i:integer;
	First,Second:playerindex;

begin
	IF aState.WhosCrib=PC then begin
		First:=HUMAN;
		Second:=PC;
	end
	ELSE begin
		First:=PC;
		Second:=HUMAN;
	end;
	with aState do for i:=0 to CRIBDEALSIZE-1 DO begin
		CardsAdd(Players[First].TheHand,CardsRemovetop(Pack));
		CardsAdd(Players[Second].TheHand,CardsRemovetop(Pack));
	end;
	aState.Players[First].CardCount:=6;
	aState.Players[Second].CardCount:=6;
end;

procedure Deal2(var aState:CribStateRec);

{ deal new hands with dup saving }

var
	i:integer;

begin
	dealNew(aState);
	{ If this is not the duplicate round then save the deal in the
		temporary storage set up for it. This will be saved later to
		the dup save file after the starter is selected. }
	if (not PlayDuplicate) or (PlayDuplicate and (not IsDupGame)) then begin
		with aState do begin
			for i:=1 to CardsSize(Players[pc].TheHand) do
				DupRec.pcHand[i]:=CardsGet(Players[pc].TheHand,i);
			for i:=1 to CardsSize(Players[human].TheHand) do
				DupRec.humanHand[i]:=CardsGet(Players[human].TheHand,i);
		end;
	end;
end;

procedure CSFDealHand(var aState:CribStateRec);

var
	i:integer;
	aPlayer:playerindex;
	aCard:TCard;

begin
	with aState do begin
		CardsShuffle(Pack,Shuffles);
		if (PlayDuplicate) and (IsDupGame) 
			then DealDup(aState)
			else Deal2(aState);

		{ adjust out of play cards for each player }
		for aPlayer:=1 to CribNumPlayers do for i:=1 to CRIBDEALSIZE do begin
			aCard:=CardsGet(Players[aPlayer].TheHand,i);
			Players[aPlayer].OutOfPlay[CardPip(aCard),CardSuit(aCard)]:=True;
			if (aPlayer = HUMAN) then faceupCard(Players[aPlayer].TheHand.ref(i)^);
		end;
	end;
	CSFNewGo(aState);
end;

procedure CSFNewGo(var aState:CribStateRec);

begin
	NextSequence(aState);
	with aState do begin
		PlayCount:=0;
		FirstToGo:=NONE;
		LastToPlay:=NONE;
	end;
	the_go_flag:=FALSE;
end;

procedure saveDupRec(var aState:CribStateRec);

{ Append the current "DupRec" to the duplicate hands list. }

var
	P:PDupRec;

begin
	dupRec.starter:=CardsGettop(aState.StarterPile); { record it for saving }
	New(P);
	P^:=DupRec;
	DupList.Insert(P);
end;

procedure CSFPostStarter(var aState:CribStateRec);

var
	aPlayer:playerindex;
	aCard:TCard;

begin
	with aState do begin
		for aPlayer:=1 to CribNumPlayers do begin
			aCard:=CardsGettop(StarterPile);
			Players[aPlayer].OutOfPlay[CardPip(aCard),CardSuit(aCard)]:=True;
		end;
		NextToPlay:=WhosCrib;
	end;
	if (not PlayDuplicate) or (PlayDuplicate and (not IsDupGame)) then SaveDupRec(aState);
end;

procedure dealDup(var aState:CribStateRec);

{ Deal the next duplicate hand by reading from the dup file.
	If there are no more duplicate hands available from the dup file
	then just deal a new one.

	The dup file must be open for reading at this point. }

var
	i:integer;
	DupRecPtr:PDupRec;

begin
	if DupList.Count>DupHand then {if ioResult=0 then} with aState do begin
		DupRecPtr:=DupList.At(DupHand);
		for i:=1 to 6 do CardsAdd(Players[pc].TheHand,dupRecPtr^.HumanHand[i]);
		for i:=1 to 6 do CardsAdd(Players[Human].TheHand,dupRecPtr^.pcHand[i]);
		CardsEmpty(aState.StarterPile);
		CardsAdd(aState.StarterPile,DupRecPtr^.Starter);
		Inc(DupHand);
	end
	else begin
		DupOverFlow:=True;
		CardsShuffle(aState.Pack,Shuffles);
		DealNew(aState);
	end;
end;

procedure nextsequence(var aState:CribStateRec);

begin
	pstart:=pend+1;
	aState.PlayCount:=0;
end;

function NextPlayerClockwise(pnum:playerindex):playerindex;

{ return the player index clockwise from player "pnum" }

begin
	NextPlayerClockwise:=1+(pnum mod CribNumPlayers);
end;

function CSFGetCribScore(const aState:CribStateRec):Word;

var
	i, j:integer;
	Temp:CardSet;
	pile:PPileOfCards;

begin
	for i:=1 to CRIBHANDSIZE do Temp[i]:=CardsGet(aState.TheCrib,i);
	Temp[5]:=CardsGettop(aState.StarterPile);
	i:=CommonScore(Temp);

	{ + his nobs }

	pile:= new(PPileOfCards, Construct(5));
	for j:= 1 to 4 do pile^.add(temp[j]);
	if hisNob(pile^, CardSuit(CardsGettop(aState.StarterPile))) then i:=i+1;
	dispose(pile, Destruct);

	IF flush(CRIBHANDSIZE+1,Temp) then i:=i+5;
	CSFGetCribScore:=i;
end;

function CSFGetHandScore(const aState:CribStateRec;pnum:playerindex):Word;

var
	i,j:integer;
	Temp:CardSet;

begin
	for i:=1 to CRIBHANDSIZE do Temp[i]:=CardsGet(aState.Players[pnum].TheHand,i);
	Temp[5]:=CardsGettop(aState.StarterPile);
	i:=CommonScore(Temp);
	if hisNob(aState.Players[pnum].TheHand,CardSuit(CardsGettop(aState.StarterPile))) then i:=i+1;
	IF flush(CRIBHANDSIZE+1,Temp) then
		i:=i+5
	ELSE IF flush(CRIBHANDSIZE,Temp) then
		i:=i+4;
	CSFGetHandScore:=i;
end;

procedure SetupDupGame;

{ Setup for the start of a duplicate game (use the hands stored
	in the dup list). }

begin
	(*
	assign(dupFile,SaveDirectory+dupFileName);
	{$I-} Reset(dupFile); {$I+} { open for reading }
	IsDupGame:=(IOResult=0);
	DupFileEnd:=False;
	*)
	DupHand:=0; { index into the collection }
	IsDupGame:=True;
	DupOverFlow:=False;
end;

procedure freeDupList;

	procedure FreeIt(Item:Pointer);
	
	begin
		Dispose(PDupRec(Item));
	end;

begin
	DupList.ForEach(@FreeIt);
	DupList.DeleteAll;
end;

procedure DrawForFirstCrib;

var
	pDraw,cDraw:byte;
	pcPick,j:integer;

begin
	pcPick:=RandomPick(DECK_SIZE);
	cdraw:=CardsRemove(CribState.Pack,pcPick);
	pdraw:=CardsRemovetop(CribState.Pack); { fudge }
	repeat
		j:=pcPick-1; { number of cards left }
		pdraw:=CardsRemove(CribState.Pack, RandomPick(j));
		while CardPip(pDraw)=CardPip(cDraw) do pdraw:=CardsRemove(CribState.Pack, RandomPick(j));
	until CardPip(pDraw)<>CardPip(cDraw);
	IF CardPip(pDraw)<CardPip(cDraw)
		then CribState.WhosCrib:=HUMAN
		else CribState.WhosCrib:=PC;
end;

function RandomPick(n:integer):integer;

begin
	RandomPick:=Random(n div 2)+1+(n div 2);
end;

procedure chooseDiscards(whom:playerindex;var choice1,choice2:integer);

{	Perform an analysis of "whom"'s hand for discarding to the crib.
	Return the index of the choices in "choice1" and "choice2". }

var
	rcounts:array [1..max6t4] of integer; { real point counts }
	scounts:array [1..max6t4] of real;	 { simulated point counts }
	maxIndex,maxcount:integer;
	Maximum:real;
	i,j,k,n:integer;
	Work:cardset;
	p:TPip;
	cardFreq:array[TACE..TKING] of integer;

begin

	{ Make up the temporary card frequency array }

	for p:=TACE to TKING do cardFreq[p]:=4; { initially 4 cards of each pip }
	for i:=1 to CRIBDEALSIZE do dec(cardFreq[CardPip(CardsGet(CribState.Players[Whom].TheHand, i))]);

	{ calculate real value of all sets of 4 from the 6 cards dealt }

	for i:=1 to max6t4 DO begin
		for j:=1 to CRIBHANDSIZE DO work[j]:=CardsGet(CribState.Players[Whom].TheHand, comb6t4[i,j]);
		rcounts[i]:=fifteens(CRIBHANDSIZE,work)+Runs(CRIBHANDSIZE,work)+Pairs(CRIBHANDSIZE,work);
		IF Flush(CRIBHANDSIZE,work) then rcounts[i]:=rcounts[i]+CRIBHANDSIZE;
	 scounts[i]:=0.0;
  end;

	{ find the maximum }

	MaxCount:=-1;
	for i:=1 TO 15 DO IF rcounts[i]>MaxCount then MaxCount:=rcounts[i];

	for i:=1 to 15 DO
		IF (rcounts[i]>=MaxCount-1) or (rcounts[i]<=MaxCount+1)	then begin
			for j:=1 to CRIBHANDSIZE DO work[j]:=CardsGet(CribState.Players[Whom].TheHand, comb6t4[i,j]);
			n:=0; { cumulative points scores }
			k:=0; { total number of ways of getting those points }
			for j:=TACE to TKING DO begin
				work[5]:=TCard(j);
				IF cardFreq[j]>0 then begin
					n:=n+(Fifteens(5,work)+Runs(5,work)+Pairs(5,work))*cardFreq[j];
					k:=k+cardFreq[j];
				end;
			end;
			IF flush(4,work) then n:=n+5; { adjust for 5-flush }
			for j:=0 to 3 DO IF hisNob(CribState.Players[whom].TheHand,TCard(j)) then n:=n+4;
			scounts[i]:=n/k;
		end;
	{ find the best hand }
	MaxIndex:=0;
	Maximum:=-1.0;
	for i:=1 TO 15 DO
		if rcounts[i]+scounts[i]>Maximum
			then begin
				Maximum:=rcounts[i]+scounts[i];
				MaxIndex:=i;
			end;

	n:=1;
	for i:=1 TO CRIBDEALSIZE DO
	 IF	  (i<>comb6t4[MaxIndex,1])
		 and (i<>comb6t4[MaxIndex,2])
		 and (i<>comb6t4[MaxIndex,3])
		 and (i<>comb6t4[MaxIndex,4])
	 then begin
			if n=1 then
				choice1:=i
			else
				choice2:=i;
			n:=n+1;
		end;
end;

procedure CSFDone(var aState:CribStateRec);

var
	i:integer;

begin
	with aState do begin
		for i:=1 to CribNumPlayers do with Players[i] do begin
			TheHand.Destruct;
		end;
		CardsDone(PlayPile);
		CardsDone(StarterPile);
		CardsDone(TheCrib);
		CardsDone(Pack);
	end;
end;

procedure CSMDone;
begin
	CSFDone(CribState);
	{ dispose of the dup list }
	FreeDupList;
	DupList.Done;
end;

procedure CSFEndHand(var aState:CribStateRec);
var
	i:playerindex;
begin
	Show:=False;
	Showi:=1;
	with aState do begin
		for i:=1 to CribNumPlayers do with Players[i] do
			SessionHandPoints:=SessionHandPoints+CSFGetHandScore(aState,i);
		SessionCribPoints:=SessionCribPoints+CSFGetCribScore(aState);
		WhosCrib:=NextPlayerClockwise(WhosCrib);
		Inc(HandsPlayed);
	end;
end;

function CSFPlayPoints(const aState:CribStateRec):integer;
{ return the number of points for the last play or 0 }
var
	j:integer;
	work:cardset;
begin
	if pend>=pstart then with aState do begin
		for j:=pstart to pend DO work[j-pstart+1]:=CardsGet(PlayPile,j);
		CSFPlayPoints:=PlayValue(pend-pstart+1,work,PlayCount);
	end
	else
		CSFPlayPoints:=0;
end;

procedure CSFEndPlay(var aState:CribStateRec);
begin
	CSFNewGo(aState);
	with aState do while CardsSize(aState.PlayPile)>0 do CardsMovetop(aState.PlayPile,Players[PlayedFrom[CardsSize(aState.PlayPile)]].TheHand);
end;

procedure CSFPlayCard(var aState:CribStateRec;CardNo:integer);
{ Play the "CardNo"th card for the current player }
begin
	with aState do begin
		CardsMove(Players[NextToPlay].TheHand,CardNo,PlayPile);
		PlayedFrom[CardsSize(PlayPile)]:=NextToPlay;
		Inc(PlayCount,CardValue(CardPip(CardsGettop(PlayPile))));
	end;
	Inc(pend);
	CPMPlayedNo:=CardNo;
end;

function PipProb(const aState:CribStateRec;const aPlayer:playerindex;const aPip:TPip):integer;

	{ probability (0..4) according to "aPlayer" that "aPip" is still in play }

	var
		Count:integer;
		aSuit:TSuit;

	begin
		Count:=0;
		for aSuit:=TCLUB to TSPADE do
			if not aState.Players[aPlayer].OutOfPlay[aPip,aSuit] then Inc(Count);
		PipProb:=Count;
	end;

procedure CPFPlay(var aState:CribStateRec;pnum:playerindex);

{ play one of "pnum"s cards. check for "IsGo" before calling this function }

var
	aPlay:integer;

	function OldPlay(var aState:CribStateRec;pnum:playerindex):integer;

	{ keeps the total count during play }
	{ this is the old play algorithm }
	{ enter this procedure when the computer has at least one card to play }

	var
		i,j,k,Ptr,Cardsleft:integer;
		value:real; { working variable to record highest value so far }
		scount:integer; { simulated count }
		Bestyet:real;
		Response:TPip;
		myPoints:integer;
		work:cardset;

	begin
		Ptr:= 0;
		Bestyet:= -30.0; { 29 points is the best }
		Cardsleft:= 0;
		for Response:= TACE to TKING DO Cardsleft:= Cardsleft + PipProb(aState, pnum, response);
		for i:=1 to CardsSize(aState.Players[pnum].TheHand) DO begin
			IF aState.PlayCount+CardValue(CardPip(CardsGet(aState.Players[pnum].TheHand,i)))<=31 then begin

				{ calculate my points if I played this card }
				scount:=aState.PlayCount+CardValue(CardPip(CardsGet(aState.Players[pnum].TheHand,i)));
				if pend >= pStart then for j:=pstart to pend DO work[j-pstart+1]:=CardsGet(aState.PlayPile,j);
				work[pend - pstart + 2]:= CardsGet(aState.Players[pnum].TheHand, i);
				mypoints:= playvalue(pend - pstart + 2, work, scount);

				{ calculate the value of my opponent's possible responses }
				value:= 0;
				if (pend - pstart + 3) <= MAXSET then begin
					for Response:= TACE to TKING do begin
						if scount + CardValue(response) <= 31 then begin
							work[pend - pstart + 3]:= MakeCard(response,TSPADE); { setup the simulated hand }
							value:= value + playvalue(pend - pstart + 3, work, scount + CardValue(response)) * PipProb(aState, pnum, response);
						end
						else
							value:= value - PipProb(aState,pnum,response);
					end;
				end;
				value:= myPoints - value / cardsleft;
				if value > Bestyet then begin
					Bestyet:= value;
					ptr:= i;
				end;
			end;
		end; { all cards }

		if Ptr<>0 then begin
			aState.PlayCount:=aState.PlayCount+CardValue(CardPip(CardsGet(aState.Players[pnum].TheHand,Ptr)));
			Inc(pend);
		end;
		OldPlay:=Ptr;
		CPMPlayedNo:=Ptr;
	end;

	function CPFGetPlay(var aState:CribStateRec;pnum:playerindex):integer;

	{ return the card number to play. Assume at least one of the
		cards is playable }

	begin
		if aState.PlayCount = 31 then NextSequence(aState);
		CPFGetPlay:= OldPlay(aState,pnum);
	end;

begin
	aPlay:=CPFGetPlay(aState,pnum);
	with aState do if aPlay>0 then begin
		CardsMove(Players[pnum].TheHand,aPlay,PlayPile);
		PlayedFrom[CardsSize(PlayPile)]:=pnum;
	end;
end;

function IsGo(const aState:CribStateRec;pnum:playerindex):boolean;
var
	i:integer;
begin
	IsGo:=True;
	with aState do for i:=1 to CardsSize(Players[pnum].TheHand) do
		if CardValue(CardPip(CardsGet(Players[pnum].TheHand,i)))<=(31-PlayCount) then IsGo:=False;
end;

function CSFWinner(const aState:CribStateRec):boolean; { true when somebody has won the current game }
var
	pnum:playerindex;
begin
	CSFWinner:=False;
	with aState do for pnum:=1 to CribNumPlayers do if player_scores[pnum].FrontPeg=MAX_SCORE then begin
		CSFWinner:=True;
		Break;
	end;
end;

function ShouldCountLastCard:boolean;
begin
	ShouldCountLastCard:=(not CSFWinner(CribState)) and (not the_go_flag) and (CribState.PlayCount<31);
end;
	
procedure TallyPoints(pnum:playerindex;nPoints:Word);
begin
	with player_scores[pnum] do begin
		BackPeg:=FrontPeg;
		FrontPeg:=Min(MAX_SCORE,FrontPeg+nPoints);
	end;
end;

procedure CBPreGame;
var
	i:integer;
begin
	for i:=1 to CribNumPlayers do with player_scores[i] do begin
		FrontPeg:=0;
		BackPeg:= -1;
	end;
end;

{$ifdef TEST}

procedure test_ShouldCountLastCard;
begin
	player_scores[PC].FrontPeg:=MAX_SCORE-1;
	the_go_flag:=FALSE;
	CribState.PlayCount:=31;
	AssertIsFalse(ShouldCountLastCard);
	CribState.PlayCount:=30;
	AssertIsTrue(ShouldCountLastCard);
end;

begin
	suite.Add(@test_PipValue);
	Suite.Add(@Test_GameRecorder_BeginHand);
	Suite.Add(@Test_GameRecorder_AddPoints);
	Suite.Add(@Test_GameRecorder_EndHand);
	Suite.Add(@Test_GameRecorder_string_length);
	Suite.Add(@Test_GameRecorder_Score);
	Suite.Add(@Test_GameRecorder_FromString);
	Suite.Add(@Test_GameRecorder_NextCrib);
	Suite.Add(@test_ShouldCountLastCard);
	suite.Run('cribbage');
{$endif}
end.
