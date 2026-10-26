#!/usr/bin/env python3
"""Minimal stand-in for Supabase Realtime (Phoenix protocol vsn 1.0.0, broadcast only).

Used by tests/run_net_test.sh online, so online play can be tested without a Supabase
project. It follows the documented message shapes (phx_join / phx_reply / broadcast /
heartbeat / phx_leave) and reports the message rate, counted the way Supabase bills
it (each message sent plus each delivery), to check we stay under the free-tier quota.

Usage: python3 tests/mock_realtime.py [port]   (needs: pip install websockets)
"""
import asyncio
import json
import sys
import time

import websockets

topics = {}  # topic -> set of websockets
counts = []  # timestamps of counted events


def count(n=1):
    now = time.time()
    counts.extend([now] * n)


async def handler(ws):
    joined = set()
    try:
        async for raw in ws:
            msg = json.loads(raw)
            topic, event, ref = msg.get("topic"), msg.get("event"), msg.get("ref")
            if event == "phx_join":
                topics.setdefault(topic, set()).add(ws)
                joined.add(topic)
                await ws.send(json.dumps({"topic": topic, "event": "phx_reply", "ref": ref,
                                          "join_ref": msg.get("join_ref"),
                                          "payload": {"status": "ok", "response": {}}}))
            elif event == "heartbeat":
                await ws.send(json.dumps({"topic": "phoenix", "event": "phx_reply", "ref": ref,
                                          "payload": {"status": "ok", "response": {}}}))
            elif event == "phx_leave":
                topics.get(topic, set()).discard(ws)
                joined.discard(topic)
            elif event == "broadcast" and topic in joined:
                out = json.dumps({"topic": topic, "event": "broadcast", "ref": None,
                                  "payload": msg.get("payload")})
                others = [o for o in topics.get(topic, set()) if o is not ws]
                count(1 + len(others))
                for o in others:
                    try:
                        await o.send(out)
                    except websockets.ConnectionClosed:
                        pass
    except websockets.ConnectionClosed:
        pass
    finally:
        for t in joined:
            topics.get(t, set()).discard(ws)


async def report():
    peak = 0
    while True:
        await asyncio.sleep(1.0)
        now = time.time()
        recent = len([t for t in counts if now - t <= 1.0])
        del counts[: max(0, len(counts) - 5000)]
        peak = max(peak, recent)
        if recent:
            print(f"msgs/s={recent} peak={peak}", flush=True)


async def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8787
    async with websockets.serve(handler, "127.0.0.1", port, max_size=2 ** 22):
        print(f"mock realtime on ws://127.0.0.1:{port}/realtime/v1/websocket", flush=True)
        await report()


asyncio.run(main())
