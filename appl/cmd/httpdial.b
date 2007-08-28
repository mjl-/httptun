implement Httpdial;

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
proxyaddr: string;

Httpdial: module {
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
	arg->setusage(arg->progname()+" [-d] [-p proxyaddr] url destaddr");
	while((c := arg->opt()) != 0)
		case c {
		'd' =>	dflag++;
			http->debug++;
		'p' =>	proxyaddr = arg->earg();
		* =>	arg->usage();
		}
	args = arg->argv();
	if(len args != 2)
		arg->usage();

	ustr := hd args;
	destaddr := hd tl args;

	(u, err) := Url.unpack(ustr);
	if(err != nil)
		fail(err);
	h := Hdrs.new(nil);
	h.set("Transfer-Encoding", "chunked");
	h.set("Destination", destaddr);
	h.set("Content-Type", "text/plain");
	req := ref Req(POST, u, HTTP_11, h, nil, proxyaddr);

	(fd, derr) := req.dial();
	if(derr != nil)
		fail(derr);
	b := bufio->fopen(fd, Sys->OREAD);
	if(b == nil)
		fail(sprint("bufio fopen: %r"));

	err = req.write(fd);
	if(err != nil)
		fail(err);

	(resp, rerr) := Resp.read(b);
	if(rerr != nil)
		fail(rerr);
	if(resp.st != "200")
		fail("response not 200: "+resp.st);
	if(!resp.h.has("Transfer-Encoding", "chunked"))
		fail("response not chunked");
	say("have connection");

	spawn httpwriter(fildes(0), fd);
	spawn keepalivewriter(fd);
	httpreader(b, fildes(0));
}

include "chunk.b";

httpwriter(infd, httpfd: ref Sys->FD)
{
	say("httpwriter starting");
	for(;;) {
		n := sys->read(infd, d := array[Sys->ATOMICIO] of byte, len d);
		if(n < 0)
			fail(sprint("reading from stdin: %r"));
		if(n == 0) {
			say("eof from stdin");
			break;
		}
		say("have data to send to http");
		if(sys->write(httpfd, od := chunkresp(d[:n]), len od) != len od)
			fail(sprint("writing to http: %r"));
		say(sprint("wrote to http: %s", string od));
	}
	say("httpwriter done");
}

httpreader(httpb: ref Iobuf, outfd: ref Sys->FD)
{
	say("httpreader starting");
	for(;;) {
		(clen, err) := getchunklen(httpb);
		if(err != nil)
			fail(err);
		if(clen == 0)
			break;
		say(sprint("have chunk length, %d", clen));
		n := httpb.read(array[1] of byte, 1);
		if(n < 0)
			fail(sprint("reading keepalive byte: %r"));
		if(n == 0)
			fail("eof on keepalive byte");
		clen--;

		say(sprint("httpreader, starting on chunk len=%d", clen));
		while(clen > 0) {
			have := httpb.read(d := array[clen] of byte, clen);
			if(have < 0)
				fail(sprint("reading chunk: %r"));
			if(have == 0)
				fail(sprint("premature eof reading chunk"));
			if(sys->write(outfd, d[:have], have) != have)
				fail(sprint("writing chunk: %r"));
			say(sprint("read from http: %s", string d[:have]));
			clen -= have;
		}
		l := getline(httpb);
		if(l != nil)
			return say("line after chunk not empty");
	}
	say("httpreader done");
}

keepalivewriter(fd: ref Sys->FD)
{
	for(;;) {
		sys->sleep(3*1000);
		if(fprint(fd, "1\r\nk\r\n") < 0)
			fail(sprint("keep alive write: %r"));
	}
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
