# Eidos

Eidos is a memory-augmented chat system built with Flutter and Supabase.  
The idea is simple: a personal AI companion that actually remembers who you are, what you’ve said, and what you care about — across every conversation.

Unlike typical chat apps where history is lost or limited, Eidos is designed to build a long-term memory layer. Every interaction is stored, indexed, and retrievable. This turns the chat into more than a messaging app — it becomes a living record of thought, goals, and context.

---

## Features

- **Authentication** — handled via Supabase Auth  
- **Realtime chat** — messages sync instantly using Supabase Realtime  
- **Persistent memory** — all conversations are stored and retrievable  
- **Optimistic UI** — user messages appear immediately, even before server confirmation  
- **AI replies** — powered by Gemini, stored alongside user messages  
- **Structured design** — built on Flutter with Riverpod for reactive state management  

---

## How It Works

When a user sends a message:

1. The message is shown immediately in the UI (optimistic update).  
2. The message is inserted into the `messages` table in Supabase.  
3. The backend (Gemini API) generates a reply.  
4. The reply is inserted back into the `messages` table.  
5. Supabase Realtime streams both user and AI messages back to the client.  

Because the client listens to the realtime stream, the chat stays consistent across devices and sessions. Local placeholders are automatically replaced by server-confirmed rows.

## Database

The app uses two main tables:

- **chats** — stores metadata for each chat session  
- **messages** — stores individual messages linked to a chat and user  