{ (C) 1998 Wesley Steiner }

{$MODE FPC}

{$ifdef DEBUG}
{!$define TEST_DUPLICATE} { set duplicate game as the default }
{$endif DEBUG}

{$I platform}

program QuickCribbage;

uses
	{$ifdef TEST} punit, {$endif}
	strings,
	windows,
	std,
	stringsx,
	windowsx,
	cribbage,
	quick,
	winqcktbl, {$ifdef TEST} winqcktbl_tests, {$endif}
	wincrbtbl, {$ifdef TEST} wincrbtbl_tests, {$endif}
	quickWin;

{$R menus.res}
{$R main.res}
{$I punit.inc}

const
	PERSISTENCE_HEADING='ScoreBoard';
	REGKEY_SCOREBOARD=PERSISTENCE_HEADING;
	REGKEY_GAMES='Games';

	KEY_SHOWPLAYCOUNT='ShowPlayCount';
	KEY_OUTSIDEFRONTPEG='OutsideFrontPeg';
	KEY_OUTSIDEREARPEG='OutsideRearPeg';
	KEY_INSIDEFRONTPEG='InsideFrontPeg';
	KEY_INSIDEREARPEG='InsideRearPeg';
	KEY_CURRENTGAME='CurrentGame';

	CM_SHOWPLAYCOUNT=296;
	CM_PLAYDUPLICATE=297;
	CM_STATISTICS=298;
	CM_VIEWSCOREPAD=301;
	
type
	MainApp_ptr=^MainApplication;

	MainFrameWindowPtr=^MainFrameWindow;
	MainFrameWindow=object(quickWin.FrameWindow)
		function FileNewOk:boolean; virtual;
		function MinFrmHt:word; virtual;
		function MinFrmWd:word; virtual;
		function OnCmd(aCmdId:UINT):LONG; virtual;
		function OnMsg(aMsg:UINT;wParam:WPARAM;lParam:LPARAM):LONG; virtual;
		function OnShowPlayCount:LONG;
		function OnStatistics:LONG;
		function OnDeal:LONG;
		function OnHint:LONG;
	end;
	
	MainFramePtr=^MainFrame;
	MainFrame=object(quickWin.Frame)
		constructor Construct;
		function OnSignal(signal_id:signalId):LONG;
		function OnStart:LONG; virtual;
		function Owner:MainApp_ptr;
	private
		function OnDiscardComplete:LONG;
	end;

	MainApplication=object(quickWin.Application)
		constructor Construct;
		destructor Destruct; virtual;
		function Frame:MainframePtr;
		function HomePageUrl:pchar; virtual;
		procedure InitMainWindow; virtual;
		procedure OnNew; virtual;
	private
		function CurrentTimeKey:string; {$ifdef TEST} virtual; {$endif}
		function FormatCurrentTimeKey(var aSystemTime:TSYSTEMTIME):string;
		function GameWinRegKey(const prefix:pchar):string;
	end;

var
	main_application:MainApplication;

function MainApplication.Frame:MainframePtr;
begin
	Frame:=MainFramePtr(inherited Frame);
end;

function GetMainFrame:MainFramePtr;
begin
	GetMainFrame:=main_application.Frame; 
end;

function MainApplication.FormatCurrentTimeKey(var aSystemTime:TSYSTEMTIME):string;
var
	i:integer;
	s,r:string;
begin
	r:='';
	Str(aSystemTime.wYear:4,s);
	r:=r+s;
	Str(aSystemTime.wMonth:2,s);
	r:=r+'-'+s;
	Str(aSystemTime.wDay:2,s);
	r:=r+'-'+s;
	Str(aSystemTime.wHour:2,s);
	r:=r+'_'+s;
	Str(aSystemTime.wMinute:2,s);
	r:=r+'-'+s;
	Str(aSystemTime.wSecond:2,s);
	r:=r+'-'+s;
	for i:= 1 to Length(r) do if r[i]=' ' then r[i]:='0';
	FormatCurrentTimeKey:=r;
end;

{$ifdef TEST}

type
	FakeMainApp=object(MainApplication)
		myTimeString:string;
		constructor Construct;
		function FullName:pchar; virtual;
		function CurrentTimeKey:string; virtual;
	end;

constructor FakeMainApp.Construct; begin end;
function FakeMainApp.FullName:PChar; begin FullName:=StrNew('Fake Full Name'); end;
function FakeMainApp.CurrentTimeKey:string; begin CurrentTimeKey:=myTimeString; end;

procedure Test_FormatCurrentTimeKey;
var
	aApp:FakeMainApp;
	testTime:TSYSTEMTIME;
begin
	aApp.Construct;
	testTime.wYear:=2001; 
    testTime.wMonth:=9; 
    testTime.wDay:=5; 
    testTime.wHour:=6; 
    testTime.wMinute:=4; 
    testTime.wSecond:=3; 
	punit.Assert.EqualStr('2001-09-05_06-04-03',aApp.FormatCurrentTimeKey(testTime));
end;

{$endif}

function MainApplication.CurrentTimeKey:string;
var
	localTime:TSYSTEMTIME;
begin
	GetLocalTime(localTime);
	CurrentTimeKey:=FormatCurrentTimeKey(localTime);
end;

function MainApplication.GameWinRegKey(const prefix:pchar):string;
begin
	GameWinRegKey:=StrPas(prefix)+'\'+CurrentTimeKey;
end;

{$ifdef TEST}

procedure Test_GameWinRegKey;
var
	aApp:FakeMainApp;
begin
	aApp.Construct;
	aApp.myTimeString:='TIMESTRING';
	punit.Assert.EqualStr('PREFIX\TIMESTRING',aApp.GameWinRegKey('PREFIX'));
end;

{$endif}

constructor MainFrame.Construct;
begin //writeln('MainFrame.Construct');
	inherited Construct(@main_application,FALSE);
	show_play_count:=main_application.GetBooleanData(REGKEY_ROOT,KEY_SHOWPLAYCOUNT,show_play_count);
end;

function MainFrameWindow.OnDeal:LONG;
begin
	wincrbtbl.Deal;
	EnableMenuItem(GetMenu(Handle), CM_HINT, MF_BYCOMMAND or MF_ENABLED);
	HumanDiscards;
	OnDeal:=0;
end;

constructor MainApplication.Construct;
begin
	inherited Construct('Cribbage');
	game_recorder.FromString(GetStringData(REGKEY_ROOT, KEY_CURRENTGAME, ''));
	Splash;
end;

destructor MainApplication.Destruct;
begin //writeln('MainApplication.Destruct');
	SetIntegerData(REGKEY_SCOREBOARD,KEY_OUTSIDEFRONTPEG,player_scores[HUMAN].FrontPeg);
	SetIntegerData(REGKEY_SCOREBOARD,KEY_OUTSIDEREARPEG,player_scores[HUMAN].BackPeg);
	SetIntegerData(REGKEY_SCOREBOARD,KEY_INSIDEFRONTPEG,player_scores[PC].FrontPeg);
	SetIntegerData(REGKEY_SCOREBOARD,KEY_INSIDEREARPEG,player_scores[PC].BackPeg);
	CSMDone;
	inherited Destruct;
end;

procedure MainApplication.InitMainWindow;
begin //writeln('MainApplication.InitMainWindow');
	MainWindow:=New(MainFramePtr,Construct);
	MainWindow^.MyFrameWindow:=New(MainFrameWindowPtr,Construct);
	MainWindow^.Create;
	Frame^.SetTabletopWindow(PTabletop(New(OMainTabletop_ptr, Construct(
		RGB(0,127,0),
		LoadBitmapFromFile(PChar(GetStringData(KEY_TABLETOP, KEY_TABLETOP_IMAGEPATH, ''))),
		GetBooleanData(KEY_TABLETOP, KEY_TABLETOP_USEIMAGE, FALSE)))));
end;

function MainFrameWindow.OnHint:LONG;
begin
	DoHint;
	ProcessDiscards;
	OnHint:=0;
end;

function MainFrameWindow.FileNewOk:boolean;
begin
	FileNewOk:=(PegScore(pc)=0) and (PegScore(human)=0);
end;

procedure MainApplication.OnNew;
begin
	inherited OnNew;
	wincrbtbl.AbortGame;
	DeleteData(REGKEY_ROOT, KEY_CURRENTGAME);
	wincrbtbl.OnNewGame;
end;

function MainFrameWindow.OnShowPlayCount:LONG;
begin
	Toggle(show_play_count);
	SetMenuBoolean(GetMenu(AppWnd),CM_SHOWPLAYCOUNT,show_play_count);
	GetMainFrame^.Owner^.SetBooleanData(REGKEY_ROOT,KEY_SHOWPLAYCOUNT,show_play_count);
	OnShowPlayCount:=0;
end;

type
	GameLibraryP=^GameLibrary;
	GameLibrary=object
		constructor Construct;
		function GamesPlayed:quantity; test_virtual
		function GamesWonBy(who:playerIndex):quantity; test_virtual
		function Skunked(who:playerIndex):quantity; test_virtual
	end;

function GameLibrary.Skunked(who:playerIndex):quantity;
begin
	Skunked:=0;
end;
 
constructor GameLibrary.Construct;
begin
end;

function GameLibrary.GamesPlayed:quantity;
begin
	GamesPlayed:=0;
end;

function GameLibrary.GamesWonBy(who:playerIndex):quantity; 
begin
	GamesWonBy:=0;
end;

{$ifdef TEST}

procedure test_GameLibrary_GamesPlayed;
var
	testee:GameLibrary;
begin
	testee.Construct;
	AssertAreEqual(0,testee.GamesPlayed);
end;

{$endif}
	
function CreateStatsMessage(const data:GameLibrary):ansistring;
var
	played,won:quantity;
	s:ansistring;
	function Suffix(who:playerIndex):string;
	begin
		Suffix:=' have been skunked '+Q(data.Skunked(who)=1,'once',Q(data.Skunked(who)=2,'twice',NumberToString(data.Skunked(who))+' times'))+'.';
	end;
begin
	played:=data.GamesPlayed;
	won:=data.GamesWonBy(HUMAN);
	if data.GamesPlayed=0 
		then s:='There is no data to report at this time.'
		else begin
			s:='You have won '+NumberToString(won)+' ('+NumberToString(Quantity(Round((won*100.0)/played)))+'%) of '+NumberToString(played)+' games played.';
			if (data.Skunked(HUMAN)>0) then s:=s+' You'+Suffix(HUMAN);
			if (data.Skunked(PC)>0) then s:=s+' I'+Suffix(PC);
		end;
	CreateStatsMessage:=s;
end;

{$ifdef TEST}

type
	FakeGameLibrary=object(GameLibrary)
		GamesPlayed_result,GamesWonBy_result:quantity;
		Skunked_result:array[playerIndex] of quantity;
		function GamesPlayed:quantity; virtual;
		function GamesWonBy(who:playerIndex):quantity; virtual;
		function Skunked(who:playerIndex):quantity; virtual;
	end;
	
function FakeGameLibrary.Skunked(who:playerIndex):quantity;
begin
	Skunked:=Skunked_result[who];
end;
 
function FakeGameLibrary.GamesPlayed:quantity;
begin
	GamesPlayed:=GamesPlayed_result;
end;

function FakeGameLibrary.GamesWonBy(who:playerIndex):quantity; 
begin
	GamesWonBy:=GamesWonBy_result;
end;

procedure test_CreateStatsMessage;
var
	data:FakeGameLibrary;
begin
	data.Construct;
	AssertAreEqual('There is no data to report at this time.',CreateStatsMessage(data));
	data.GamesPlayed_result:=3;
	data.GamesWonBy_result:=0;
	AssertAreEqual('You have won 0 (0%) of 3 games played.',CreateStatsMessage(data));
	data.GamesWonBy_result:=2;
	AssertAreEqual('You have won 2 (67%) of 3 games played.',CreateStatsMessage(data));
	data.GamesPlayed_result:=MAX_QUANTITY;
	data.GamesWonBy_result:=MAX_QUANTITY;
	AssertAreEqual('You have won 4294967295 (100%) of 4294967295 games played.',CreateStatsMessage(data));
	data.Skunked_result[HUMAN]:=3;
	data.Skunked_result[PC]:=5;
	AssertEndsWith(' You have been skunked 3 times. I have been skunked 5 times.',CreateStatsMessage(data));
	data.Skunked_result[PC]:=0;
	AssertEndsWith(' You have been skunked 3 times.',CreateStatsMessage(data));
	data.Skunked_result[HUMAN]:=0;
	data.Skunked_result[PC]:=12;
	AssertEndsWith(' I have been skunked 12 times.',CreateStatsMessage(data));
	data.Skunked_result[HUMAN]:=2;
	data.Skunked_result[PC]:=0;
	AssertEndsWith(' You have been skunked twice.',CreateStatsMessage(data));
	data.Skunked_result[HUMAN]:=0;
	data.Skunked_result[PC]:=1;
	AssertEndsWith(' I have been skunked once.',CreateStatsMessage(data));
end;

{$endif}

function MainFrameWindow.OnStatistics:LONG;
var
	data:GameLibrary;
begin
	data.Construct;
	MessageBox(Handle,PChar(CreateStatsMessage(data)),'Game Statistics',MB_ICONINFORMATION or MB_OK);
	OnStatistics:=0;
end;

procedure CheckScoreData(const aGameRecorder:GameRecorder);
	function MismatchedScores(who:cribbage.playerindex):boolean;
	begin
		MismatchedScores:=aGameRecorder.Score(who)<>player_scores[who].FrontPeg;
	end;
begin
	if MismatchedScores(PC) or MismatchedScores(HUMAN) then begin
		player_scores[PC].FrontPeg:=0;
		player_scores[PC].BackPeg:=-1;
		player_scores[HUMAN].FrontPeg:=0;
		player_scores[HUMAN].BackPeg:=-1;
	end;
end;

{$ifdef TEST}

procedure Test_CheckScoreData;
var
	testGameRecorder:GameRecorder;
begin
	player_scores[HUMAN].FrontPeg:=13;
	player_scores[HUMAN].BackPeg:=11;
	player_scores[PC].FrontPeg:=23;
	player_scores[PC].BackPeg:=21;
	testGameRecorder.FromString('1,-24,0,0,99');
	CheckScoreData(testGameRecorder);
	punit.Assert.Equal(0,player_scores[PC].FrontPeg);
	punit.Assert.Equal(-1,player_scores[PC].BackPeg);
	punit.Assert.Equal(0,player_scores[HUMAN].FrontPeg);
	punit.Assert.Equal(-1,player_scores[HUMAN].BackPeg);

	player_scores[HUMAN].FrontPeg:=13;
	player_scores[HUMAN].BackPeg:=11;
	player_scores[PC].FrontPeg:=23;
	player_scores[PC].BackPeg:=21;
	testGameRecorder.FromString('1,-23,12,0,99');
	CheckScoreData(testGameRecorder);
	punit.Assert.Equal(0,player_scores[PC].FrontPeg);
	punit.Assert.Equal(-1,player_scores[PC].BackPeg);
	punit.Assert.Equal(0,player_scores[HUMAN].FrontPeg);
	punit.Assert.Equal(-1,player_scores[HUMAN].BackPeg);
end;

{$endif TEST}

function MainFrame.OnStart:LONG;
begin //writeln('MainFrame.OnStart');
	OnStart:=0;
	EnableMenuItem(GetMenu(AppWnd), CM_HINT, MF_BYCOMMAND or MF_GRAYED);
	SetMenuBoolean(GetMenu(AppWnd),CM_SHOWPLAYCOUNT, show_play_count);
	{$ifdef TEST_DUPLICATE}
	PlayDuplicate:=TRUE;
	{$endif}
	CribState.WhosCrib:=game_recorder.NextCrib;
	player_scores[HUMAN].FrontPeg:=Integer(main_application.GetIntegerDataRange(REGKEY_SCOREBOARD,KEY_OUTSIDEFRONTPEG,0,CBMAXHOLEINDEX,0));
	player_scores[HUMAN].BackPeg:=Integer(main_application.GetIntegerDataRange(REGKEY_SCOREBOARD,KEY_OUTSIDEREARPEG,CBMINHOLEINDEX,CBMAXHOLEINDEX,CBMINHOLEINDEX));
	player_scores[PC].FrontPeg:=Integer(main_application.GetIntegerDataRange(REGKEY_SCOREBOARD,KEY_INSIDEFRONTPEG,0,CBMAXHOLEINDEX,0));
	player_scores[PC].BackPeg:=Integer(main_application.GetIntegerDataRange(REGKEY_SCOREBOARD,KEY_INSIDEREARPEG,CBMINHOLEINDEX,CBMAXHOLEINDEX,CBMINHOLEINDEX));
	CheckScoreData(game_recorder);
	SetFocus(MyFrameWindow^.Handle);
	wincrbtbl.Start;
	MyFrameWindow^.PostMessage(WM_DEAL, 0, 0);
end;

function MainFrameWindow.OnMsg(aMsg:UINT;wParam:WPARAM;lParam:LPARAM):LONG;
var
	buf:stringBuffer;
begin
	case aMsg of
		WM_SAVEGAMESCORE:begin
			with main_application do begin
				if aWinner then begin
					SetStringData(REGKEY_GAMES,StrPCopy(buf,CurrentTimeKey), game_recorder.ToString);
					DeleteData(REGKEY_ROOT,KEY_CURRENTGAME);
				end
				else begin
					SetStringData(REGKEY_ROOT,KEY_CURRENTGAME, game_recorder.ToString);
				end;
			end;
			OnMsg:=0;
		end;
		WM_NEXTPLAY:OnMsg:=OnNextPlay;
		WM_DEAL:OnMsg:=OnDeal;
		WM_SIGNAL:OnMsg:=GetMainFrame^.OnSignal(wParam);
		WM_START:OnMsg:=GetMainFrame^.OnStart;
		else OnMsg:=inherited OnMsg(aMsg,wParam,lParam);
	end;
end;

{$ifdef TEST}
procedure Test_main;
var
	aApp:FakeMainApp;
begin
	aApp.Construct;
	AssertAreEqual('http://www.wesleysteiner.com/quickgames/cribbage.html',aApp.HomePageUrl);
	AssertAreEqual(295,CM_HINT);
end;

procedure Test_backwards_compatibility;
begin
	AssertAreEqual(PERSISTENCE_HEADING,REGKEY_SCOREBOARD);
	AssertAreEqual('Games',REGKEY_GAMES);
	AssertAreEqual('ShowPlayCount',KEY_SHOWPLAYCOUNT);
	AssertAreEqual('OutsideFrontPeg',KEY_OUTSIDEFRONTPEG);
	AssertAreEqual('OutsideRearPeg',KEY_OUTSIDEREARPEG);
	AssertAreEqual('InsideFrontPeg',KEY_INSIDEFRONTPEG);
	AssertAreEqual('InsideRearPeg',KEY_INSIDEREARPEG);
	AssertAreEqual('CurrentGame',KEY_CURRENTGAME);
end;
{$endif TEST}

function MainFrameWindow.OnCmd(aCmdId:UINT):LONG;
begin
	case aCmdId of
		CM_SHOWPLAYCOUNT:OnCmd:=OnShowPlayCount;
		CM_STATISTICS:OnCmd:=OnStatistics;
		CM_HINT:OnCmd:=OnHint;
		else OnCmd:=inherited OnCmd(aCmdId);
	end
end;

function MainApplication.HomePageUrl:pchar;
begin
	HomePageUrl:=quick.HOMEPAGE_DIR+'cribbage.html';
end;

function MainFrame.Owner:MainApp_ptr;
begin
	Owner:=MainApp_ptr(inherited Owner);
end;

function MainFrameWindow.MinFrmWd:word; begin MinFrmWd:=700; end;
function MainFrameWindow.MinFrmHt:word; begin MinFrmHt:=630; end;

function MainFrame.OnDiscardComplete:LONG;
begin
	EnableMenuItem(GetMenu(AppWnd), CM_HINT, MF_BYCOMMAND or MF_GRAYED);
	OnDiscardComplete:=0;
end;

function MainFrame.OnSignal(signal_id:signalId):LONG;
begin
	OnSignal:=0;
	case signal_id of
		SID_DISCARDCOMPLETE:OnSignal:=OnDiscardComplete;
	end;
end;

begin
	DupList.Init(15,1);
	{$ifdef TEST}
	Suite.Add(@Test_main);
	Suite.Add(@Test_backwards_compatibility);
	Suite.Add(@Test_GameWinRegKey);
	Suite.Add(@Test_FormatCurrentTimeKey);
	Suite.Add(@Test_CheckScoreData);
	Suite.Add(@test_GameLibrary_GamesPlayed);
	Suite.Add(@test_CreateStatsMessage);
	Suite.Run('main');
	{$else}
	main_application.Construct;
	main_application.Run;
	main_application.Destruct;
	{$endif TEST}
end.
