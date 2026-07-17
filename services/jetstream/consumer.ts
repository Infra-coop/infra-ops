/**
 * Jetstream consumer for co/infra. Watches the AT Protocol firehose (via
 * Jetstream) for accounts that go inactive and purges the image CDN cache for
 * that account. This is Tier 1 of the CDN's blob invalidation.
 *
 * It asks Jetstream for a collection nothing publishes to, which drops the
 * commit firehose while still delivering account and identity events, so the
 * bandwidth is a trickle. The time_us cursor is persisted so a restart resumes
 * without gaps.
 */
import { readFileSync, writeFileSync } from 'node:fs';

const JETSTREAM_URL = process.env.JETSTREAM_URL ?? 'wss://jetstream1.us-east.bsky.network/subscribe';
const PURGE_URL = process.env.PURGE_URL ?? '';
const PURGE_TOKEN = process.env.PURGE_TOKEN ?? '';
const CURSOR_FILE = process.env.CURSOR_FILE ?? '/data/cursor';

if (!PURGE_URL || !PURGE_TOKEN) {
	console.error('PURGE_URL and PURGE_TOKEN are required');
	process.exit(1);
}

interface AccountEvent {
	did: string;
	time_us: number;
	kind: string;
	account?: { active: boolean; status?: string };
}

let cursor = loadCursor();
let lastSaved = 0;
let backoff = 1000;

function loadCursor(): string | undefined {
	try {
		return readFileSync(CURSOR_FILE, 'utf8').trim() || undefined;
	} catch {
		return undefined;
	}
}

function saveCursor(value: string): void {
	cursor = value;
	const now = Date.now();
	if (now - lastSaved < 5000) {
		return;
	}
	lastSaved = now;
	try {
		writeFileSync(CURSOR_FILE, value);
	} catch (error) {
		console.error('failed to persist cursor', error);
	}
}

async function purge(did: string, status: string | undefined): Promise<void> {
	try {
		const res = await fetch(PURGE_URL, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${PURGE_TOKEN}` },
			body: JSON.stringify({ did }),
		});
		if (!res.ok) {
			console.error(`purge failed for ${did}: ${res.status}`);
			return;
		}
		const body = (await res.json()) as { purged?: number };
		console.log(`purged ${body.purged ?? 0} variants for ${did} (${status ?? 'inactive'})`);
	} catch (error) {
		console.error(`purge error for ${did}:`, error);
	}
}

function connect(): void {
	const url = new URL(JETSTREAM_URL);
	// A collection nothing publishes to, so commits are dropped and only account
	// and identity events arrive.
	url.searchParams.set('wantedCollections', 'coop.infra.none');
	if (cursor) {
		url.searchParams.set('cursor', cursor);
	}

	const ws = new WebSocket(url.toString());

	ws.addEventListener('open', () => {
		console.log('connected to jetstream');
		backoff = 1000;
	});

	ws.addEventListener('message', (event) => {
		let parsed: AccountEvent;
		try {
			parsed = JSON.parse(event.data as string) as AccountEvent;
		} catch {
			return;
		}
		if (parsed.time_us) {
			saveCursor(String(parsed.time_us));
		}
		if (parsed.kind === 'account' && parsed.account && parsed.account.active === false) {
			void purge(parsed.did, parsed.account.status);
		}
	});

	ws.addEventListener('close', () => {
		console.warn(`jetstream closed, reconnecting in ${backoff}ms`);
		setTimeout(connect, backoff);
		backoff = Math.min(backoff * 2, 30000);
	});

	ws.addEventListener('error', () => {
		try {
			ws.close();
		} catch {
			// close triggers the reconnect
		}
	});
}

console.log('starting jetstream consumer');
connect();
