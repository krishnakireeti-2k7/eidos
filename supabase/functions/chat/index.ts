import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.7.1";

const corsHeaders = {
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const genAI = new GoogleGenerativeAI(Deno.env.get("GEMINI_API_KEY")!);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const authHeader = req.headers.get("Authorization")!;
  const { data: { user }, error } = await supabase.auth.getUser(authHeader.replace("Bearer ", ""));
  if (error || !user) return new Response("Unauthorized", { status: 401 });

  const { text } = await req.json();

  // Rate limit (daily check)
  const today = new Date().toISOString().split("T")[0];
  const { data: usage } = await supabase.from("usage").select("*").eq("user_id", user.id).eq("date", today).single();
  let requests = usage ? usage.requests_count : 0;
  if (requests >= 30) {
    return new Response(JSON.stringify({ error: "Daily limit reached", reset: new Date(today + "T23:59:59Z").toISOString() }), {
      status: 429,
      headers: { "Content-Type": "application/json", ...corsHeaders },
    });
  }

  // Store user message
  const { data: msg, error: msgError } = await supabase.from("messages").insert({
    user_id: user.id,
    role: "user",
    text,
    created_at: new Date().toISOString(),
    token_count: Math.ceil(text.length / 4), // Rough estimate
  }).select().single();
  if (msgError) {
    return new Response(JSON.stringify({ error: "Failed to store message" }), { status: 500 });
  }

  // Build prompt and call Gemini
  const systemPrompt = `You are Kireeti’s AI companion: equal parts fun and productive. Priorities: 1) Be honest and direct (call out BS kindly). 2) Help Kireeti achieve goals. Tone: concise, warm, a bit witty. Never patronizing.`;
  const model = genAI.getGenerativeModel({ model: "gemini-1.5-flash" });
  const result = await model.generateContent(`${systemPrompt}\nUser: ${text}\nAssistant:`);
  const reply = result.response.text();

  // Store assistant message
  await supabase.from("messages").insert({
    user_id: user.id,
    role: "assistant",
    text: reply,
    created_at: new Date().toISOString(),
    token_count: Math.ceil(reply.length / 4),
  });

  // Update usage
  if (usage) {
    await supabase.from("usage").update({ requests_count: requests + 1 }).eq("id", usage.id);
  } else {
    await supabase.from("usage").insert({ user_id: user.id, date: today, requests_count: 1 });
  }

  return new Response(JSON.stringify({ reply }), {
    headers: { "Content-Type": "application/json", ...corsHeaders },
  });
});