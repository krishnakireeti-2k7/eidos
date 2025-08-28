EIDOS Memory Chat — 
0) Outcome (what “done” looks like)
Mobile app (Flutter) with chat UI.

Every message is stored, embedded, and retrievable.

Replies come from an LLM (e.g., Gemini) with RAG (retrieval-augmented generation).

Structured memory: goals, facts, preferences (guaranteed recall).

Proactive nudges: scheduled reminders/call-outs.

All traffic goes through your backend (protects API key, enforces per-user limits).

1) Minimal, proven stack

Pick one; both work great on free tiers.

Option A (straightforward, SQL-first):

Frontend: Flutter + Riverpod.

Auth: Supabase Auth (email/Google).

DB: Supabase Postgres + pgvector (built-in).

Backend: Supabase Edge Functions (Deno/TypeScript) to call Gemini.

Scheduler: Supabase cron for reminders.

Option B (Firebase-friendly):

Frontend: Flutter + Riverpod.

Auth/DB: Firebase Auth + Firestore.

Vector DB: Weaviate (free tier) or Pinecone (free tier).

Backend: Cloud Functions (Node/TS) to call Gemini.

Scheduler: Cloud Scheduler + Pub/Sub.

If you want the fewest moving parts, Option A (Supabase + pgvector) keeps everything in one place.

2) Data model (tables/collections)
Core (per user)

users
id, email, created_at, persona_json (optional)

messages (full chat history)
id, user_id, role('user'|'assistant'), text, created_at, token_count

memory_chunks (unstructured episodic memory)
id, user_id, source_message_id, text, created_at

embeddings (vector index for memory_chunks)
id, memory_chunk_id, embedding VECTOR(1536 or 3072), created_at

facts (structured, durable): key/value with type
id, user_id, category('profile'|'preference'|'constraint'), key, value, confidence(0..1), updated_at

goals (explicit commitments)
id, user_id, title, details, start_date, due_date, status('active'|'done'|'dropped'), updated_at

reminders
id, user_id, goal_id (nullable), text, due_at, cadence('once'|'daily'|'weekly'), status('scheduled'|'sent'|'skipped')

usage (rate limiting/analytics)
id, user_id, date, requests_count, tokens_in, tokens_out

In pgvector, add an index:
CREATE INDEX ON embeddings USING ivfflat (embedding vector_cosine_ops);

3) Request flow (per message)

Frontend → Backend:

User sends text.

Backend auth checks user, rate-limits (per day/minute).

Backend stores message (role=user).

Backend extracts candidates for memory (simple heuristic first: length > N, or phrases like “remember that”, “my birthday is…”).

For each memory_chunk created:

Create embedding with an embedding model.

Upsert into embeddings.

Retrieval:
6) Build a retrieval query from the user message:

Embed the query.

SELECT memory_chunk_id, text, cos_sim FROM embeddings ORDER BY cos_sim DESC LIMIT k;

Optionally include top facts/goals by rule.

Synthesis (RAG):
7) Build the prompt: system + persona + rules + retrieved memory + conversation snippet + user message.
8) Call LLM (Gemini free tier) → get assistant text.
9) Store assistant message in messages.
10) Return to client.

Post-reply enrichment (best effort):
11) Run light “memory extractor” on the user message (and sometimes assistant reply) to update facts/goals if you detected structured info.
12) Schedule reminders if the user committed to something with a time.

4) Prompts that actually work
System (personality + behavior)
You are Kireeti’s AI companion: equal parts fun and productive.
Priorities: 1) Be honest and direct (call out BS kindly). 2) Help Kireeti achieve goals.
3) Keep continuity using retrieved memories below. 4) Don’t invent facts you didn’t retrieve.
Tone: concise, warm, a bit witty. Never patronizing.

Rules:
- If the user’s query conflicts with past commitments, raise it respectfully.
- Use facts/goals/reminders only if high-confidence or clearly user-confirmed.
- If unsure, ask a short clarifying question (max 1).
- When giving advice, prefer actionable steps.

Memory injection template
### Known facts
- Birthday: 3 July
- Gym targets: Bench 75kg, Squat 100kg, Deadlift 120kg by 19th bday
...

### Active goals (top 5)
1) Solve 150+ DSA problems by 2026-07-03 (3/week)
2) Complete Flutter course on Udemy
...

### Retrieved memories (most relevant first)
- [2025-08-18] “I procrastinated today; please call me out if I say ‘tomorrow’ again.”
- [2025-08-05] “I prefer direct callouts over vague metaphors.”
...

Now respond to the new message:

Assistant style nudge (when warranted)
Observation: You postponed this same task twice this week.
Nudge: Want to schedule a 25-min block now or adjust the goal?

5) Heuristics for memory vs. facts vs. goals

facts when patterns like:

“My birthday is …”, “I live in …”, “Remind me that I prefer …”, “Call me Kireeti”.

goals when:

“I will do X by Y”, “This week I’ll …”, “Target: …”

memory_chunks for everything else (episodic context, reflections, anecdotes).

Start simple with regex + keywords. You can later add a mini LLM “memory extractor” that outputs:

{
  "facts":[{"key":"preferred_style","value":"direct callouts","confidence":0.9}],
  "goals":[{"title":"Finish Flutter course","due_date":"2025-10-01"}],
  "reminders":[{"text":"Study Flutter 45m","due_at":"2025-09-01T19:00:00"}]
}

6) Retrieval recipe (pgvector example)

Create embedding for query → q_vec.

SQL (cosine similarity):

SELECT m.id, m.text,
       1 - (e.embedding <=> q_vec) AS score
FROM embeddings e
JOIN memory_chunks m ON m.id = e.memory_chunk_id
WHERE m.user_id = $1
ORDER BY e.embedding <=> q_vec
LIMIT 8;


Then filter/score rerank in code (e.g., drop very short/duplicate chunks). Keep 4–8.

7) Rate limiting (per-user, free tier safe)

Daily: e.g., max 30 messages/day per user (configurable).

Burst: 1 req/sec per user (token bucket).

Global: stop if project-wide free-tier quota nears cap.

Store counters in usage (reset daily via cron).

When limited, return a friendly message + show next reset time.

8) Proactive reminders (scheduler loop)

Cron runs every 5–10 minutes:

SELECT * FROM reminders WHERE due_at <= now() AND status='scheduled'.

For each, enqueue a server-pushed message (or mark to show next app open).

Set status='sent' and if cadence is repeating, push due_at forward.

On mobile, you can also schedule local notifications as backup.

9) Caching & cost control (important)

Short-term response cache: If same user asks near-identical question within 1 hour, reuse answer.

Embedding dedupe: Hash normalized text; if seen before for this user, don’t re-embed.

Truncate prompt: Keep only top K memories + recent 10–20 turns.

Prefer small/cheap model (Gemini Flash/Flash-Lite) for most turns; escalate to bigger only when flagged (long reasoning).

10) Security & privacy

Never ship the model API key in the app. All requests hit your backend proxy.

Encrypt at rest if possible; minimally, restrict DB by user_id RLS (Row Level Security).

Provide export & delete my data (one button).

Log only what you need (mask secrets).

11) Frontend wiring (Flutter + Riverpod)

AuthController: handles login/out (Supabase/Firebase).

ChatRepository: sendMessage(text) → calls your backend → returns assistant reply.

MemoryPanel: optional UI to show/edit facts/goals (transparent & empowering).

RateLimitBanner: shows remaining messages today.

UX rules:

Quick send, optimistic UI.

Subtle “Memory saved” chips when facts/goals captured.

One-tap “Set reminder” on action items the model proposes.

12) Backend endpoints (minimal)

POST /chat/send

{ "text": "I’ll study DSA 30m every evening. Remind me at 7pm." }


Server steps:

auth → rate-limit

store message

(optional) extract structured memory, create reminders

embed + retrieve memories

call LLM with prompt + retrieved memory

store assistant message

return { reply, usage_stats }

GET /profile/memory → return facts, goals, recent reminders.

POST /profile/facts / POST /goals / POST /reminders → optional manual edits.

13) “It works” checkpoints (layered passes)

Pass 1 (Day 1–3):
Chat loop works end-to-end (no memory). Store messages. Get LLM replies.

Pass 2 (Day 3–6):
Add memory capture → memory_chunks + embeddings + retrieval + RAG in prompt.

Pass 3 (Day 6–10):
Structured memory (facts/goals). Show them in a simple panel. Nudge on conflicts.

Pass 4 (Day 10–14):
Reminders + scheduler + local notifications.

Pass 5 (Day 14+):
Polish prompts, smarter extraction, better retrieval scoring, rate limit UI, export/delete data.

(You’ll thin-slice across all of these, but these are the functional milestones.)

14) Minimal code shapes (pseudocode)

Create embedding & upsert

const emb = await embed(text); // returns Float32Array
await sql`INSERT INTO memory_chunks (user_id, text) VALUES (${uid}, ${text}) RETURNING id`;
await sql`INSERT INTO embeddings (memory_chunk_id, embedding) VALUES (${id}, ${emb})`;


Retrieve

const qvec = await embed(query);
const rows = await sql`SELECT m.text, 1 - (e.embedding <=> ${qvec}) AS score
                       FROM embeddings e JOIN memory_chunks m
                       ON m.id = e.memory_chunk_id
                       WHERE m.user_id = ${uid}
                       ORDER BY e.embedding <=> ${qvec}
                       LIMIT 8`;


Synthesize

const prompt = buildPrompt(system, facts, goals, rows, recentMessages, userMsg);
const reply = await llmChat(prompt); // Gemini Flash-lite for MVP

15) Testing checklist

Retrieval returns sensible memories for 10 random prompts.

Model doesn’t hallucinate private facts (only uses injected memory).

Rate limiting blocks cleanly with clear UI.

Reminders fire on time (including repeating).

Data export produces JSON with messages, facts, goals, reminders.

16) Stretch (after MVP)

Voice I/O (STT/TTS).

Multi-modal memory (images → captions + embeddings).

Agentic tasks (scheduled planning, weekly reviews).

Better reranking (LLM re-rank of retrieved chunks).

Feedback loop (“Was this recall correct?” → raise/lower confidence).

17) What to tell recruiters (one-liner)

“Built a cross-platform AI memory companion (Flutter + Supabase + pgvector + Gemini) with RAG, structured memory (facts/goals), and proactive reminders. Full privacy, per-user rate limits, and a personality layer that calls out inconsistencies.”# eidos
