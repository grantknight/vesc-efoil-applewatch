# AI entry point

Read [MASTER_PROMPT.md](MASTER_PROMPT.md) before making changes. It is the project brief, accepted product intent, architecture map, constraints and continuation plan. Then read [README.md](README.md), [MAC_HANDOFF.md](MAC_HANDOFF.md) and [WIDGET_SETUP.md](WIDGET_SETUP.md) as relevant.

This is Grant Knight's **Foil Assist** standalone Apple Watch app for a VESC e-foil assist system. It displays read-only information; it does not control throttle or drive the motor. Preserve the selected Sport layout, persistent ride history, clear data freshness and independent VESC/BMS connections.

Never invent live measurements, individual cell voltages or test passes. Demo data must remain visibly labelled and isolated from real storage, radios and shared snapshots. The 12S BMS screen exists, but live vendor-specific cell decoding remains unfinished pending the actual BMS identity. Simulator success is not physical Watch/on-water acceptance.

Keep the master brief and verification record current when behavior, decisions or remaining work change. Use exact commit IDs for evidence. Do not claim historical tests apply to subsequently changed code. Use independent peer review when the user requests councils; a reviewer must not approve their own implementation. Jev reviews executed evidence, not hardware and not unexecuted tests. Repair defects before requesting another assessment; never retry merely to obtain a favourable answer.

Keep credentials, `.env`, private runtime files, build output and generated ZIP files out of Git. Do not modify unrelated remote branches. Normal implementation and handover work is authorized by the user's request; ask only for genuinely missing technical information or actions outside that scope, subject to the host's permission rules.
