# 0012. The public IP lookup: more change signals, one confirmation lookup, no shorter interval

| | |
| --- | --- |
| Status | accepted |
| Date | 2026-11-18 |
| Decided by | the author's request of 2026-11-18 ("faire en sorte que l'icône du pays de l'IP publique se rafraîchisse plus souvent (si l'IP change, sinon pas la peine)"), interpreted as below by the agent; **overrule if wanted** |
| Supersedes | none. **Extends [0011](0011-public-ip-lookup-also-runs-while-its-flag-is-shown.md), does not supersede it** (and so extends [0007](0007-privacy-by-default.md) too): the lookup stays optional and off by default, with the same service (ipwho.is, backup ipapi.co), the same session (ephemeral, no cookies, no cache), nothing stored, and the same periodic fallback of 5 minutes |
| Drives from | decision driver 3 (privacy); the SL19 flag |

## Context

With ADR 0011 the flag follows the connection: a lookup runs when the setting is on and the network item is shown, at most every 5 minutes, or at once (not within 5 seconds of the last attempt) when the "fingerprint" changes. The fingerprint was `local IP | VPN on or off | VPN interface | VPN name`, read at the 3-second measure (the VPN every 10 seconds).

The author asked for the flag to refresh more often, but only if the IP changes. The public IP can change in more situations than that fingerprint sees: switching Wi-Fi network or Wi-Fi to Ethernet (two home networks can both give 192.168.1.x with the same router address), a change of default route or gateway, of DNS servers or search domains (VPN split tunnels), a VPN server hop that keeps the same tunnel interface, and waking from sleep.

## Options considered

### Option A: a shorter periodic interval

- For: trivial.
- Against: more requests to a third party **when nothing changes**, which is exactly what the author did not want, and which is the privacy cost of ADR 0011 multiplied.

### Option B: more local change signals, an event source, and one confirmation lookup (chosen)

- For: no extra traffic in steady state; the lookup happens when something that can change the public IP changed, and once more shortly after because the first answer can still come from the old route; all signals are read locally with no permission.
- Against: more code to keep right, and a few spurious lookups are possible (each bounded by the 5-second gap, the 60-second pause after a failure and the 3-second calm period).

### Option C: a lighter "IP only" endpoint

- For: less data per request.
- Against: still a request to a third party, and a new service to name, trust and document. Rejected.

## Decision

**Option B.** The lookup rules of 0011 do not change. What is added:

1. **A richer fingerprint**, a pure value (`NetworkSignals`) built by a pure function from plain dictionaries: the primary interface and default gateway (IPv4 and IPv6), each network service's interface, addresses, router and macOS's own `NetworkSignature` (it holds the router's hardware address, which tells two 192.168.1.x networks apart), the DNS servers and domains, and the active IPv4 tunnels with their addresses. Read through SystemConfiguration and `getifaddrs`: no request, no permission. Not used: the Wi-Fi name (SSID) and access point (BSSID), because macOS redacts them without the Location permission (checked on 2026-11-18: empty SSID, 02:00:00:00:00:00), and a permission prompt is out of the question; the BSSID would also change when roaming between access points of the same network without any change of public IP. Signal strength, byte counters, lease times and IPv6 temporary addresses are noise and are never read.
2. **An event source with a calm period.** A monitor wakes the same decision function after a burst of events (3 seconds without a new event). The source is SystemConfiguration's dynamic store notifications on the keys the fingerprint reads, plus the wake notification (`NSWorkspace.didWakeNotification`). **Not** `NWPathMonitor`: it reports path status and interfaces but not a change of DNS servers or of the gateway or address of a tunnel that keeps its interface, which is the VPN hop case; the store needs no entitlement for a non-sandboxed app (ADR 0002), is already linked, and plugs into the main run loop without a queue. The monitor exists only while a lookup could be asked for (setting on, no demo, network item shown or Network tab open), is created and cancelled with that condition, never calls the network or the lookup service, and does not retain `AppState`. A wake forces a "changed" decision even if the fingerprint is the same.
3. **A calm period also for the 3-second measure.** A changed fingerprint counts as a change once it has stayed the same for 3 seconds (the Network tab keeps its immediate rule, and so does the very first lookup). Without it the 3-second measure would look up in the middle of a burst of events.
4. **One confirmation lookup.** After a lookup caused by a detected change (not the first lookup, not the periodic one, not a click on Refresh), exactly one more lookup 10 seconds later, because the first answer can still come from the old route. The newer answer is kept; if it is the same, nothing more. Not after a failure, not repeated, cancelled when the setting is turned off or the flag is hidden, never in demo, and it respects the 60-second pause after a failure. This is the only extra traffic, and only after a detected change.
5. The 5-minute periodic refresh is not shortened. `SOARO_DEBUG` writes one line per lookup and per settled event on the error output (the reason, never the address or the country), so the author can check that nothing is asked between the 5-minute checks.

## Consequences

- Good: the flag disappears and comes back with the right country within seconds of a Wi-Fi switch, a VPN hop or a wake; no traffic at all when nothing changes; no new setting, no new service, no new permission.
- Bad: one extra request after each detected change (the Settings text, "about every 5 minutes, and again when your network or VPN changes", stays true: no wording change); the 3-second calm period delays a change seen only by the measure by up to 3 seconds; after a wake the network may not be up yet, so the first lookup can fail and the next one waits 60 seconds.
- Risks: a network that flaps all the time makes a lookup every 5 seconds at worst while the calm period keeps being met; a signal that flickers without a real change would cost spurious lookups (the signals chosen were read for their stability).

## Revisit when

- The service starts to refuse requests, or spurious lookups show up in the `SOARO_DEBUG` log.
- macOS exposes the Wi-Fi name without a permission, or the author accepts the Location permission.

## Open points

- None. Not testable here, only by the author: a real network change, a real VPN hop, a real wake.
