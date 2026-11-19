"""A UDP relay that makes a bad connection between two copies of the game, for the multiplayer test.

    python3 tests/tools/lag_relay.py LISTEN_PORT TARGET_PORT LAG_MS [JITTER_MS] [LOSS_PERCENT]

Guests connect to LISTEN_PORT on this machine; every packet, both ways, is held for LAG_MS (plus or minus
JITTER_MS) and LOSS_PERCENT of them are dropped, then passed on to the host on TARGET_PORT.
"""
import asyncio
import random
import sys


class Relay:
    def __init__(self, target, lag, jitter, loss):
        self.target = target
        self.lag, self.jitter, self.loss = lag / 1000.0, jitter / 1000.0, loss / 100.0
        self.front = None          # the socket guests talk to
        self.backs = {}            # guest address -> its own socket to the host
        self.sent = self.dropped = 0

    def later(self, send):
        if random.random() < self.loss:
            self.dropped += 1
            return
        self.sent += 1
        delay = max(0.0, self.lag + random.uniform(-self.jitter, self.jitter))
        asyncio.get_running_loop().call_later(delay, send)


class Front(asyncio.DatagramProtocol):
    def __init__(self, relay):
        self.relay = relay

    def connection_made(self, transport):
        self.relay.front = transport

    def datagram_received(self, data, addr):
        r = self.relay
        back = r.backs.get(addr)
        if back is None:
            r.backs[addr] = "pending"
            asyncio.ensure_future(self.open_back(addr, data))
            return
        if back == "pending":
            return
        r.later(lambda: back.sendto(data))

    async def open_back(self, addr, first):
        r = self.relay
        loop = asyncio.get_running_loop()
        transport, _ = await loop.create_datagram_endpoint(lambda: Back(r, addr), remote_addr=r.target)
        r.backs[addr] = transport
        r.later(lambda: transport.sendto(first))


class Back(asyncio.DatagramProtocol):
    def __init__(self, relay, guest):
        self.relay, self.guest = relay, guest

    def datagram_received(self, data, _addr):
        r = self.relay
        r.later(lambda: r.front.sendto(data, self.guest))


async def main():
    listen, target, lag = int(sys.argv[1]), int(sys.argv[2]), float(sys.argv[3])
    jitter = float(sys.argv[4]) if len(sys.argv) > 4 else 0.0
    loss = float(sys.argv[5]) if len(sys.argv) > 5 else 0.0
    relay = Relay(("127.0.0.1", target), lag, jitter, loss)
    loop = asyncio.get_running_loop()
    await loop.create_datagram_endpoint(lambda: Front(relay), local_addr=("127.0.0.1", listen))
    print("RELAY %d -> %d  lag %.0f ms  jitter %.0f ms  loss %.1f%%" % (listen, target, lag, jitter, loss), flush=True)
    try:
        while True:
            await asyncio.sleep(10)
            print("RELAY passed %d packets, dropped %d" % (relay.sent, relay.dropped), flush=True)
    except asyncio.CancelledError:
        pass


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
