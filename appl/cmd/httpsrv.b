implement Httplisten;

include "sys.m";
include "draw.m";
include "arg.m";
include "bufio.m";
	bufio: Bufio;
	Iobuf: import bufio;
include "string.m";
include "mhttp.m";

sys: Sys;
str: String;
http: Http;

print, sprint, fprint, fildes: import sys;
Url, Hdrs, Req, Resp, POST, HTTP_11: import http;

dflag: int;

Httplisten: module {
	init:	fn(nil: ref Draw->Context, args: list of string);
};

init(nil: ref Draw->Context, args: list of string)
{
	sys = load Sys Sys->PATH;
	arg := load Arg Arg->PATH;
	bufio = load Bufio Bufio->PATH;
	str = load String String->PATH;
	http = load Http Http->PATH;
	http->init(bufio);

	arg->init(args);
	arg->setusage(arg->progname()+" [-d]");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
			http->debug++;
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 0)
		arg->usage();

	outfd := fildes(1);
	b := bufio->fopen(fildes(0), Bufio->OREAD);
	if(b == nil)
		return say(sprint("bufio fopen: %r"));
	(req, err) := Req.read(b);
	if(err != nil)
		return error(outfd, "400", "bad request", "could not parse request: "+err);
	if(req.method != POST || req.major != 1 || req.minor != 1 || !req.h.has("Transfer-Encoding", "chunked"))
		return error(outfd, "400", "bad request", "either not a post request, not http/1.1 or not chunked transfer-encoding");
	(has, destaddr) := req.h.find("Destination");
	if(!has)
		return error(outfd, "400", "bad request", "missing destination header");
	(ok, conn) := sys->dial(destaddr, nil);
	if(ok < 0)
		return error(outfd, "404", "not found", sprint("dialing %s: %r", destaddr));

	h := Hdrs.new(nil);
	h.set("Transfer-Encoding", "chunked");
	resp := Resp.mk(HTTP_11, "200", "Fine by me", h);
	err = resp.write(outfd);
	if(err != nil)
		return say("writing response: "+err);
	say("connected");

	spawn keepalive(outfd);
	spawn httpwriter(conn.dfd, outfd);
	httpreader(b, conn.dfd);
}

include "chunk.b";

error(fd: ref Sys->FD, st, stmsg, body: string)
{
	resp := Resp.mk(HTTP_11, st, stmsg, Hdrs.new(("Connection", "close")::nil));
	err := resp.write(fd);
	if(err != nil)
		return say("writing error response: "+err);
	if(fprint(fd, "%s\n", body) < 0)
		say("writing error body: "+err);
}

keepalive(fd: ref Sys->FD)
{
	say("keepalive start");
	for(;;) {
		sys->sleep(3*1000);
		if(fprint(fd, "1\r\nk\r\n") < 0) {
			say(sprint("writing keepalive: %r"));
			break;
		}
		say("wrote keepalive");
	}
	say("keepalive done");
}

httpwriter(infd, httpfd: ref Sys->FD)
{
	say("httpwriter start");
	for(;;) {
		n := sys->read(infd, d := array[Sys->ATOMICIO] of byte, len d);
		if(n < 0)
			return say("reading from remote addr: %r");
		say(sprint("have data to write, %d", n));
		if(sys->write(httpfd, od := chunkresp(d[:n]), len od) != len od)
			return say("writing to remote http: %r");
		say(sprint("wrote to http: %s", string od));
		if(n == 0)
			break;
	}
	say("httpwriter done");
}

httpreader(httpb: ref Iobuf, remotefd: ref Sys->FD)
{
	say("httpreader start");
	for(;;) {
		(clen, err) := getchunklen(httpb);
		if(err != nil)
			return say("reading chunk length: "+err);
		if(clen == 0)
			break;
		n := httpb.read(array[1] of byte, 1);
		if(n < 0)
			return say(sprint("reading keepalive byte: %r"));
		if(n == 0)
			return say("eof on keepalive byte");
		clen--;

		say(sprint("reading chunk, len=%d", clen));
		while(clen > 0) {
			have := httpb.read(d := array[clen] of byte, clen);
			if(have < 0)
				fail(sprint("reading chunk: %r"));
			if(have == 0)
				fail(sprint("premature eof reading chunk"));
			if(sys->write(remotefd, d[:have], have) != have)
				fail(sprint("writing chunk: %r"));
			say(sprint("wrote to remote: %s", string d[:have]));
			clen -= have;
		}
		line := getline(httpb);
		if(line != nil)
			return say("line after chunk not empty");
	}
	say("httpreader done");
}

say(s: string)
{
	if(dflag)
		fprint(fildes(2), "%s\n", s);
}

fail(s: string)
{
	fprint(fildes(2), "%s\n", s);
	raise "fail:"+s;
}
