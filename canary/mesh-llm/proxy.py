"""Logs the destination of each proxied connection; with --refuse it answers 403."""

import asyncio, sys, time

REFUSE = "--refuse" in sys.argv
PORT = int(sys.argv[1])


async def pipe(r, w):
    try:
        while data := await r.read(65536):
            w.write(data)
            await w.drain()
    except Exception:
        pass
    finally:
        w.close()


def log(method, target):
    print(f"{time.strftime('%H:%M:%S')} {method} {target}", flush=True)


async def handle(reader, writer):
    # A traceback in the log would be read as contacted hosts. A request we
    # can't read is logged as <unparsed-request>, which the check reports.
    errors = (asyncio.IncompleteReadError, asyncio.LimitOverrunError, ValueError)
    try:
        line = (await reader.readuntil(b"\r\n")).decode(errors="replace").strip()
        method, target = line.split(" ")[:2]
    except asyncio.IncompleteReadError as e:
        if e.partial:
            log("?", "<unparsed-request>")
        writer.close()
        return
    except errors:
        log("?", "<unparsed-request>")
        writer.close()
        return
    log(method, target)
    try:
        while await reader.readuntil(b"\r\n") != b"\r\n":
            pass
    except errors:
        writer.close()
        return
    if REFUSE:
        writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
        await writer.drain()
        writer.close()
        return
    if method == "CONNECT":
        try:
            host, port = target.rsplit(":", 1)
            ur, uw = await asyncio.open_connection(host, int(port))
        except (OSError, ValueError):
            writer.write(b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\n\r\n")
            await writer.drain()
            writer.close()
            return
        writer.write(b"HTTP/1.1 200 Connection established\r\n\r\n")
        await writer.drain()
        await asyncio.gather(pipe(reader, uw), pipe(ur, writer))
    else:
        writer.write(b"HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\n\r\n")
        await writer.drain()
        writer.close()


async def main():
    server = await asyncio.start_server(handle, "127.0.0.1", PORT)
    async with server:
        await server.serve_forever()


asyncio.run(main())
