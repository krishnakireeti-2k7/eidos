import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_CHAT_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";
const GEMINI_EMBED_URL = "https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL"),
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
);

serve(async (req) => {
  try {
    if (!GEMINI_API_KEY) throw new Error("Missing GEMINI_API_KEY");

    const body = await req.json();
    const message = body.message;
    const userId = body.userId;

    if (!message || !userId)
      return new Response(JSON.stringify({ error: "Missing message or userId" }), { status: 400 });

    console.log("---- New Request ----");
    console.log("User ID:", userId);
    console.log("Message:", message);

    // --- 1. Save user message
    const { data: userMsgData, error: userMsgErr } = await supabase
      .from("messages")
      .insert({
        user_id: userId,
        content: message,
        is_user: true,
        created_at: new Date().toISOString()
      })
      .select()
      .single();

    if (userMsgErr) console.error("Failed to save user message:", userMsgErr);
    console.log("User message saved:", userMsgData);

    // --- 2. Embed user message
    const embedRes = await fetch(GEMINI_EMBED_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        model: "models/text-embedding-004",
        content: { parts: [{ text: message }] }
      })
    });

    const embedJson = await embedRes.json();
    const embedding = embedJson?.embedding?.values;
    console.log("User embedding length:", embedding?.length);
    console.log("First 5 values:", embedding?.slice(0, 5));

    // --- 3. Store user memory + embedding
    let userMemoryChunkId: string | null = null;
    if (embedding) {
      const { data: memData, error: memErr } = await supabase
        .from("memory_chunks")
        .insert({
          user_id: userId,
          source_message_id: userMsgData?.id,
          text: message,
          created_at: new Date().toISOString()
        })
        .select()
        .single();

      if (memErr) console.error("Failed to store user memory chunk:", memErr);
      userMemoryChunkId = memData?.id ?? null;
      console.log("User memory chunk saved:", userMemoryChunkId);

      if (userMemoryChunkId) {
        await supabase.from("embeddings").insert({
          memory_chunk_id: userMemoryChunkId,
          embedding: embedding.map(Number), // convert to float[]
          created_at: new Date().toISOString()
        });
        console.log("User embedding stored successfully");
      }
    }

    // --- 4. Retrieve relevant memories
    const { data: memoryMatches, error: memoryErr } = await supabase.rpc("match_memory", {
      query_embedding: embedding,
      match_count: 5,
      match_threshold: 0.75,
      p_user_id: userId
    });
    if (memoryErr) console.error("Memory match error:", memoryErr);
    console.log("Memory matches:", memoryMatches?.length);
    const contextText = memoryMatches?.length
      ? memoryMatches.map((m: any) => m.content).join("\n")
      : "";

    // --- 5. Build Gemini RAG prompt
    const geminiPayload = {
      contents: [
        {
          parts: [
            {
              text: contextText
                ? `Here are some things this user said in the past:\n${contextText}\n\nNow respond to their new message: ${message}`
                : message
            }
          ]
        }
      ]
    };

    // --- 6. Call Gemini
    const geminiRes = await fetch(GEMINI_CHAT_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify(geminiPayload)
    });
    const geminiJson = await geminiRes.json();
    const geminiResponse = geminiJson?.candidates?.[0]?.content?.parts?.[0]?.text ?? "No response from Gemini";
    console.log("Gemini response:", geminiResponse);

    // --- 7. Save Gemini reply
    const { data: gemMsgData, error: gemMsgErr } = await supabase
      .from("messages")
      .insert({
        user_id: userId,
        content: geminiResponse,
        is_user: false,
        created_at: new Date().toISOString()
      })
      .select()
      .single();

    if (gemMsgErr) console.error("Failed to save Gemini message:", gemMsgErr);
    console.log("Gemini message saved:", gemMsgData);

    // --- 8. Embed Gemini reply + store in embeddings
    const replyEmbedRes = await fetch(GEMINI_EMBED_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-goog-api-key": GEMINI_API_KEY },
      body: JSON.stringify({
        model: "models/text-embedding-004",
        content: { parts: [{ text: geminiResponse }] }
      })
    });
    const replyJson = await replyEmbedRes.json();
    const replyEmbedding = replyJson?.embedding?.values;

    if (replyEmbedding && gemMsgData?.id) {
      const { data: replyMemData, error: replyMemErr } = await supabase
        .from("memory_chunks")
        .insert({
          user_id: userId,
          source_message_id: gemMsgData.id,
          text: geminiResponse,
          created_at: new Date().toISOString()
        })
        .select()
        .single();

      if (replyMemErr) console.error("Failed to store Gemini memory chunk:", replyMemErr);
      console.log("Gemini memory chunk saved:", replyMemData?.id);

      if (replyMemData?.id) {
        await supabase.from("embeddings").insert({
          memory_chunk_id: replyMemData.id,
          embedding: replyEmbedding.map(Number),
          created_at: new Date().toISOString()
        });
        console.log("Gemini embedding stored successfully");
      }
    }

    // --- 9. Return Gemini response
    return new Response(JSON.stringify({ response: geminiResponse }), {
      headers: { "Content-Type": "application/json" }
    });
  } catch (err) {
    console.error("Unexpected error:", err);
    return new Response(JSON.stringify({ error: err.message }), { status: 500 });
  }
});
