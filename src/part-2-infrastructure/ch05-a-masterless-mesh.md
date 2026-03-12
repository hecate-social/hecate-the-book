# Chapter 5: A Masterless Mesh

*QUIC, DHT, CRDTs, and the end of central servers*

---

I've been building distributed systems since before the web existed. In 1990, my world was VAX clusters and SNA networks — IBM's Systems Network Architecture, where every packet route was predetermined by a central controller. A few years later I was wiring up CORBA naming services, watching Java RMI die in production, and trying to make DCOM work across subnets. Every generation of distributed computing has had the same argument: who's in charge?

For most of my career, the answer was always "someone." Raft, Paxos, ZooKeeper — pick a leader, replicate writes, sleep soundly. I'd built systems on Kafka, on Kubernetes, on etcd. The leader pattern is popular because it's comforting. One node decides, the rest follow. You can draw it on a whiteboard and everyone nods. I've drawn it on hundreds of whiteboards over three decades.

Then I tried to run a leader-elected cluster on four Celeron mini-PCs sitting on a shelf in my closet, connected to a laptop that travels between my desk and a coffee shop. The laptop would close its lid mid-election. The mini-PCs would split-brain during a power flicker. Kubernetes would spend more resources electing leaders and checking quorum than doing actual work. I spent one particularly memorable Saturday debugging why my "highly available" system had been unavailable for six hours because three of four nodes decided they were all the leader simultaneously.

That's when the question hit me: who exactly is supposed to lead here? The laptop that might lose Wi-Fi in ten seconds? The mini-PC with 16GB of RAM and a dream? Running Kubernetes on these machines was like hiring a symphony orchestra to play in an elevator — technically impressive, mostly unnecessary, and everyone involved was uncomfortable.

But here's the thing — the masterless concept isn't new to me. USENET was masterless. Every node carried its own copy of every newsgroup, and articles propagated through flooding. Gnutella was masterless. BitTorrent is masterless. I'd seen this topology work at massive scale for decades. What I hadn't seen was someone combine it with modern transport (QUIC), modern conflict resolution (CRDTs), and a serious peer-to-peer discovery protocol on hardware you can buy for the price of a nice dinner.

Macula takes the less-traveled fork. No leaders. No quorum. No consensus protocol for writes. Every node is equal. Every node runs the full stack. Nodes discover each other, exchange data, and converge — eventually, reliably, without anyone being in charge.

This chapter is about how that works. (If you've never had to debug a split-brain at 2 AM, I envy you. But read on anyway — the ideas here will change how you think about coordination.)

![Macula Mesh Topology](assets/macula-mesh-topology.svg)

---

## Why QUIC

The transport layer matters more than most architects think. I know, because I've lived through every transport evolution since SNA.

I started with X.25 packet-switched networks, moved to TCP/IP when the internet arrived, watched HTTP/1.0 turn into HTTP/1.1 with persistent connections, then WebSockets for full-duplex, HTTP/2 for multiplexing, and now QUIC. Each transition solved a real problem. Each one also carried baggage from the era before. What thirty-five years of transport history teaches you is this: the protocol shapes the architecture more than architects want to admit.

TCP is a reliable stream protocol designed for a world of wired connections and long-lived sessions. It works. It also does head-of-line blocking (one lost packet stalls everything behind it), takes a full round-trip just to establish a connection plus another for TLS, and falls apart when a device moves between networks — every IP change kills every connection. We ran on TCP for the first prototype. It lasted about three weeks before the constant reconnection storms on flaky home Wi-Fi made it unusable. I'd seen the same pattern in the late '90s with early mobile data networks — TCP simply wasn't designed for connections that move.

QUIC fixes all of this. It multiplexes independent streams over a single UDP socket, so a lost packet in one stream doesn't block the others. Connection establishment takes a single round-trip (zero for repeat connections). TLS 1.3 is built in — not layered on top, *built in*. And connection migration lets a device move from Wi-Fi to cellular without dropping a session.

Macula runs on HTTP/3 over QUIC via MsQuic, Microsoft's production QUIC implementation, accessed through the `quicer` Erlang NIF. One UDP port — 9443 by default — handles everything: pub/sub, RPC, content transfer, gossip, DHT lookups. One port to open in the firewall. One port to NAT-traverse. After decades of managing multi-port deployments — SNA had different ports for different LU types, CORBA's IIOP needed its own range, DCOM was a nightmare of dynamic port allocation — I cannot overstate how much operational pain disappears when your entire distributed system runs through a single port.

```erlang
%% Starting a Macula peer — one port, everything included
macula:start(#{
    port => 9443,
    realm => <<"hecate">>,
    discovery => #{
        mdns => true,
        bootstrap_nodes => [<<"mesh.hecate.social:9443">>]
    }
}).
```

This isn't HTTP being repurposed as a transport hack. QUIC's multiplexed streams map naturally to the multiple communication patterns Macula needs. A pub/sub subscription is a long-lived stream. An RPC call is a short-lived one. A content transfer is a high-bandwidth stream running alongside everything else without blocking it. The protocol matches the workload. When we first saw pub/sub, RPC, and a model file download all running simultaneously over a single connection without interfering with each other — that was the moment I knew we'd finally arrived at the transport the previous thirty years had been building toward.

---

## Discovery Without a Registry

In a centralized system, nodes find each other by asking a registry. Consul, etcd, a DNS SRV record — someone, somewhere, maintains a list of who's online. That someone is a single point of failure. (We briefly ran a Consul cluster to discover our mesh nodes. Yes, we had a distributed system to find our distributed system. The irony was not lost on us — I'd done the same thing with CORBA naming services in 1998, and it was just as absurd then.)

Macula uses two complementary mechanisms: gossip for local discovery and a Kademlia DHT for global routing.

**Local discovery** uses UDP multicast. Every Macula node periodically broadcasts its presence on the local network. Other nodes hear the broadcast and initiate a connection. No configuration needed. Start two nodes on the same LAN and they find each other. This is how your laptop discovers the Hecate daemon running on your home server. I've been using multicast discovery in one form or another since the early 2000s — Apple's Bonjour, Jini's multicast announcement protocol — and it still feels like magic when a node appears in the mesh without a single line of configuration. The technology is mundane. The experience never gets old.

**Global discovery** uses a Kademlia Distributed Hash Table. Every node has a 256-bit SHA-256 identifier. When a node joins the network, it performs a DHT lookup for its own ID, which has the side effect of populating its routing table with nearby nodes (in XOR-distance terms). Finding any node in a million-node network takes O(log N) hops — about 20 lookups.

```erlang
%% DHT is invisible — you publish and subscribe by topic
macula:subscribe(<<"marketplace.apps.available">>, fun(Msg) ->
    handle_app_announcement(Msg)
end).

%% The DHT routes this to all subscribers, wherever they are
macula:publish(<<"marketplace.apps.available">>, #{
    app_id => <<"weather-station">>,
    version => <<"1.2.0">>,
    capabilities => [<<"weather.forecast">>, <<"weather.alerts">>]
}).
```

The DHT also bridges network boundaries through a hierarchical structure. A node first checks its local cluster. If the topic has no local subscribers, the query escalates: Street, Neighborhood, City, Province, Country, Region, Global. Each level has bridge nodes that connect clusters. A publish in your living room can reach a subscriber on another continent, with each hop narrowing the search.

This isn't theoretical. Hecate uses this to connect agents running on a home lab (four Celeron mini-PCs on a shelf) with agents running on a laptop, with no static configuration, no DNS, no service registry. Nodes appear. Nodes disappear. The mesh adapts. I've literally unplugged a mini-PC, plugged it back in thirty seconds later, and watched it rejoin the mesh without a single configuration change or manual intervention. Try doing that with Kubernetes.

---

## CRDTs: Consensus Without Consensus

Here's the fundamental challenge of masterless systems: if there's no leader, how do nodes agree on shared state?

The traditional answer is consensus protocols — Raft, Paxos, PBFT. These guarantee strong consistency at the cost of availability. If a majority of nodes can't communicate, the system stops accepting writes. That's fine for a database. It's unacceptable for a mesh of autonomous agents that might be on flaky Wi-Fi. Raft consensus is democracy for computers: slow, messy, but usually right. CRDTs are anarchy: fast, chaotic, and surprisingly functional.

"Eventually consistent" used to make architects nervous. It made me nervous, too — in 1995. Then I spent decades living with systems that were eventually consistent whether they admitted it or not. USENET propagation could take hours. DNS caches have TTLs measured in days. Batch replication between AS/400 systems ran on a nightly schedule — your branch office data was twenty-four hours stale and nobody complained. Every read replica in every database cluster I've ever managed was eventually consistent, no matter what the marketing said. The question was never "is eventual consistency acceptable?" It was always "how eventual is eventual?"

Still, when it came to CRDTs, I approached them with the skepticism of someone who'd been burned by too many "this changes everything" technologies. Then we had our first network partition during a demo. The Raft-based prototype went completely silent — a majority of nodes were on the wrong side of the partition, so nothing could write. Meanwhile, the agents on both sides of the partition had perfectly good work to do. They just... couldn't. Because a consensus algorithm on the other side of a flaky Wi-Fi connection said so.

That was the week I read the CRDT papers seriously. And what I found was not some radical new idea — it was a formalization of something I'd been doing informally for years. Merge-friendly data structures. Commutative operations. Convergent state. The academics had given rigorous guarantees to patterns I'd seen work in the wild across decades of distributed systems.

Macula uses CRDTs — Conflict-Free Replicated Data Types. CRDTs are data structures designed so that any two replicas can be merged without conflicts, regardless of the order of operations. They guarantee eventual consistency: all nodes will converge to the same state, given enough time, with no coordination required.

The types available tell you what problems they solve:

```
lww_register  — Last-Writer-Wins Register. Simple values where
                the most recent write wins. Timestamps break ties.

g_counter     — Grow-only Counter. Tracks totals that only go up:
                messages sent, requests served.

pn_counter    — Positive-Negative Counter. Can increment and
                decrement. Each node maintains its own count;
                the global value is the sum.

g_set         — Grow-only Set. Elements can be added but never
                removed. Membership lists, capability registries.

or_set        — Observed-Remove Set. Elements can be added AND
                removed. The "or" means "observed remove" — a
                remove only affects adds the remover has seen.
```

These aren't arbitrary data structures. They're the building blocks of shared state in a masterless system. A node's reputation is a `pn_counter` (endorsements add, disputes subtract). The set of known capabilities is a `g_set` (capabilities are announced, never un-announced — revocation is a separate event). A node's current status is an `lww_register` (the most recent heartbeat wins).

```erlang
%% CRDTs are accessed through the mesh — no manual merge
macula:crdt_update(<<"node_stats">>, {pn_counter, increment, 1}).

%% Read converges automatically across nodes
{ok, Count} = macula:crdt_read(<<"node_stats">>).
```

The gossip protocol handles dissemination. Every second, each node pushes its CRDT state to a random subset of peers (fanout of 3). Every 30 seconds, a full anti-entropy sweep runs: two nodes compare their state and exchange anything the other is missing. The push-pull-push protocol ensures updates propagate exponentially through the network.

This is AP in the CAP theorem. Availability and Partition tolerance, at the cost of strong consistency. Every node can always read and write. Every node will eventually converge. But at any given moment, two nodes might disagree about the current count or the current set membership.

For Hecate, this is the right trade-off. An agent deciding whether to accept a task doesn't need globally consistent reputation scores. It needs a recent, approximately correct view of the world. CRDTs deliver exactly that. And here's what surprised even a veteran like me: in practice, "eventually" is fast. On a local network, convergence happens in seconds. Even across the internet, it's rarely more than a minute. The theoretical worst case is scary. The practical reality is that you stop thinking about it — the same way you stopped worrying about DNS propagation delays twenty years ago.

---

## NAT Traversal: Getting Through the Walls

Most devices on the internet sit behind a NAT. Your laptop has a private IP (192.168.1.x). Your router has a public IP. Between them is a translation table that the router maintains, and it doesn't appreciate unsolicited incoming connections.

This is the reason most peer-to-peer systems fail in practice. I've been watching P2P architectures die on the NAT problem since Gnutella in 2000. Beautiful protocols, elegant routing, mathematically proven convergence — all of it falling apart the instant it hit a real network with real NATs and real firewalls. The early Napster clones, the various Kazaa forks, even early VOIP — everyone reinvented NAT traversal badly, or gave up and ran everything through central servers (which defeated the purpose). STUN, TURN, and ICE emerged from that era of pain. We learned this the hard way ourselves with an early prototype that worked flawlessly on a single LAN and completely refused to function when we tried it between two home networks. The same failure I'd watched happen to a dozen other projects over two decades.

Macula handles this with a three-tier strategy:

**Direct connection** works when both nodes have public IPs, or when they're on the same LAN. Try it first — it's the fastest path.

**Hole punching** works for most consumer NATs. Both nodes send packets to each other simultaneously, using a coordination server to exchange addresses. The outgoing packets create entries in each NAT's translation table, and the incoming packets from the other side match those entries. It looks like magic. It's just exploiting how NAT implementations work. NAT traversal is the dark magic of networking — it works for the same reason your microwave works: you know it does, you don't fully understand why, and you don't want to look too closely. (I first saw hole punching in the early 2000s with game networking libraries. Twenty years later it's still the cleverest hack in networking — getting away with something by exploiting implementation details that were never part of any spec.)

**Relay fallback** handles the hostile cases — symmetric NATs, corporate firewalls, carrier-grade NATs that actively resist hole punching. When direct connection fails and hole punching fails, traffic routes through a relay node that both peers CAN reach. It's slower, but it works.

The system is adaptive. Macula detects the NAT type during connection setup and picks the best strategy automatically. If conditions change (a device moves from a friendly home NAT to a hostile corporate network), the connection strategy adjusts.

This matters because Hecate runs on whatever hardware people have. A Raspberry Pi behind a home router. A laptop on a university network. A mini-PC on a shelf in a closet. The mesh has to work everywhere, without asking users to configure port forwarding or set up VPNs. I've watched people try to explain port forwarding to non-technical users. It doesn't go well. The infrastructure adapts to the network, not the other way around.

---

## Pub/Sub and RPC: Two Communication Patterns

Macula supports two fundamental communication patterns, and choosing the right one is a design decision, not a preference. We went back and forth on this for weeks — could we get away with just pub/sub? Just RPC? In the end, the answer was clear: you need both, and you need to know when to use each. This isn't a new insight — CORBA had both notification services and synchronous invocations. JMS had both topics and queues. Every messaging system eventually arrives at the same conclusion.

**Pub/Sub** is fire-and-forget with topic-based routing. A publisher sends a message to a topic. All subscribers on that topic receive it. The publisher doesn't know — or care — who's listening.

```erlang
%% Publisher: announce that an app is available
macula:publish(<<"marketplace.apps.available">>, #{
    app_id => AppId,
    manifest => Manifest
}).

%% Subscriber: react to app announcements (somewhere else entirely)
macula:subscribe(<<"marketplace.apps.available">>, fun(Msg) ->
    maybe_install_app(Msg)
end).
```

Topic design has one hard rule: **IDs go in payloads, NOT in topic names.** This prevents topic explosion. `marketplace.apps.available` is a topic. `marketplace.apps.available.weather-station-v1.2.0` is a mistake — you'd need a subscription for every app ID, and new apps would require new subscriptions. Put the filtering logic in the subscriber. (We made this mistake exactly once, ended up with 300+ topics for what should have been one, and learned our lesson permanently.)

**RPC** is request-response with service routing. A caller invokes a named procedure on a remote node and waits for a result (synchronous) or registers a callback (asynchronous, NATS-style).

```erlang
%% Advertise a capability
macula:advertise(<<"llm.generate">>, fun(Request) ->
    generate_response(Request)
end).

%% Call it from another node
{ok, Response} = macula:call(<<"llm.generate">>, #{
    model => <<"llama3">>,
    prompt => <<"Explain CRDTs">>
}).
```

The distinction maps to domain concepts. Integration facts go over pub/sub — they're announcements that any interested party can consume. Service invocations go over RPC — they're directed requests that expect a response. When Hecate announces a new plugin to the network, that's pub/sub. When one agent asks another to generate text, that's RPC. If you find yourself confused about which to use, ask: "Do I need an answer?" If yes, RPC. If no, pub/sub.

---

## Content Transfer: Moving Big Things

Small messages fit in pub/sub payloads. Model files, datasets, and plugin binaries do not. (A 7B parameter LLM model is about 4GB. That's not a pub/sub message. That's a commitment.)

Macula includes a content-addressed transfer protocol inspired by BitTorrent and IPFS. Every piece of content gets a content ID (MCID) computed from its BLAKE3 or SHA-256 hash. Transfer uses a Want/Have/Block protocol:

1. Node A wants content with MCID `abc123`
2. Node A broadcasts `WANT abc123` to its peers
3. Nodes that have it respond with `HAVE abc123`
4. Node A requests blocks from multiple peers in parallel
5. Each block is verified against the content hash
6. When all blocks arrive, the content is reassembled and verified

Parallel download from multiple sources. Cryptographic verification of every block. Automatic deduplication — if two nodes publish the same content, it gets the same MCID. No central file server. No CDN. Just peers sharing data.

This is how Hecate distributes AI models and plugin binaries across a home lab without downloading them from the internet for each node. Download the model once to any node, and it propagates to the others. The first time we watched a 4GB model transfer across four nodes in the home lab — each node contributing blocks it had already received to the others — was deeply satisfying. I'd been waiting for this since I first read about BitTorrent's tit-for-tat protocol in 2003. BitTorrent for your living room, finally running on proper infrastructure.

---

## The Supervision Architecture

Macula is an OTP application, and its supervision tree reflects the "always-on, everything everywhere" philosophy. The base system starts 17 processes:

- Connection manager, listener, and session pool
- DHT server and routing table
- CRDT store and gossip process
- Pub/sub registry and topic manager
- RPC router and service registry
- NAT detection and relay coordinator
- Content transfer manager
- Telemetry collector

Each peer connection adds 4 more processes: a session handler, a stream multiplexer, a heartbeat monitor, and a message dispatcher.

The entire system runs under OTP supervision, which means individual process crashes are isolated and recovered. A DHT routing table corruption doesn't take down pub/sub. A failed peer connection doesn't affect the CRDT store. The BEAM's "let it crash" philosophy is the mesh's resilience strategy. I once watched a bug in the content transfer manager crash and restart twelve times in a minute while pub/sub and RPC continued operating without a hiccup. In any other runtime I've worked with over thirty-five years — and I've worked with most of them — that would have been a full outage. On the BEAM, it was a noisy Tuesday.

---

## Realms: Namespace Isolation

Not every node should see every message. Macula uses realms to partition the mesh into logical namespaces. A node joins a realm when it connects, and it only sees topics and services within that realm.

The topology is a **star-ring hybrid**. Within each realm, nodes form a gossip ring — each node exchanges state with its neighbors, and information propagates around the ring. Across realms, designated **bridge nodes** connect the rings in a star pattern. A bridge node participates in its own realm's gossip ring and maintains connections to bridge nodes in other realms.

![Realm Topology: Star-Ring Hybrid](assets/realm-topology.svg)

This gives you two desirable properties simultaneously:

**Intra-realm efficiency.** Gossip within a ring is O(N) per round — every node talks to a small fixed number of neighbors, and updates propagate in O(log N) rounds. There's no leader, no election, no quorum. If a node crashes, the ring heals by connecting its neighbors directly.

**Inter-realm isolation with selective bridging.** Realms are invisible to each other except through bridge nodes. A production realm's internal gossip — heartbeats, CRDT deltas, topic subscriptions — never leaks to the development realm. Only explicitly published integration facts cross the bridge, and only when a bridge node forwards them. (We learned why this isolation matters after a dev environment's chatty debug logging flooded the production realm's gossip channel. That was a fun afternoon.)

```erlang
%% A node joins exactly one realm
macula:start(#{
    port => 9443,
    realm => <<"hecate">>,          %% production realm
    bridge => true,                  %% this node bridges to other realms
    bridge_peers => [
        <<"dev-01.lab:9443">>,       %% dev realm bridge
        <<"store.marketplace:9443">> %% marketplace realm bridge
    ]
}).
```

In Hecate's home lab deployment, this looks concrete: four Celeron mini-PCs (`beam00` through `beam03`) and a laptop form the `hecate` production realm. A separate set of dev nodes form the `hecate-dev` realm. A marketplace cluster distributes plugins through the `marketplace` realm. `beam00` acts as the bridge node for production, connecting to bridge nodes in the other two realms.

The bridge node is not a leader — it has no special authority. If it crashes, another node in the realm can be promoted to bridge (or the realm simply operates in isolation until the bridge returns). The star topology between bridges is a convenience for routing, not a dependency for correctness.

---

## What This Enables

A masterless mesh changes the assumptions you can make about your system. After living with this for over a year, here's what actually matters day-to-day:

**No deployment coordinator.** Nodes appear and disappear. The mesh adapts. You don't need to update a service registry or reconfigure a load balancer when you add a node. I've added nodes to the cluster by literally plugging in a new mini-PC and turning it on. That's the whole deployment process. After decades of writing deployment runbooks — from mainframe IPL procedures to Kubernetes manifests — "plug it in and turn it on" feels almost subversive. My deployment runbook is now shorter than most stack traces.

**No single point of failure.** There's no leader to lose. Any node can serve any request. If a node goes down, its subscribers and publishers simply don't participate until it comes back. No pages. No failover runbooks. No "who's the new leader?"

**Edge-native.** The same protocol works on a home LAN (via mDNS) and across the internet (via DHT + NAT traversal). No VPN. No tunnel. No cloud relay that becomes a dependency.

**Offline-first.** Nodes operate independently. When they reconnect, CRDTs merge state automatically. An agent that went offline for an hour doesn't need to "catch up" — the gossip protocol handles convergence.

The trade-off is complexity. I won't pretend otherwise. Debugging eventual consistency is harder than debugging a leader-follower system. Message ordering is not guaranteed. Network partitions cause temporary divergence. You have to design your application to tolerate all of this. There were days, especially early on, when I missed the simplicity of "just ask the leader." Every distributed systems paper starts with "assume a reliable network." Every distributed systems postmortem starts with "the network was not reliable."

But if your system is a collection of autonomous agents — each with its own event store, its own decision-making capability, its own local state — then a masterless mesh isn't a compromise. It's the only topology that matches the architecture. I've seen this pattern under six different names across four decades — from USENET floods to Gnutella to BitTorrent swarms to CRDTs — and this time we finally have the transport, the math, and the runtime to do it right.

The well-lit road led to Kubernetes, to managed clusters, to someone else's infrastructure. We went the other way — into the woods, where it's darker but quieter, and the topology is ours.

No kings. No servers. Just peers.
