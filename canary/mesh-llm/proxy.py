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


async def handle(reader, writer):
    head = await reader.readuntil(b"\r\n\r\n")
    line = head.split(b"\r\n", 1)[0].decode(errors="replace")
    method, target = line.split(" ")[:2]
    print(f"{time.strftime('%H:%M:%S')} {method} {target}", flush=True)
    if REFUSE:
        writer.write(b"HTTP/1.1 403 Forbidden\r\nContent-Length: 0\r\n\r\n")
        await writer.drain()
        writer.close()
        return
    if method == "CONNECT":
        host, port = target.rsplit(":", 1)
        ur, uw = await asyncio.open_connection(host, int(port))
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
