suffix(l, suf: string): int
{
	return len l >= len suf && l[len l-len suf:] == suf;
}

getline(b: ref Iobuf): string
{
	l := b.gets('\n');
	if(suffix(l, "\r\n"))
		l = l[:len l-2];
	else if(suffix(l, "\n"))
		l = l[:len l-1];
	say("<- "+l);
	return l;
}

getchunklen(b: ref Iobuf): (int, string)
{
	l := getline(b);
	if(l == nil)
		return (0, "eof/error reading");
	(l, nil) = str->splitstrl(l, ";");
	(clen, rem) := str->toint(l, 16);
	if(rem != nil)
		return (0, "bad chunk length: "+l);
	return (clen, nil);
}

chunkresp(d: array of byte): array of byte
{
	chunklen := array of byte sprint("%x\r\n", len d+1);
	od := array[len chunklen+1+len d+2] of byte;
	od[:] = chunklen;
	od[len chunklen:] = array of byte "k";
	od[len chunklen+1:] = d;
	od[len chunklen+1+len d:] = array of byte "\r\n";
	return od;
}
