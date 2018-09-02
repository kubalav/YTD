(******************************************************************************

______________________________________________________________________________

YTD v1.00                                                    (c) 2009-12 Pepak
http://www.pepak.net/ytd                                  http://www.pepak.net
______________________________________________________________________________


Copyright (c) 2009-12 Pepak (http://www.pepak.net)
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Pepak nor the
      names of his contributors may be used to endorse or promote products
      derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL PEPAK BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

******************************************************************************)

unit downCT;
{$INCLUDE 'ytd.inc'}
{$DEFINE CONVERTSUBTITLES}
  // Convert subtitles to .srt format


interface

uses
  SysUtils, Classes, Windows,
  {$IFDEF DELPHI6_UP} Variants, {$ENDIF}
  uPCRE, uXml, HttpSend, SynaUtil,
  uOptions,
  {$IFDEF GUI}
//    guiDownloaderOptions,
    {$IFDEF GUI_WINAPI}
//      guiOptionsWINAPI_CT,
    {$ELSE}
//      guiOptionsVCL_CT,
    {$ENDIF}
  {$ENDIF}
  uDownloader, uCommonDownloader, uHLSDownloader;

type
  TDownloader_CT = class(THLSDownloader)
    private
    protected
      PlaylistInfoRegExp: TRegExp;
      PlaylistUrlRegExp: TRegExp;
      StreamUrlRegExp: TRegExp;
      StreamTitleRegExp: TRegExp;
      StreamTitle2RegExp: TRegExp;
      IFrameUrlRegExp: TRegExp;
    protected
      function GetMovieInfoUrl: string; override;
      function GetFileNameExt: string; override;
      function AfterPrepareFromPage(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean; override;
      function GetPlaylistInfo(Http: THttpSend; const Page: string; out PlaylistType, PlaylistID: string): boolean;
    public
      class function Provider: string; override;
      class function UrlRegExp: string; override;
      class function Features: TDownloaderFeatures; override;
      constructor Create(const AMovieID: string); override;
      destructor Destroy; override;
    end;

implementation

uses
  uStringConsts,
  uStrings,
  uDownloadClassifier,
  uMessages;

const
  URLREGEXP_BEFORE_ID = '';
  URLREGEXP_ID =        REGEXP_COMMON_URL_PREFIX + '(?:ceskatelevize|ct24)\.cz/.+';
  URLREGEXP_AFTER_ID =  '';

const
  REGEXP_PLAYLIST_INFO = '\bgetPlaylistUrl\s*\(\s*\[\s*\{\s*"type"\s*:\s*"(?P<TYP>.+?)"\s*,\s*"id"\s*:\s*"(?P<ID>\d+)"';
  REGEXP_PLAYLIST_URL = '"url"\s*:\s*"(?P<URL>https?:.+?)"';
  REGEXP_STREAM_URL = '"streamUrls"\s*:\s*\{\s*"main"\s*:\s*"(?P<URL>https?:.+?)"';
  REGEXP_STREAM_TITLE = '"playlist"\s*:\s*\[.*?"title"\s*:\s*"(?P<TITLE>.*?)"';
  REGEXP_STREAM_TITLE_BETTER = '"playlist"\s*:\s*\[.*?"gemius"\s*:\s*\{[^}]*"NAZEV"\s*:\s*"(?P<TITLE>.*?)"';
  REGEXP_IFRAME_URL = '<(?:iframe\b[^>]*\ssrc|a\b[^>]*\shref)="(?P<URL>(https?://[^/]+)?/ivysilani/.+?)"';

class function TDownloader_CT.Provider: string;
begin
  Result := 'CeskaTelevize.cz';
end;

class function TDownloader_CT.UrlRegExp: string;
begin
  Result := Format(REGEXP_BASE_URL, [URLREGEXP_BEFORE_ID, MovieIDParamName, URLREGEXP_ID, URLREGEXP_AFTER_ID]);
end;

class function TDownloader_CT.Features: TDownloaderFeatures;
begin
  Result := inherited Features;
end;

constructor TDownloader_CT.Create(const AMovieID: string);
begin
  inherited;
  InfoPageEncoding := peUTF8;
  PlaylistInfoRegExp := RegExCreate(REGEXP_PLAYLIST_INFO);
  PlaylistUrlRegExp := RegExCreate(REGEXP_PLAYLIST_URL);
  StreamUrlRegExp := RegExCreate(REGEXP_STREAM_URL);
  StreamTitleRegExp := RegExCreate(REGEXP_STREAM_TITLE);
  StreamTitle2RegExp := RegExCreate(REGEXP_STREAM_TITLE_BETTER);
  IFrameUrlRegExp := RegExCreate(REGEXP_IFRAME_URL);
  Referer := GetMovieInfoUrl;
end;

destructor TDownloader_CT.Destroy;
begin
  RegExFreeAndNil(PlaylistInfoRegExp);
  RegExFreeAndNil(PlaylistUrlRegExp);
  RegExFreeAndNil(StreamUrlRegExp);
  RegExFreeAndNil(StreamTitleRegExp);
  RegExFreeAndNil(StreamTitle2RegExp);
  RegExFreeAndNil(IFrameUrlRegExp);
  inherited;
end;

function TDownloader_CT.GetMovieInfoUrl: string;
begin
  Result := MovieID;
end;

function TDownloader_CT.AfterPrepareFromPage(var Page: string; PageXml: TXmlDoc; Http: THttpSend): boolean;
var
  Prot, User, Pass, Host, Port, Part, Para: string;
  PlaylistType, PlaylistID, PlaylistUrlPage, PlaylistUrl, Playlist, Url, Title: string;
begin
  inherited AfterPrepareFromPage(Page, PageXml, Http);
  Result := False;
  ParseUrl(GetMovieInfoUrl, Prot, User, Pass, Host, Port, Part, Para);
  if not GetPlaylistInfo(Http, Page, PlaylistType, PlaylistID) then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_INFO_PAGE)
  else if not DownloadPage(Http,
                           'http://www.ceskatelevize.cz/ivysilani/ajax/get-client-playlist',
                           {$IFDEF UNICODE} AnsiString {$ENDIF} ('playlist%5B0%5D%5Btype%5D=' + PlaylistType + '&playlist%5B0%5D%5Bid%5D=' + PlaylistID + '&requestUrl=' + UrlEncode(Part) + '&requestSource=iVysilani&addCommercials=1&type=flash'),
                           HTTP_FORM_URLENCODING_UTF8,
                           ['x-addr: 127.0.0.1', 'X-Requested-With: XMLHttpRequest'],
                           PlaylistUrlPage,
                           peUtf8
                          )
  then
    SetLastErrorMsg(ERR_FAILED_TO_DOWNLOAD_MEDIA_INFO_PAGE)
  else if not GetRegExpVar(PlaylistUrlRegExp, PlaylistUrlPage, 'URL', PlaylistUrl) then
    if PlaylistUrlPage <> '' then
      SetLastErrorMsg(Format(ERR_SERVER_ERROR, [PlaylistUrlPage]))
    else
      SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_INFO_PAGE)
  else if not DownloadPage(Http, JSDecode(PlaylistUrl), Playlist) then
    SetLastErrorMsg(ERR_FAILED_TO_DOWNLOAD_MEDIA_INFO_PAGE)
  else if not GetRegExpVar(StreamUrlRegExp, Playlist, 'URL', Url) then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_URL)
  else if not GetRegExpVar(StreamTitleRegExp, Playlist, 'TITLE', Title) then
    SetLastErrorMsg(ERR_FAILED_TO_LOCATE_MEDIA_TITLE)
  else
    begin
    SetName(AnsiEncodedUtf8ToString( {$IFDEF UNICODE} AnsiString {$ENDIF} (JSDecode(Title))));
    if GetRegExpVar(StreamTitle2RegExp, Playlist, 'TITLE', Title) then
      SetName(Title);
    MovieURL := JSDecode(Url);
    SetPrepared(True);
    Result := True;
    end;
end;

function TDownloader_CT.GetFileNameExt: string;
begin
  Result := '.ts';
end;

function TDownloader_CT.GetPlaylistInfo(Http: THttpSend; const Page: string; out PlaylistType, PlaylistID: string): boolean;
var
  Url, Page2: string;
begin
  Result := GetRegExpVars(PlaylistInfoRegExp, Page, ['TYP', 'ID'], [@PlaylistType, @PlaylistID]);
  if not Result then
    if GetRegExpVar(IFrameUrlRegExp, Page, 'URL', Url) then
      if DownloadPage(Http, GetRelativeUrl(GetMovieInfoUrl, Url), Page2, peUtf8) then
        Result := GetRegExpVars(PlaylistInfoRegExp, Page2, ['TYP', 'ID'], [@PlaylistType, @PlaylistID]);
end;

initialization
  RegisterDownloader(TDownloader_CT);

end.

